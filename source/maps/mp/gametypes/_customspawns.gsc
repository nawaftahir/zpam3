#include maps\mp\gametypes\global\_global;

/*
	Custom Spawns (zpam 3.36)

	Per-map spawn points stored on disk with the native zk_libcod JSON functions
	(json_load / json_save). Points live in customspawns/<map>.json and are applied
	at spawn time. A mode cvar selects how they combine with the map's stock spawns,
	an in-game chat editor places and removes them live, autosave writes and re-reads
	them asynchronously on every edit, and a debug mode marks spawns in the world and
	announces when a player actually spawns on a custom point.

	Wiring:
	  global\_init::InitModules()  -> thread maps\mp\gametypes\_customspawns::init();
	  <gametype> spawn selection   -> maps\mp\gametypes\_customspawns::getSpawnpoints(name);
	  _callbacksetup.gsc           -> CodeCallback_PlayerCommand routes "!cs ..." here.

	Modes (scr_customspawns_mode):
	  0  stock spawns only (default - no change to map behaviour)
	  1  custom spawns only (falls back to stock for a team with none defined)
	  2  stock and custom spawns combined

	Chat editor (normal chat, prefix !cs):
	  !cs add [allies|axis]   place a spawn where you stand (defaults to your team)
	  !cs del                 remove the nearest custom spawn
	  !cs save                write the spawns to customspawns/<map>.json
	  !cs load                re-read the file from disk
	  !cs clear               remove every custom spawn (save to persist)
	  !cs mode <0|1|2>        change the spawn mode
	  !cs autosave            toggle async save + reload on every edit
	  !cs debug               toggle custom-spawn markers + spawn announcements
	  !cs debug stock         toggle stock-spawn markers
	  !cs stats               report custom vs stock spawns used this map
	  !cs dump                print spawns as json (json_stringify + json_parse)
	  !cs list                report counts and the active mode

	Server / rcon:
	  set scr_customspawns_mode 0|1|2
	  set scr_customspawns_capture 1   snapshot the map's stock spawns into json
	  set scr_customspawns_autosave 0|1
	  set scr_customspawns_debug 0|1
	  set scr_customspawns_debugstock 0|1
	  set scr_customspawns_edit 0|1    allow players to use the chat editor (default 1)
*/

init()
{
	// Register cvars after this state exists - onCvarChanged fires during registration.
	level.cs_classAllies = "mp_ctf_spawn_allied";
	level.cs_classAxis = "mp_ctf_spawn_axis";
	level.cs_classes = [];
	level.cs_classes[0] = level.cs_classAllies;
	level.cs_classes[1] = level.cs_classAxis;

	level.cs_mode = 0;
	level.cs_edit = true;
	level.cs_autosave = false;
	level.cs_debug = false;
	level.cs_debugStock = false;
	level.cs_savePending = false;
	level.cs_pollerRunning = false;
	level.cs_jobsPending = 0;

	level.cs_countCustom = 0;
	level.cs_countStock = 0;

	level.cs_data = [];
	level.cs_spawns = [];
	level.cs_markers = [];
	level.cs_jobKind = []; // async jobId -> "save" | "load"

	level.cs_markerModel = "xmodel/prop_flag_base"; // custom markers
	level.cs_markerModelStock = "xmodel/mp_tntbomb"; // stock markers (distinct)
	precacheModel(level.cs_markerModel);
	precacheModel(level.cs_markerModelStock);

	addEventListener("onStartGameType", ::onStartGameType);
	addEventListener("onCvarChanged", ::onCvarChanged);
	addEventListener("onSpawnedPlayer", ::onSpawnedPlayer);

	registerCvarEx("I", "scr_customspawns_mode", "INT", 0, 0, 2);
	registerCvarEx("I", "scr_customspawns_capture", "BOOL", 0);
	registerCvarEx("I", "scr_customspawns_autosave", "BOOL", 0);
	registerCvarEx("I", "scr_customspawns_debug", "BOOL", 0);
	registerCvarEx("I", "scr_customspawns_debugstock", "BOOL", 0);
	registerCvarEx("I", "scr_customspawns_edit", "BOOL", 1);
}

onStartGameType()
{
	level.cs_countCustom = 0;
	level.cs_countStock = 0;
	loadSpawns();
}

