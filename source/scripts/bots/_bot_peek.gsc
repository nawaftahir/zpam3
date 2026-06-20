#include maps\mp\gametypes\global\_global;

// Combat peeks: jump-shot / lean / prone, gated by skill tier. Runs in
// parallel with combat+movement and only acts while the bot has a target.
//
// Per-tick the bot rolls peek_chance_per_sec against the elapsed dt. On a
// hit it picks one of the enabled actions (lean L/R follows current strafe
// direction so the body angles into the engagement), holds it for
// peek_duration_ms, then reverts. peek_cooldown_ms enforces a minimum gap
// between peeks so high-tier bots don't strobe.
//
// Movement still owns walk + crouch via setWalkValues / "stuck" jumps;
// peek owns lean + occasional jump-shot + prone-drop only while engaging.
run()
{
	self endon("disconnect");

	if(isDefined(self.bot_phase))
		wait level.fps_multiplier * (self.bot_phase + 0.03);

	tick_ms      = 250;
	dt_sec       = tick_ms / 1000.0;

	self.bot_peek_until    = 0;
	self.bot_peek_cooldown = 0;
	self.bot_peek_action   = "";   // "lean_l" | "lean_r" | "jump" | "prone" | ""

	for(;;)
	{
		wait level.fps_multiplier * dt_sec;

		ai_on    = (isDefined(level.bots_ai) && level.bots_ai);
		has_enemy = (isDefined(self.bot_enemy) && isAlive(self.bot_enemy));

		if(!ai_on || !isAlive(self))
		{
			clear_peek();
			continue;
		}

		now = gettime();

		// Active peek window — keep the action held until it expires
		if(self.bot_peek_action != "" && now < self.bot_peek_until)
			continue;

		// Just expired — revert to neutral
		if(self.bot_peek_action != "")
		{
			clear_peek();
			self.bot_peek_cooldown = now + self.bot_peek_cooldown_ms;
		}

		if(!has_enemy)
			continue;
		if(now < self.bot_peek_cooldown)
			continue;
		if(self.bot_peek_chance_per_sec <= 0)
			continue;

		// Bernoulli per tick: P(peek this tick) = chance_per_sec * dt
		if(randomfloat(1.0) > self.bot_peek_chance_per_sec * dt_sec)
			continue;

		action = choose_action();
		if(action == "")
			continue;

		apply_peek(action);
		self.bot_peek_action = action;
		self.bot_peek_until  = now + self.bot_peek_duration_ms;
	}
}

// Roll a peek action from the bot's enabled set. Lean follows strafe_dir
// so the body opens toward the side it's moving — feels less random.
choose_action()
{
	bag = [];

	if(self.bot_peek_lean_enabled)
	{
		dir = 0;
		if(isDefined(self.bot_strafe_dir))
			dir = self.bot_strafe_dir;
		if(dir < 0)
			bag[bag.size] = "lean_l";
		else if(dir > 0)
			bag[bag.size] = "lean_r";
		else
		{
			// Idle strafe — pick a side at random so we still peek sometimes
			if(randomint(2) == 0)
				bag[bag.size] = "lean_l";
			else
				bag[bag.size] = "lean_r";
		}
	}

	if(self.bot_peek_jump_enabled)
		bag[bag.size] = "jump";

	if(self.bot_peek_prone_range_sq > 0 && isDefined(self.bot_enemy))
	{
		d2 = distanceSquared(self.origin, self.bot_enemy.origin);
		if(d2 > self.bot_peek_prone_range_sq)
			bag[bag.size] = "prone";
	}

	if(bag.size == 0)
		return "";
	return bag[randomint(bag.size)];
}

apply_peek(action)
{
	if(action == "lean_l")
		self setLean("left");
	else if(action == "lean_r")
		self setLean("right");
	else if(action == "jump")
		self setBotStance("jump");
	else if(action == "prone")
		self setBotStance("prone");

	self scripts\bots\_bot_log::log_event("peek", "peek", "3", action);
}

clear_peek()
{
	if(self.bot_peek_action == "lean_l" || self.bot_peek_action == "lean_r")
		self setLean("none");
	else if(self.bot_peek_action == "jump" || self.bot_peek_action == "prone")
		self setBotStance("stand");
	self.bot_peek_action = "";
}
