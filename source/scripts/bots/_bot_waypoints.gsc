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
	level.bot_waypoints = [];
	level.bot_wp_head   = 0;
	level.bot_wp_max    = 64;
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
	// Reject if any existing waypoint is closer than min_spacing
	for(i = 0; i < level.bot_waypoints.size; i++)
	{
		if(!isDefined(level.bot_waypoints[i])) continue;
		if(distanceSquared(origin, level.bot_waypoints[i]) < min_spacing_sq)
			return;
	}

	if(level.bot_waypoints.size < level.bot_wp_max)
	{
		level.bot_waypoints[level.bot_waypoints.size] = origin;
	}
	else
	{
		// Ring buffer overwrite at head
		level.bot_waypoints[level.bot_wp_head] = origin;
		level.bot_wp_head = (level.bot_wp_head + 1) % level.bot_wp_max;
	}
}

pick_random()
{
	if(!isDefined(level.bot_waypoints) || level.bot_waypoints.size == 0)
		return undefined;
	idx = randomint(level.bot_waypoints.size);
	return level.bot_waypoints[idx];
}
