#include maps\mp\gametypes\global\_global;

/*
	HTTP + WebSocket test harness (zpam 3.36) - libcod proof of implementation

	Exercises EVERY function and EVERY callback pointer, reporting PASS/FAIL
	per case:

	  Functions: httpFetch, webSocketConnect, webSocketSendText, webSocketClose
	  Pointers : onDone, onError (http) + onConnect, onMessage, onClose, onError (ws)

	  httpFetch          HTTPS GET 200 (also proves built-in TLS), POST with
	                     body+header, non-200 status (404 -> onDone not onError),
	                     transport error (DNS -> onError), timeout (-> onError),
	                     response-header parsing, geo-IP lookup. Covers onDone
	                     (all 3 args: status/body/headers) and onError.
	  webSocketConnect   full round-trip that drives every ws function + pointer
	                     in order: connect (return id) -> onConnect -> sendText
	                     (return) -> onMessage -> close (return) -> onClose; plus
	                     onError + auto-reconnect retry loop, reconnect-disabled
	                     single attempt, and send/close guard paths on a bad id

	Server / rcon:
	  set scr_test_http 1     run the whole suite once, print a PASS/FAIL summary
	  set scr_debug_http 0|1  log every callback as it fires (raw activity, default 0)

	Chat command:
	  !geoip [name]     look up your own (or another player's) public IP location
	                    over HTTP and print country / region / city / timezone

	The callbacks run as engine threads with no 'self', so they touch only the
	level.httptest.* state and their passed arguments.

	NOTE: this is a developer-only module. It reaches out to public test
	endpoints (postman-echo.com, ip-api.com), so a box with no outbound internet
	will report the network-dependent cases as FAIL - that is the environment,
	not the functions.
*/

// Public test endpoints
HTTP_GET()    { return "https://postman-echo.com/get"; }
HTTP_POST()   { return "https://postman-echo.com/post"; }
HTTP_404()    { return "https://postman-echo.com/status/404"; }
HTTP_DELAY()  { return "https://postman-echo.com/delay/5"; }
HTTP_BADDNS() { return "https://no-such-host-zpamtest-9x7a.invalid"; }
WS_ECHO()     { return "wss://ws.postman-echo.com/raw"; }
WS_DEAD()     { return "ws://127.0.0.1:1"; }

// ip-api.com is plain HTTP (no TLS) and returns location as JSON
GEO_URL(ip)   { return "http://ip-api.com/json/" + ip; }

init()
{
	level.http_debug = false;

	// Shared state for the suite and the !geoip command; created once so the
	// command works even if the suite has never run
	level.httptest = spawnstruct();
	level.httptest.running = false;
	level.httptest.results = [];

	addEventListener("onCvarChanged", ::onCvarChanged);

	registerCvarEx("I", "scr_debug_http", "BOOL", 0);
	registerCvarEx("I", "scr_test_http", "BOOL", 0);
}

onCvarChanged(cvar, value, isRegisterTime)
{
	switch(cvar)
	{
		case "scr_debug_http":
			level.http_debug = (int(value) != 0);
			return true;

		case "scr_test_http":
			// One-shot: run on a live set to 1, then reset to 0
			if (!isRegisterTime && int(value) != 0)
			{
				thread runSuite();
				changeCvarQuiet("scr_test_http", 0);
			}
			return true;
	}

	return false;
}

// ---------------------------------------------------------------------------
// Logging + result bookkeeping
// ---------------------------------------------------------------------------

// Test output goes to players in-game (iprintln) AND the server console
// (println), so it is visible wherever you are watching.
say(msg)
{
	println(msg);
	iprintln(msg);
}

dbg(msg)
{
	if (level.http_debug)
		say("^7   [dbg] " + msg);
}

// Prints what a test is about to do before it fires: the action, the exact
// endpoint being queried, and what a PASS looks like.
announce(what, query, expect)
{
	say("^5[http test]^7 " + what);
	say("^7   query : " + query);
	say("^7   expect: " + expect);
}

// True if 'needle' occurs anywhere in 'haystack'
strContains(haystack, needle)
{
	hlen = haystack.size;
	nlen = needle.size;

	if (nlen == 0)
		return true;
	if (nlen > hlen)
		return false;

	for (i = 0; i <= hlen - nlen; i += 1)
	{
		if (getsubstr(haystack, i, i + nlen) == needle)
			return true;
	}

	return false;
}