onCvarChanged(cvar, value, isRegisterTime)
{
	switch(cvar)
	{
		case "scr_customspawns_mode":
			level.cs_mode = int(value);
			return true;

		case "scr_customspawns_edit":
			level.cs_edit = (int(value) != 0);
			return true;

		case "scr_customspawns_autosave":
			level.cs_autosave = (int(value) != 0);
			return true;

		case "scr_customspawns_debug":
			level.cs_debug = (int(value) != 0);
			refreshMarkers();
			return true;

		case "scr_customspawns_debugstock":
			level.cs_debugStock = (int(value) != 0);
			refreshMarkers();
			return true;

		case "scr_customspawns_capture":
			if (!isRegisterTime && int(value) != 0)
			{
				captureSpawns();
				changeCvarQuiet("scr_customspawns_capture", 0);
			}
			return true;
	}
	return false;
}

// Count custom vs stock spawns and (in debug) announce custom ones.
onSpawnedPlayer()
{
	self endon("disconnect");

	team = "axis";
	if (isDefined(self.pers["team"]) && self.pers["team"] == "allies")
		team = "allies";

	index = -1;
	if (level.cs_mode != 0)
		index = nearestCustomIndex(self.origin, teamClass(team));

	if (index >= 0)
	{
		level.cs_countCustom += 1;
		if (level.cs_debug)
		{
			self iprintln("^2Custom Spawns: ^7you spawned at " + team + " point #" + index);
			csConsole(self.name + " spawned at custom " + team + " point #" + index);
		}
	}
	else
		level.cs_countStock += 1;
}

// ---------------------------------------------------------------------------
// Spawn selection hook - the gametype calls this instead of getentarray().
// ---------------------------------------------------------------------------
getSpawnpoints(classname)
{
	stock = getentarray(classname, "classname");

	custom = [];
	if (isDefined(level.cs_spawns) && isDefined(level.cs_spawns[classname]))
		custom = level.cs_spawns[classname];

	if (level.cs_mode == 0 || custom.size == 0)
		return stock;

	if (level.cs_mode == 1)
		return custom;

	merged = [];
	for (i = 0; i < stock.size; i++)
		merged[merged.size] = stock[i];
	for (i = 0; i < custom.size; i++)
		merged[merged.size] = custom[i];
	return merged;
}

// ---------------------------------------------------------------------------
// Persistence (json_load / json_save)
// ---------------------------------------------------------------------------
loadSpawns()
{
	mapname = getCvar("mapname");
	level.cs_data = [];

	data = json_load("customspawns/" + mapname + ".json");
	if (!isDefined(data))
	{
		csConsole("no saved spawns for " + mapname + " (stock spawns active)");
		rebuildSpawns();
		return;
	}

	total = 0;
	for (c = 0; c < level.cs_classes.size; c++)
	{
		classname = level.cs_classes[c];
		clean = [];
		list = data[classname];
		if (isDefined(list))
		{
			for (i = 0; i < list.size; i++)
			{
				entry = list[i];
				if (!isDefined(entry) || !isDefined(entry["o"]))
					continue;
				clean[clean.size] = entry;
				total += 1;
			}
		}
		level.cs_data[classname] = clean;
	}

	rebuildSpawns();
	csConsole("json_load: " + total + " spawns from customspawns/" + mapname + ".json");
}

saveSpawns()
{
	mapname = getCvar("mapname");
	out = buildSaveData();
	total = countData(out);

	ok = json_save("customspawns/" + mapname + ".json", out, 1);
	if (isDefined(ok) && ok == 1)
		csConsole("json_save: " + total + " spawns to customspawns/" + mapname + ".json");
	else
		csConsole("json_save FAILED for " + mapname);

	return total;
}

// Build the on-disk structure { classname: [ {o,y}, ... ] } from cs_data.
buildSaveData()
{
	out = [];
	for (c = 0; c < level.cs_classes.size; c++)
	{
		classname = level.cs_classes[c];
		list = level.cs_data[classname];
		if (!isDefined(list))
			list = [];
		out[classname] = list;
	}
	return out;
}

// Count spawn entries across both teams in a save/loaded structure.
countData(data)
{
	if (!isDefined(data))
		return 0;

	n = 0;
	for (c = 0; c < level.cs_classes.size; c++)
	{
		list = data[level.cs_classes[c]];
		if (isDefined(list))
			n += list.size;
	}
	return n;
}

