#include maps\mp\gametypes\global\_global;

// Auto-seeded waypoint ring buffer. One level thread samples every alive
// player's origin every sample_ms; if no existing waypoint is within
// min_spacing of that origin, the new origin is appended. Cap at max_wp:
// when full, overwrite oldest. Graph persists across maps via JSON.
//
// Purpose: idle bots pull a random waypoint as a wander goal instead of a
// pure-random yaw, so they bias toward places players actually walk through.
// Foundation for the real graph + A* iteration later.
//
// Persistence: bot_waypoints/<mapname>.json. Loaded on init (sync), saved
// at intermission (async). Toggled by scr_bots_waypoints_save / _load.

init()
{
	level.bot_waypoints    = [];
	level.bot_wp_neighbors = [];  // parallel: index -> array of neighbor indices
	level.bot_wp_head      = 0;
	level.bot_wp_max       = 64;
	level.bot_wp_link_dist_sq = 600 * 600;
	level.bot_wp_link_max  = 6;

	if (getCvarInt("scr_bots_waypoints_load"))
		try_load();

	level thread save_watcher();
	level thread run();
}

run()
{
	level endon("intermission");

	sample_ms       = 1000;
	min_spacing     = 200;
	min_spacing_sq  = min_spacing * min_spacing;

	for(;;)
	{
		wait level.fps_multiplier * (sample_ms / 1000.0);

		if(!isDefined(level.bot_pool_all))
			continue;

		players = level.bot_pool_all;
		for(i = 0; i < players.size; i++)
		{
			p = players[i];
			if(!isAlive(p)) continue;
			add_if_far(p.origin, min_spacing_sq);
		}
	}
}

add_if_far(origin, min_spacing_sq)
{
	for(i = 0; i < level.bot_waypoints.size; i++)
	{
		if(!isDefined(level.bot_waypoints[i])) continue;
		if(distanceSquared(origin, level.bot_waypoints[i]) < min_spacing_sq)
			return;
	}

	if(level.bot_waypoints.size < level.bot_wp_max)
	{
		new_idx = level.bot_waypoints.size;
		level.bot_waypoints[new_idx] = origin;
		build_links(new_idx);
	}
	else
	{
		new_idx = level.bot_wp_head;
		clear_links(new_idx);                 // detach old neighbors of evicted slot
		level.bot_waypoints[new_idx] = origin;
		build_links(new_idx);
		level.bot_wp_head = (level.bot_wp_head + 1) % level.bot_wp_max;
	}

	schedule_save();
}

// Trace from waypoint pos (raised 32u so we sample at chest height, not floor).
los_clear(a, b)
{
	az = (a[0], a[1], a[2] + 32);
	bz = (b[0], b[1], b[2] + 32);
	return sightTracePassed(az, bz, false, undefined);
}

build_links(idx)
{
	level.bot_wp_neighbors[idx] = [];
	for(j = 0; j < level.bot_waypoints.size; j++)
	{
		if(j == idx) continue;
		if(!isDefined(level.bot_waypoints[j])) continue;
		if(level.bot_wp_neighbors[idx].size >= level.bot_wp_link_max) break;

		d2 = distanceSquared(level.bot_waypoints[idx], level.bot_waypoints[j]);
		if(d2 > level.bot_wp_link_dist_sq) continue;
		if(!los_clear(level.bot_waypoints[idx], level.bot_waypoints[j])) continue;

		level.bot_wp_neighbors[idx][level.bot_wp_neighbors[idx].size] = j;

		// Reverse link
		if(!isDefined(level.bot_wp_neighbors[j]))
			level.bot_wp_neighbors[j] = [];
		if(level.bot_wp_neighbors[j].size < level.bot_wp_link_max)
			level.bot_wp_neighbors[j][level.bot_wp_neighbors[j].size] = idx;
	}
}

// Remove all references to idx from every neighbor list, then null its own.
clear_links(idx)
{
	if(isDefined(level.bot_wp_neighbors[idx]))
	{
		nbrs = level.bot_wp_neighbors[idx];
		for(i = 0; i < nbrs.size; i++)
		{
			nb = nbrs[i];
			if(!isDefined(level.bot_wp_neighbors[nb])) continue;
			level.bot_wp_neighbors[nb] = remove_value(level.bot_wp_neighbors[nb], idx);
		}
	}
	level.bot_wp_neighbors[idx] = [];
}

