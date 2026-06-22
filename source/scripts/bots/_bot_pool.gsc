#include maps\mp\gametypes\global\_global;

// Level-cached player pool, rebuilt at 5Hz. Filtering happens engine-side
// via the getPlayersInRange native (team enum: 1=axis, 2=allies, -1=any).

init()
{
	level.bot_pool_allies = [];
	level.bot_pool_axis   = [];
	level.bot_pool_all    = [];
	level thread run();
}

run()
{
	level endon("intermission");

	pool_rebuild_ms = 200;
	big_d2          = 100000.0 * 100000.0;
	world_origin    = (0, 0, 0);

	for(;;)
	{
		wait level.fps_multiplier * (pool_rebuild_ms / 1000.0);

		level.bot_pool_axis   = getPlayersInRange(world_origin, big_d2, 1);
		level.bot_pool_allies = getPlayersInRange(world_origin, big_d2, 2);
		level.bot_pool_all    = getPlayersInRange(world_origin, big_d2, -1);

		log_pool_summary();
	}
}

log_pool_summary()
{
	if(!isDefined(level.debug_bot_flags) || !isDefined(level.debug_bot_flags["pool"]) || !level.debug_bot_flags["pool"])
		return;
	if(isDefined(level.bot_pool_log_next) && gettime() < level.bot_pool_log_next)
		return;

	level.bot_pool_log_next = gettime() + 5000;
	iprintln("^8[bot] ^7pool: axis=" + level.bot_pool_axis.size + " allies=" + level.bot_pool_allies.size + " all=" + level.bot_pool_all.size);
}