// rcon: snapshot the map's stock spawns into json as a starting point to edit.
captureSpawns()
{
	level.cs_data = [];
	total = 0;

	for (c = 0; c < level.cs_classes.size; c++)
	{
		classname = level.cs_classes[c];
		ents = getentarray(classname, "classname");

		list = [];
		for (i = 0; i < ents.size; i++)
		{
			o = ents[i].origin;
			coords = [];
			coords[0] = o[0];
			coords[1] = o[1];
			coords[2] = o[2];

			entry = [];
			entry["o"] = coords;
			entry["y"] = ents[i].angles[1];
			list[i] = entry;
		}
		level.cs_data[classname] = list;
		total += ents.size;
	}

	rebuildSpawns();
	saveSpawns();
	csConsole("captured " + total + " stock spawns");
}

// Autosave: debounced and fully asynchronous. Submits json_save_async, then the
// poller (json_async_done / json_async_result) claims it and chains a
// json_load_async round-trip - exercising the whole async API on every edit
// without blocking the main script VM. Manual !cs save/load stay synchronous.
scheduleAutoSave()
{
	if (!level.cs_autosave || level.cs_savePending)
		return;
	level.cs_savePending = true;
	level thread autoSaveDebounce();
}

autoSaveDebounce()
{
	level endon("intermission");
	wait level.frame * 0.1; // batch rapid edits into one round-trip
	level.cs_savePending = false;
	submitAsyncSave();
}

submitAsyncSave()
{
	mapname = getCvar("mapname");
	jobId = json_save_async("customspawns/" + mapname + ".json", buildSaveData(), 1);
	if (jobId > 0)
		registerJob(jobId, "save");
	else
		csConsole("json_save_async submission failed");
}

registerJob(jobId, kind)
{
	level.cs_jobKind[jobId] = kind;
	level.cs_jobsPending += 1;
	startAsyncPoller();
}

startAsyncPoller()
{
	if (level.cs_pollerRunning)
		return;
	level.cs_pollerRunning = true;
	level thread asyncPoller();
}

// Poll-and-drain, mirroring libcod's mysql_async usage. Runs only while jobs
// are in flight, then stops; a new submission restarts it.
asyncPoller()
{
	level endon("intermission");
	for (;;)
	{
		wait level.frame * 0.1;

		done = json_async_done();
		for (i = 0; i < done.size; i++)
			handleAsyncJob(done[i]);

		if (level.cs_jobsPending <= 0)
			break;
	}
	level.cs_pollerRunning = false;
}

handleAsyncJob(jobId)
{
	if (!isDefined(level.cs_jobKind[jobId]))
		return; // not one of ours

	kind = level.cs_jobKind[jobId];
	level.cs_jobKind[jobId] = undefined;
	level.cs_jobsPending -= 1;

	result = json_async_result(jobId); // claims + frees the job

	if (kind == "save")
	{
		// save finished - chain an async load to verify the round-trip
		mapname = getCvar("mapname");
		loadId = json_load_async("customspawns/" + mapname + ".json");
		if (loadId > 0)
			registerJob(loadId, "load");
	}
	else
		iprintln("^5Custom Spawns: ^7async save + reload verified " + countData(result) + " points (json_*_async)");
}

// ---------------------------------------------------------------------------
// Spawn entities + world markers
// ---------------------------------------------------------------------------

// Recreate the script_origin spawn entities from level.cs_data and refresh the
// debug markers. Called after every edit so the live spawns always match data.
rebuildSpawns()
{
	for (c = 0; c < level.cs_classes.size; c++)
	{
		classname = level.cs_classes[c];
		if (isDefined(level.cs_spawns[classname]))
		{
			old = level.cs_spawns[classname];
			for (i = 0; i < old.size; i++)
			{
				if (isDefined(old[i]))
					old[i] delete();
			}
		}
	}
	level.cs_spawns = [];

	for (c = 0; c < level.cs_classes.size; c++)
	{
		classname = level.cs_classes[c];
		made = [];
		data = level.cs_data[classname];
		if (isDefined(data))
		{
			for (i = 0; i < data.size; i++)
			{
				entry = data[i];
				o = entry["o"];
				yaw = 0;
				if (isDefined(entry["y"]))
					yaw = entry["y"];

				e = spawn("script_origin", (o[0], o[1], o[2]));
				e.angles = (0, yaw, 0);
				e placeSpawnpoint(); // snap to ground
				made[made.size] = e;
			}
		}
		level.cs_spawns[classname] = made;
	}

	refreshMarkers();
}