// Records a case result once. Later duplicate callbacks (e.g. reconnect
// retries) are ignored so a test cannot flip its own verdict.
record(name, passed, detail)
{
	if (!isDefined(level.httptest.results))
		level.httptest.results = [];

	if (isDefined(level.httptest.results[name]))
		return;

	result = "PASS";
	if (!passed)
		result = "FAIL";

	level.httptest.results[name] = result;

	tag = "^2 PASS ^7";
	if (!passed)
		tag = "^1 FAIL ^7";

	line = "^5[http test]^7" + tag + name;
	if (isDefined(detail) && detail != "")
		line = line + " - " + detail;

	say(line);
}

// ---------------------------------------------------------------------------
// Suite driver
// ---------------------------------------------------------------------------

runSuite()
{
	level endon("intermission");

	if (level.httptest.running)
	{
		iprintln("^3[http test]^7 already running - wait for the current run to finish");
		return;
	}

	level.httptest.running = true;
	level.httptest.results = [];

	say(" ");
	say("^5=========== HTTP / WebSocket test suite ===========");
	say("^7Each case prints what it queries and what to expect, then a PASS/FAIL line.");
	say("^7WebSocket note: the echo test uses a PUBLIC server (no local server needed);");
	say("^7the reconnect tests hit a dead port ON PURPOSE to prove error/retry handling.");
	say("^7Set scr_debug_http 1 for extra per-callback detail. Running now...");
	say(" ");

	// Independent HTTP cases fire together; each reports via its own callbacks
	thread test_get();
	thread test_post();
	thread test_404();
	thread test_baddns();
	wait 8;

	// Timeout needs its own window: 5s server delay against a 2s timeout
	thread test_timeout();
	wait 8;

	// Geo-IP round trip over plain HTTP
	thread test_geoip();
	wait 8;

	// Synchronous guard-path check (no network) - runs instantly
	test_ws_badid();
	wait 1;

	// WebSocket full round-trip: exercises every ws function + pointer
	thread test_ws_echo();
	wait 12;

	// WebSocket error + reconnect retry loop
	thread test_ws_reconnect();
	wait 9;

	// WebSocket single attempt when reconnect is disabled
	thread test_ws_noreconnect();
	wait 7;

	summary();
	level.httptest.running = false;
}

summary()
{
	names = [];
	names[names.size] = "get200";
	names[names.size] = "post";
	names[names.size] = "headers";
	names[names.size] = "status404";
	names[names.size] = "baddns";
	names[names.size] = "timeout";
	names[names.size] = "geoip";
	names[names.size] = "ws_sendtext_badid";
	names[names.size] = "ws_close_badid";
	names[names.size] = "ws_connect_ret";
	names[names.size] = "ws_onconnect";
	names[names.size] = "ws_sendtext";
	names[names.size] = "ws_onmessage";
	names[names.size] = "ws_close_ret";
	names[names.size] = "ws_onclose";
	names[names.size] = "ws_reconnect";
	names[names.size] = "ws_noreconnect";

	passed = 0;
	failed = 0;
	missing = 0;

	say(" ");
	say("^5=========== summary ===========");
	for (i = 0; i < names.size; i += 1)
	{
		n = names[i];
		r = level.httptest.results[n];
		if (!isDefined(r))
		{
			missing += 1;
			say("^3 ---- ^7" + n + " (no result - callback never fired, likely no network)");
		}
		else if (r == "PASS")
			passed += 1;
		else
			failed += 1;
	}

	say("^5[http test]^7 " + passed + " ^2passed^7, " + failed + " ^1failed^7, " + missing + " missing (of " + names.size + ")");
	say(" ");
	say("^5coverage:^7 functions - httpFetch, webSocketConnect, webSocketSendText, webSocketClose");
	say("^7          pointers  - onDone, onError (http) + onConnect, onMessage, onClose, onError (ws)");
	say("^7 get200/post/status404/geoip = onDone | baddns/timeout = onError");
	say("^7 ws_connect_ret/onconnect/sendtext/onmessage/close_ret/onclose = full ws round-trip");
	say("^7 ws_reconnect/noreconnect = ws onError + retry policy | *_badid = guard paths");
}

// ---------------------------------------------------------------------------
// httpFetch cases
// ---------------------------------------------------------------------------

test_get()
{
	announce("httpFetch GET over HTTPS (also proves built-in TLS works)", HTTP_GET(), "onDone with HTTP status 200, plus a string-keyed response-headers array");
	httpFetch(HTTP_GET(), "GET", "", "", 8000, ::onGetDone, ::onGetError);
}

