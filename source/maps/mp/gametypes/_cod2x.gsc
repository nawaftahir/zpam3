#include maps\mp\gametypes\global\_global;

/*
	CoD2x client identity (zpam 3.36) - libcod HWID proof of implementation

	Demonstrates the CoD2x identity script methods ported into zk_libcod:

	  <player> getHWID()           the 32-bit FNV-1a(cl_hwid2) value - the exact GUID
	                               CoD2x's own server derives at connect and bans on.
	                               0 for stock / 1.x clients and bots.
	  <player> getCod2xProtocol()  the client's CoD2x version (0 = not a CoD2x client).

	Both values are client-controlled and unauthenticated, so this is a best-effort
	identity signal only, never a trust anchor.

	Wiring:
	  global\_init::InitModules()  -> thread maps\mp\gametypes\_cod2x::init();
	  _callbacksetup.gsc           -> CodeCallback_PlayerCommand routes !hwid / !gethwid here.

	Chat commands (normal chat):
	  !hwid              report your own CoD2x identity
	  !gethwid <name>    report another player's identity (partial name, case-insensitive)

	Server / rcon:
	  set scr_cod2x_debug 0|1   log every client's identity to the console on connect (default 0)
	  set scr_test_cod2x 1      run the self-test, print a passed/failed summary, then reset to 0

	CoD2x reference - how the server derives the HWID this reads:
	  https://github.com/callofduty2x/CoD2x/blob/d8c54695a5239ac99d1dfe96212b809b1a54bfee/src/shared/server.cpp#L427-L444
*/

// CoD2x's own "is a CoD2x client" test is protocol_cod2x >= APP_VERSION_PROTOCOL,
// currently 6 (src/shared/server.cpp). Kept here so it tracks that constant.
COD2X_MIN_PROTOCOL()
{
	return 6;
}

init()
{
	level.cod2x_debug = false;

	addEventListener("onCvarChanged", ::onCvarChanged);
	addEventListener("onConnected", ::onConnected);

	registerCvarEx("I", "scr_cod2x_debug", "BOOL", 0);
	registerCvarEx("I", "scr_test_cod2x", "BOOL", 0);
}

onCvarChanged(cvar, value, isRegisterTime)
{
	switch(cvar)
	{
		case "scr_cod2x_debug":
			level.cod2x_debug = (int(value) != 0);
			return true;

		case "scr_test_cod2x":
			// One-shot trigger: run on a live set to 1, then reset to 0.
			if (!isRegisterTime && int(value) != 0)
			{
				runSelfTest();
				changeCvarQuiet("scr_test_cod2x", 0);
			}
			return true;
	}

	return false;
}

// Fired on the connecting player (self = player). Cache the identity once and,
// in debug, log it so a CoD2x connect can be confirmed on every join.
onConnected()
{
	self endon("disconnect");

	self.cod2x_protocol = self getCod2xProtocol();
	self.cod2x_hwid = self getHWID();

	if (level.cod2x_debug)
	{
		if (self isCod2xClient())
			println("[COD2X] " + self.name + " connected: CoD2x proto " + self.cod2x_protocol + ", hwid " + self.cod2x_hwid);
		else
			println("[COD2X] " + self.name + " connected: not a CoD2x client");
	}
}

// CoD2x's exact server-side check: a genuine CoD2x client advertises
// protocol_cod2x >= 6.
isCod2xClient()
{
	return (self getCod2xProtocol() >= COD2X_MIN_PROTOCOL());
}

// Report one player's identity to 'self' (the caller who issued the command).
reportIdentity(target)
{
	if (target isCod2xClient())
		self iprintln("^2CoD2x^7: " + target.name + " ^7- proto " + target getCod2xProtocol() + ", hwid " + target getHWID());
	else
		self iprintln("^3CoD2x^7: " + target.name + " ^7is not a CoD2x client");
}

// Routed from CodeCallback_PlayerCommand for !hwid and !gethwid.
onPlayerCommand(args)
{
	self endon("disconnect");

	cmd = tolower(args[1]);

	if (cmd == "!hwid")
	{
		self reportIdentity(self);
		return;
	}

	// !gethwid <name>
	if (!isDefined(args[2]))
	{
		self iprintln("^3CoD2x^7: usage: !gethwid <player name>");
		return;
	}

	target = findPlayer(args[2]);
	if (!isDefined(target))
	{
		self iprintln("^3CoD2x^7: no player matching '" + args[2] + "'");
		return;
	}

	self reportIdentity(target);
}

// Resolve a player by case-insensitive partial name.
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

// True if 'needle' occurs anywhere in 'haystack'.
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

// scr_test_cod2x 1 - assert the methods behave and print a passed/failed summary.
runSelfTest()
{
	passed = 0;
	failed = 0;

	players = getentarray("player", "classname");

	iprintln("^5[COD2X TEST]^7 running over " + players.size + " player(s)");

	for (i = 0; i < players.size; i += 1)
	{
		p = players[i];
		proto = p getCod2xProtocol();
		hwid = p getHWID();

		// A CoD2x client (proto >= 6) must expose a non-zero hwid; a non-CoD2x
		// client or bot must report proto 0 and hwid 0.
		if (proto >= COD2X_MIN_PROTOCOL())
		{
			if (hwid != "")
				passed += 1;
			else
			{
				failed += 1;
				iprintln("^1[COD2X TEST] FAIL^7 " + p.name + ": CoD2x proto " + proto + " but empty hwid");
			}
		}
		else
		{
			if (proto == 0 && hwid == "")
				passed += 1;
			else
			{
				failed += 1;
				iprintln("^1[COD2X TEST] FAIL^7 " + p.name + ": non-CoD2x but proto " + proto + " / hwid " + hwid);
			}
		}
	}

	iprintln("^5[COD2X TEST]^7 " + passed + " passed, " + failed + " failed");
}