// Debug markers: a model at each spawn (custom = flag base, stock = bomb).
refreshMarkers()
{
	for (i = 0; i < level.cs_markers.size; i++)
	{
		if (isDefined(level.cs_markers[i]))
			level.cs_markers[i] delete();
	}
	level.cs_markers = [];

	for (c = 0; c < level.cs_classes.size; c++)
	{
		classname = level.cs_classes[c];

		if (level.cs_debug && isDefined(level.cs_spawns[classname]))
			addMarkers(level.cs_spawns[classname], level.cs_markerModel);

		if (level.cs_debugStock)
			addMarkers(getentarray(classname, "classname"), level.cs_markerModelStock);
	}
}

addMarkers(list, model)
{
	if (!isDefined(list))
		return;

	for (i = 0; i < list.size; i++)
	{
		if (!isDefined(list[i]))
			continue;
		m = spawn("script_model", list[i].origin);
		m.angles = list[i].angles;
		m setModel(model);
		level.cs_markers[level.cs_markers.size] = m;
	}
}

// ---------------------------------------------------------------------------
// In-game chat editor (routed from CodeCallback_PlayerCommand). self = player.
// ---------------------------------------------------------------------------
onPlayerCommand(args)
{
	self endon("disconnect");

	if (!isDefined(args) || !isDefined(args[2]))
	{
		self csHelp();
		return;
	}

	if (!level.cs_edit)
	{
		self iprintln("^1Custom Spawns: ^7editing is disabled (scr_customspawns_edit 0)");
		return;
	}

	sub = tolower(args[2]);
	param = "";
	if (isDefined(args[3]))
		param = tolower(args[3]);

	switch(sub)
	{
		case "add":
			self csAdd(param);
			break;

		case "del":
		case "delete":
			self csDel();
			break;

		case "save":
			n = saveSpawns();
			self iprintln("^2Custom Spawns: ^7saved " + n + " points to json");
			break;

		case "load":
			loadSpawns();
			self iprintln("^2Custom Spawns: ^7reloaded from json");
			break;

		case "clear":
			level.cs_data = [];
			rebuildSpawns();
			scheduleAutoSave();
			self iprintln("^3Custom Spawns: ^7cleared (use '!cs save' to persist)");
			break;

		case "mode":
			m = int(param);
			if (m < 0)
				m = 0;
			if (m > 2)
				m = 2;
			level.cs_mode = m;
			changeCvarQuiet("scr_customspawns_mode", m);
			self iprintln("^2Custom Spawns: ^7mode " + m + " ^7(0 stock / 1 custom / 2 both)");
			break;

		case "autosave":
			level.cs_autosave = !level.cs_autosave;
			if (level.cs_autosave)
			{
				changeCvarQuiet("scr_customspawns_autosave", 1);
				self iprintln("^2Custom Spawns: ^7autosave ON (async save + reload on edit)");
			}
			else
			{
				changeCvarQuiet("scr_customspawns_autosave", 0);
				self iprintln("^3Custom Spawns: ^7autosave OFF");
			}
			break;

		case "debug":
			if (param == "stock")
			{
				level.cs_debugStock = !level.cs_debugStock;
				refreshMarkers();
				changeCvarQuiet("scr_customspawns_debugstock", boolToInt(level.cs_debugStock));
				self iprintln("^2Custom Spawns: ^7stock markers " + onOff(level.cs_debugStock));
			}
			else
			{
				level.cs_debug = !level.cs_debug;
				refreshMarkers();
				changeCvarQuiet("scr_customspawns_debug", boolToInt(level.cs_debug));
				self iprintln("^2Custom Spawns: ^7debug " + onOff(level.cs_debug) + " ^7(markers + announcements)");
			}
			break;

		case "stats":
			self csStats();
			break;

		case "dump":
			self csDump();
			break;

		case "list":
			self csList();
			break;

		default:
			self csHelp();
			break;
	}
}

