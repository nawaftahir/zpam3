#include maps\mp\gametypes\global\_global;

// Concise debug logger. One line per event, rate-limited per (bot, verb)
// so the chat stays readable even with 16 bots in a firefight.
//
// Per-category gating:
//   debug_bot_perception  saw / lost / switch
//   debug_bot_combat      fired
//   debug_bot_movement    stuck / pathing
//   debug_bot_peek        jump / lean / prone peeks
//   debug_bot_spawn       bot lifecycle (spawn/respawn)
//   debug_bot_waypoints   load / save events
//   debug_bots            master — when 1, everything prints regardless
//
// Format: ^8[bot] ^7<name> ^5T<tier> ^<col><verb> ^7<object>
//
// Caller-chosen color codes:
//   "1" red    — lost / negative
//   "2" green  — saw / positive
//   "3" yellow — switch / stuck / warning
//   "5" cyan   — spawn / lifecycle
//   "6" magenta— fire

log_event(category, verb, color, obj)
{
	master = (isDefined(level.debug_bots) && level.debug_bots);
	cat_on = false;
	if (isDefined(category) && isDefined(level.debug_bot_flags))
		cat_on = (isDefined(level.debug_bot_flags[category]) && level.debug_bot_flags[category]);

	if (!master && !cat_on)
		return;

	if(!isDefined(self.bot_log_next))
		self.bot_log_next = [];

	now = gettime();
	if(isDefined(self.bot_log_next[verb]) && now < self.bot_log_next[verb])
		return;
	self.bot_log_next[verb] = now + 1000;

	tier = "T?";
	if(isDefined(self.bot_skill_tier))
		tier = "T" + self.bot_skill_tier;

	line = "^8[bot] ^7" + self.name + " ^5" + tier + " ^" + color + verb;
	if(isDefined(obj))
		line += " ^7" + obj;

	iprintln(line);
}
