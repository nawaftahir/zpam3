#include maps\mp\gametypes\global\_global;

// Auto-seeded waypoint ring buffer. One level thread samples every alive
// player's origin every sample_ms; if no existing waypoint is within
// min_spacing of that origin, the new origin is appended. Cap at max_wp:
// when full, overwrite oldest. No persistence — rebuilds each map.
//
// Purpose: idle bots pull a random waypoint as a wander goal instead of a
// pure-random yaw, so they bias toward places players actually walk through.
// Foundation for the real graph + A* iteration later.

init()
{
	level.bot_waypoints    = [];
	level.bot_wp_neighbors = [];  // parallel: index -> array of neighbor indices
	level.bot_wp_head      = 0;
	level.bot_wp_max       = 64;
	level.bot_wp_link_dist_sq = 600 * 600;
	level.bot_wp_link_max  = 6;
	level thread run();
}

run()
{
	level endon("game_ended");

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