remove_value(arr, val)
{
	out = [];
	for(i = 0; i < arr.size; i++)
		if(arr[i] != val)
			out[out.size] = arr[i];
	return out;
}

pick_random()
{
	if(!isDefined(level.bot_waypoints) || level.bot_waypoints.size == 0)
		return undefined;
	idx = randomint(level.bot_waypoints.size);
	return level.bot_waypoints[idx];
}

// ---------------------------------------------------------------------------
// JSON persistence
// ---------------------------------------------------------------------------

wp_path()
{
	return "bot_waypoints/" + getCvar("mapname") + ".json";
}

// Sync load at init. json_load returns undefined if the file is missing or
// malformed, so falling through leaves the graph empty and the sampler fills
// it from live play, same as the old behavior.
try_load()
{
	data = json_load(wp_path());
	if (!isDefined(data))
		return;

	if (!isDefined(data["version"]) || data["version"] != 1)
		return;
	if (!isDefined(data["waypoints"]) || !isDefined(data["neighbors"]))
		return;

	wps = data["waypoints"];
	nbs = data["neighbors"];

	// JSON arrays come back as integer-indexed GSC arrays; vectors come back
	// as 3-element float arrays, recompose.
	loaded = 0;
	for (i = 0; i < wps.size; i++)
	{
		v = wps[i];
		if (!isDefined(v) || !isDefined(v[0]) || !isDefined(v[1]) || !isDefined(v[2]))
			continue;
		level.bot_waypoints[loaded] = (v[0], v[1], v[2]);

		nb = [];
		if (isDefined(nbs[i]))
		{
			src = nbs[i];
			for (j = 0; j < src.size; j++)
				if (isDefined(src[j]))
					nb[nb.size] = src[j];
		}
		level.bot_wp_neighbors[loaded] = nb;
		loaded += 1;
	}

	if (isDefined(data["head"]))
		level.bot_wp_head = data["head"];

	if (loaded > 0)
		iprintln("^5[bot] ^7waypoints: loaded " + loaded + " from " + wp_path());
}

// Debounced autosave. Every new waypoint append calls schedule_save(); a
// single timer thread batches the rapid stream of adds during early sampling
// into one async write per save_debounce_ms. The intermission save below is
// a final flush in case the map ends naturally, but the durability guarantee
// comes from the per-add saves: map_rotate / hard-restart cannot lose data
// older than save_debounce_ms.
schedule_save()
{
	if (!isDefined(level.bot_wp_save_enabled))
		level.bot_wp_save_enabled = getCvarInt("scr_bots_waypoints_save");
	if (!level.bot_wp_save_enabled)
		return;

	if (isDefined(level.bot_wp_save_pending) && level.bot_wp_save_pending)
		return;
	level.bot_wp_save_pending = true;
	level thread save_debounce();
}

save_debounce()
{
	level endon("intermission");
	wait level.fps_multiplier * 2.0;     // batch ~2s of rapid sampler appends
	level.bot_wp_save_pending = false;
	submit_save();
}

// Async save fired by debounce + final flush at intermission.
save_watcher()
{
	level waittill("intermission");
	submit_save();
}

submit_save()
{
	if (!getCvarInt("scr_bots_waypoints_save"))
		return;
	if (!isDefined(level.bot_waypoints) || level.bot_waypoints.size == 0)
		return;

	out = spawnstruct();
	out.version    = 1;
	out.map        = getCvar("mapname");
	out.head       = level.bot_wp_head;
	out.waypoints  = level.bot_waypoints;
	out.neighbors  = level.bot_wp_neighbors;

	jobId = json_save_async(wp_path(), out, 1);
	if (jobId == 0)
	{
		iprintln("^1[bot] ^7waypoints: async save submit failed for " + wp_path());
		return;
	}

	// Only chatter on the final intermission save; the debounced per-tick
	// saves stay silent to keep the chat readable during play.
	if (game["state"] == "intermission")
		iprintln("^5[bot] ^7waypoints: saving " + level.bot_waypoints.size + " to " + wp_path());
}