onGetDone(status, body, headers)
{
	dbg("GET done status=" + status + " bodylen=" + body.size);
	record("get200", status == 200, "status " + status);

	// Response-header parsing: the array must be string-keyed and populated.
	// Match content-type case-insensitively so header casing does not matter.
	found = "";
	if (isDefined(headers))
	{
		keys = getArrayKeys(headers);
		if (isDefined(keys))
		{
			for (i = 0; i < keys.size; i += 1)
			{
				if (tolower(keys[i]) == "content-type")
				{
					found = keys[i];
					break;
				}
			}
		}
	}

	got = (found != "");
	if (got)
		record("headers", true, found + "=" + headers[found]);
	else
		record("headers", false, "content-type not in response headers");
}

onGetError(error)
{
	record("get200", false, "onError: " + error);
	record("headers", false, "no response");
}

test_post()
{
	body = "{\"zpam\":\"verindra\",\"n\":42}";
	announce("httpFetch POST with a JSON body + Content-Type header", HTTP_POST() + " body=" + body, "status 200 and the server echoes our body back (contains 'verindra')");
	httpFetch(HTTP_POST(), "POST", body, "Content-Type: application/json", 8000, ::onPostDone, ::onPostError);
}

onPostDone(status, body, headers)
{
	dbg("POST done status=" + status + " bodylen=" + body.size);
	// postman-echo echoes our payload back inside its JSON response
	echoed = strContains(body, "verindra");
	record("post", status == 200 && echoed, "status " + status + " echoed=" + echoed);
}

onPostError(error)
{
	record("post", false, "onError: " + error);
}

test_404()
{
	announce("httpFetch to a URL that returns HTTP 404", HTTP_404(), "onDone with status 404 (a 404 is a valid reply, NOT a transport error)");
	httpFetch(HTTP_404(), "GET", "", "", 8000, ::on404Done, ::on404Error);
}

on404Done(status, body, headers)
{
	// A 404 is a valid HTTP response, NOT a transport error: onDone must fire
	dbg("404 case done status=" + status);
	record("status404", status == 404, "status " + status);
}

on404Error(error)
{
	record("status404", false, "wrongly routed to onError: " + error);
}

test_baddns()
{
	announce("httpFetch to a hostname that cannot resolve (error path)", HTTP_BADDNS(), "onError fires with a resolve/connect failure message (PASS = onError, not onDone)");
	httpFetch(HTTP_BADDNS(), "GET", "", "", 8000, ::onBadDnsDone, ::onBadDnsError);
}

onBadDnsDone(status, body, headers)
{
	record("baddns", false, "unexpected success status " + status);
}

onBadDnsError(error)
{
	// Expected path: a resolve/connect failure must reach onError
	dbg("baddns onError: " + error);
	record("baddns", true, error);
}

test_timeout()
{
	announce("httpFetch with a 2s timeout against a server that waits 5s (timeout path)", HTTP_DELAY() + " (timeout 2000ms)", "onError fires with a timeout message (PASS = onError, not onDone)");
	httpFetch(HTTP_DELAY(), "GET", "", "", 2000, ::onTimeoutDone, ::onTimeoutError);
}

onTimeoutDone(status, body, headers)
{
	record("timeout", false, "unexpected success status " + status);
}

onTimeoutError(error)
{
	dbg("timeout onError: " + error);
	record("timeout", true, error);
}

// ---------------------------------------------------------------------------
// Geo-IP lookup (plain HTTP round trip that resolves a real IP to a location)
// ---------------------------------------------------------------------------

test_geoip()
{
	// A well-known public IP so the suite does not depend on a connected player
	announce("geo-IP lookup over plain HTTP (locate an IP address)", GEO_URL("8.8.8.8") + " (8.8.8.8 = Google DNS)", "status 200 and JSON with a country field (expected: United States)");
	httpFetch(GEO_URL("8.8.8.8"), "GET", "", "", 8000, ::onGeoDone, ::onGeoError);
}

onGeoDone(status, body, headers)
{
	dbg("geoip done status=" + status + " body=" + body);
	country = jsonStr(body, "country");
	ok = (status == 200 && isDefined(country) && country != "");
	record("geoip", ok, "country=" + country);
}

onGeoError(error)
{
	record("geoip", false, "onError: " + error);
}

