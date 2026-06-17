#include maps\mp\gametypes\global\_global;

// Per-bot brain entry. Threaded from maps\mp\gametypes\_bots::bot_think()
// once per bot when scr_bots_ai is on. Spawns the perception and combat
// sub-threads; each runs its own loop and self-gates on isAlive() so
// respawns are handled without a per-life restart.
run()
{
	self endon("disconnect");

	self.bot_enemy = undefined;
	self.bot_fire_time = 0;

	// Wait until first alive spawn in a real team
	while(!isAlive(self) || !isDefined(self.pers["team"]))
		wait level.fps_multiplier * 0.2;

	if(self.pers["team"] != "allies" && self.pers["team"] != "axis")
		return;

	self thread scripts\bots\_bot_perception::run();
	self thread scripts\bots\_bot_combat::run();
	self thread scripts\bots\_bot_movement::run();
}
