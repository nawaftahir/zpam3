#include maps\mp\gametypes\global\_global;

// Single level-owned player pool. Every bot perception tick used to call
// getentarray + iterate all players + filter by team/alive. With 16 bots at
// 10Hz that's ~3000 player-iterations/sec just to *build* the candidate list.
//
// This rebuilds the same filtered list once per pool_rebuild_ms and stashes
// the result on level. Perception reads the cached array — O(1) build cost
// per bot per tick.

init()
{
	level.bot_pool_allies = [];
	level.bot_pool_axis   = [];
	level.bot_pool_all    = [];
	level thread run();
}

run()
{
	level endon("game_ended");
	pool_rebuild_ms = 200;

	for(;;)
	{
		wait level.fps_multiplier * (pool_rebuild_ms / 1000.0);

		allies = [];
		axis   = [];
		all    = [];

		players = getentarray("player", "classname");
		for(i = 0; i < players.size; i++)
		{
			p = players[i];
			if(!isAlive(p)) continue;
			if(!isDefined(p.pers["team"])) continue;

			all[all.size] = p;
			if(p.pers["team"] == "allies")    allies[allies.size] = p;
			else if(p.pers["team"] == "axis") axis[axis.size] = p;
		}

		level.bot_pool_allies = allies;
		level.bot_pool_axis   = axis;
		level.bot_pool_all    = all;
	}
}