// Extracts a string value for a JSON key, e.g. jsonStr("...\"city\":\"Ashburn\"...", "city").
// A tiny scanner - this build has no json_parse - good enough for flat replies.
jsonStr(body, key)
{
	needle = "\"" + key + "\":\"";
	start = -1;
	nlen = needle.size;
	blen = body.size;

	if (nlen >= blen)
		return "";

	for (i = 0; i <= blen - nlen; i += 1)
	{
		if (getsubstr(body, i, i + nlen) == needle)
		{
			start = i + nlen;
			break;
		}
	}

	if (start == -1)
		return "";

	for (j = start; j < blen; j += 1)
	{
		if (getsubstr(body, j, j + 1) == "\"")
			return getsubstr(body, start, j);
	}

	return "";
}

// ---------------------------------------------------------------------------
// Live chat command: !geoip [partial name]
// ---------------------------------------------------------------------------

onGeoCommand(args)
{
	self endon("disconnect");

	target = self;
	if (isDefined(args[2]))
	{
		target = findPlayer(args[2]);
		if (!isDefined(target))
		{
			self iprintln("^3[geoip]^7 no player matching '" + args[2] + "'");
			return;
		}
	}

	ip = target getIP();
	if (!isDefined(ip) || ip == "" || ip == "0.0.0.0")
	{
		self iprintln("^3[geoip]^7 " + target.name + " ^7has no resolvable IP (bot or loopback)");
		return;
	}

	self iprintln("^5[geoip]^7 " + target.name + " ^7ip " + ip + " -> querying " + GEO_URL(ip));
	self iprintln("^7   (fetching over plain HTTP from ip-api.com, please wait...)");
	self thread geoLookup(ip, target.name);
}

geoLookup(ip, who)
{
	self endon("disconnect");
	// Capture the asker in a field the callback can read (callbacks have no self)
	level.httptest.geo_asker = self;
	level.httptest.geo_who = who;
	httpFetch(GEO_URL(ip), "GET", "", "", 8000, ::onGeoCmdDone, ::onGeoCmdError);
}

onGeoCmdDone(status, body, headers)
{
	asker = level.httptest.geo_asker;
	if (!isDefined(asker))
		return;

	if (status != 200)
	{
		asker iprintln("^3[geoip]^7 lookup failed, HTTP " + status);
		return;
	}

	country = jsonStr(body, "country");
	region = jsonStr(body, "regionName");
	city = jsonStr(body, "city");
	tz = jsonStr(body, "timezone");

	if (country == "")
	{
		asker iprintln("^3[geoip]^7 no location data returned");
		return;
	}

	asker iprintln("^2[geoip]^7 " + level.httptest.geo_who + "^7: " + city + ", " + region + ", " + country + " ^7(" + tz + ")");
}

onGeoCmdError(error)
{
	asker = level.httptest.geo_asker;
	if (isDefined(asker))
		asker iprintln("^3[geoip]^7 lookup error: " + error);
}

// Resolve a player by case-insensitive partial name
findPlayer(needle)
{
	players = getentarray("player", "classname");
	needle = tolower(needle);

	for (i = 0; i < players.size; i += 1)
	{
		if (strContains(tolower(players[i].name), needle))
			return players[i];
	}

	return undefined;
}

// ---------------------------------------------------------------------------
// WebSocket cases
// ---------------------------------------------------------------------------

// The echo round-trip drives, in order, EVERY websocket function and pointer:
//   webSocketConnect (return id) -> onConnect -> webSocketSendText (return) ->
//   onMessage (getText) -> webSocketClose (return) -> onClose
test_ws_echo()
{
	level.httptest.ws_echo_id = -1;
	level.httptest.ws_echo_token = "zpam-echo-7788";
	announce("webSocket full round-trip: connect, onConnect, sendText, onMessage, close, onClose (PUBLIC echo, no local server)", WS_ECHO(), "each step records its own PASS: connect id >= 0, onConnect fires, sendText returns true, onMessage echoes our token, close returns true, onClose fires");

	// reconnect 0 (single shot), default ping interval
	id = webSocketConnect(WS_ECHO(), "", ::onEchoConnect, ::onEchoMessage, ::onEchoClose, ::onEchoError, 0, 15000);
	level.httptest.ws_echo_id = id;
	record("ws_connect_ret", id >= 0, "webSocketConnect returned id " + id);
	dbg("WS echo id=" + id);
}

onEchoConnect()
{
	// Proves the onConnect pointer fires
	record("ws_onconnect", true, "onConnect fired");

	// Proves webSocketSendText and its return value (true while connected)
	sent = webSocketSendText(level.httptest.ws_echo_id, level.httptest.ws_echo_token);
	record("ws_sendtext", sent == true, "webSocketSendText returned " + sent);
	dbg("WS echo connected, sent token, sendText=" + sent);
}