csAdd(teamParam)
{
	team = teamParam;
	if (team != "allies" && team != "axis")
	{
		team = self.pers["team"];
		if (!isDefined(team) || (team != "allies" && team != "axis"))
		{
			self iprintln("^1Custom Spawns: ^7join a team, or use '!cs add allies' / '!cs add axis'");
			return;
		}
	}

	classname = teamClass(team);
	if (!isDefined(level.cs_data[classname]))
		level.cs_data[classname] = [];

	// Require ground with standing room, or the point ends up in solid.
	feet = self.origin;
	if (bulletTracePassed(feet + (0, 0, 2), feet - (0, 0, 24), false, self))
	{
		self iprintln("^1Custom Spawns: ^7stand on solid ground to place a spawn");
		return;
	}
	if (!bulletTracePassed(feet + (0, 0, 2), feet + (0, 0, 70), false, self))
	{
		self iprintln("^1Custom Spawns: ^7not enough headroom here - use open ground");
		return;
	}

	o = self.origin;
	coords = [];
	coords[0] = o[0];
	coords[1] = o[1];
	coords[2] = o[2];

	entry = [];
	entry["o"] = coords;
	entry["y"] = self.angles[1];

	list = level.cs_data[classname];
	list[list.size] = entry;
	level.cs_data[classname] = list;

	rebuildSpawns();
	scheduleAutoSave();
	self iprintln("^2Custom Spawns: ^7added " + team + " point ^7(" + level.cs_data[classname].size + " " + team + " total)");
}

csDel()
{
	bestClass = undefined;
	bestIndex = -1;
	bestDist = 0;

	for (c = 0; c < level.cs_classes.size; c++)
	{
		classname = level.cs_classes[c];
		list = level.cs_data[classname];
		if (!isDefined(list))
			continue;

		for (i = 0; i < list.size; i++)
		{
			o = list[i]["o"];
			d = distanceSquared(self.origin, (o[0], o[1], o[2]));
			if (!isDefined(bestClass) || d < bestDist)
			{
				bestDist = d;
				bestClass = classname;
				bestIndex = i;
			}
		}
	}

	if (!isDefined(bestClass))
	{
		self iprintln("^1Custom Spawns: ^7nothing to delete");
		return;
	}

	old = level.cs_data[bestClass];
	rebuilt = [];
	for (i = 0; i < old.size; i++)
	{
		if (i == bestIndex)
			continue;
		rebuilt[rebuilt.size] = old[i];
	}
	level.cs_data[bestClass] = rebuilt;

	rebuildSpawns();
	scheduleAutoSave();
	self iprintln("^3Custom Spawns: ^7deleted nearest point");
}

csStats()
{
	self iprintln("^7Spawns used this map - ^2custom: " + level.cs_countCustom + " ^7| ^4stock: " + level.cs_countStock);
}

// Dump the spawns as a json string (json_stringify) and round-trip it back
// (json_parse) - demonstrates the string-level json functions.
csDump()
{
	s = json_stringify(level.cs_data, 1);
	if (!isDefined(s))
	{
		self iprintln("^1Custom Spawns: ^7json_stringify returned nothing");
		return;
	}
	csConsole("json_stringify dump:\n" + s);

	back = json_parse(s);
	self iprintln("^7Custom Spawns: ^7json dumped to console; json_parse round-trip = " + countData(back) + " points");
}

csList()
{
	a = 0;
	x = 0;
	if (isDefined(level.cs_data[level.cs_classAllies]))
		a = level.cs_data[level.cs_classAllies].size;
	if (isDefined(level.cs_data[level.cs_classAxis]))
		x = level.cs_data[level.cs_classAxis].size;

	self iprintln("^7Custom Spawns: ^2" + a + " allies^7, ^4" + x + " axis ^7| mode " + level.cs_mode);
}

csHelp()
{
	self iprintln("^3Custom Spawns ^7- !cs add | del | save | load | clear | mode 0/1/2 | autosave | debug [stock] | stats | dump | list");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
teamClass(team)
{
	if (team == "allies")
		return level.cs_classAllies;
	return level.cs_classAxis;
}

// Index of the custom spawn closest to org for this team, or -1 if none is
// within snap range (a player spawns exactly on the chosen point).
nearestCustomIndex(org, classname)
{
	if (!isDefined(level.cs_spawns[classname]))
		return -1;

	list = level.cs_spawns[classname];
	for (i = 0; i < list.size; i++)
	{
		if (!isDefined(list[i]))
			continue;
		if (distanceSquared(org, list[i].origin) <= 256)
			return i;
	}
	return -1;
}

boolToInt(b)
{
	if (b)
		return 1;
	return 0;
}

onOff(b)
{
	if (b)
		return "^2ON";
	return "^3OFF";
}

csConsole(msg)
{
	logPrintConsole("[Custom Spawns] " + msg + "\n");
}