onEchoMessage(message)
{
	dbg("WS echo recv: " + message);
	// Ignore any server greeting; only our exact token counts as the round-trip.
	// This proves the onMessage pointer delivers received text intact.
	if (message == level.httptest.ws_echo_token)
	{
		record("ws_onmessage", true, "received our token back: " + message);

		// Proves webSocketClose and its return value, then triggers onClose
		closed = webSocketClose(level.httptest.ws_echo_id);
		record("ws_close_ret", closed == true, "webSocketClose returned " + closed);
	}
}

onEchoClose(closedByRemote, fullyDisconnected)
{
	// Proves the onClose pointer fires with its two booleans
	dbg("WS echo close remote=" + closedByRemote + " fully=" + fullyDisconnected);
	record("ws_onclose", fullyDisconnected, "remote=" + closedByRemote + " fully=" + fullyDisconnected);
}

onEchoError(error)
{
	// If the connection never establishes, fail the whole chain clearly rather
	// than leaving each dependent pointer as 'missing'. record() keeps the first
	// verdict, so any step that already passed is untouched.
	dbg("WS echo error: " + error);
	record("ws_onconnect", false, "onError before connect: " + error);
	record("ws_sendtext", false, "connection failed");
	record("ws_onmessage", false, "connection failed");
	record("ws_close_ret", false, "connection failed");
	record("ws_onclose", false, "connection failed");
}

test_ws_reconnect()
{
	level endon("intermission");
	level.httptest.ws_recon_errors = 0;
	announce("webSocket onError + auto-reconnect (connects to a DEAD port ON PURPOSE)", WS_DEAD() + " (nothing listens there - the failure is expected)", "onError fires, then it retries every 1.5s; PASS = 2 or more onError seen within 5s");
	// reconnect 1500ms: the failed connect must retry, firing onError each round
	level.httptest.ws_recon_id = webSocketConnect(WS_DEAD(), "", ::onReconConnect, ::onReconMessage, ::onReconClose, ::onReconError, 1500, 0);

	// Give it ~5s to accumulate retries, then stop and grade
	wait 5;
	webSocketClose(level.httptest.ws_recon_id);
	// >=2 onError callbacks proves the reconnect loop retried, not just failed once
	record("ws_reconnect", level.httptest.ws_recon_errors >= 2, level.httptest.ws_recon_errors + " retries observed");
}

onReconConnect() { }
onReconMessage(message) { }
onReconClose(closedByRemote, fullyDisconnected) { }

onReconError(error)
{
	level.httptest.ws_recon_errors += 1;
	dbg("WS reconnect onError #" + level.httptest.ws_recon_errors + ": " + error);
}

test_ws_noreconnect()
{
	level endon("intermission");
	level.httptest.ws_norecon_errors = 0;
	announce("webSocket with reconnect DISABLED (dead port, reconnect=0)", WS_DEAD() + " (nothing listens there - the failure is expected)", "exactly ONE onError, then it gives up - no retry loop; PASS = exactly 1 error in 5s");
	// reconnect 0: exactly one failed attempt, then the slot is reaped
	level.httptest.ws_norecon_id = webSocketConnect(WS_DEAD(), "", ::onNoReconConnect, ::onNoReconMessage, ::onNoReconClose, ::onNoReconError, 0, 0);

	wait 5;
	// Exactly one onError and no retry loop
	record("ws_noreconnect", level.httptest.ws_norecon_errors == 1, level.httptest.ws_norecon_errors + " error(s) - expected 1");
}

onNoReconConnect() { }
onNoReconMessage(message) { }
onNoReconClose(closedByRemote, fullyDisconnected) { }

onNoReconError(error)
{
	level.httptest.ws_norecon_errors += 1;
	dbg("WS noreconnect onError #" + level.httptest.ws_norecon_errors + ": " + error);
}

// Synchronous guard-path check: the send/close functions must reject an id that
// has no live connection by returning false, never crash. No network involved.
test_ws_badid()
{
	announce("webSocketSendText / webSocketClose on a bogus id (guard paths)", "id 999 (no such connection)", "both return false without erroring");

	s = webSocketSendText(999, "should not send");
	record("ws_sendtext_badid", s == false, "webSocketSendText(999) returned " + s);

	c = webSocketClose(999);
	record("ws_close_badid", c == false, "webSocketClose(999) returned " + c);
}
