#include maps\mp\gametypes\global\_global;

// Per-bot brain entry. Threaded from maps\mp\gametypes\_bots::bot_think()
// once per bot when scr_bots_ai is on. Owns the per-bot skill profile and
// the three worker threads (perception / combat / movement). Each worker
// gates on isAlive() so respawns are handled without per-life restart.
run()
{
	self endon("disconnect");

	// Assign skill profile (cvar 1..4 picks a tier; 0 randomizes per bot)
	skill = 2;
	if(isDefined(level.bots_skill))
		skill = level.bots_skill;

	prof = scripts\bots\_bot_skill::get_profile(skill);

	// Copy profile knobs onto self so hot loops do single-level access
	self.bot_view_dist_sq    = prof.view_dist_sq;
	self.bot_fov_cos         = prof.fov_cos;
	self.bot_reaction_ms     = prof.reaction_ms;
	self.bot_aim_blend       = prof.aim_blend;
	self.bot_aim_noise_deg   = prof.aim_noise_deg;
	self.bot_aim_turn_rate_dps = prof.aim_turn_rate_dps;
	self.bot_fire_cooldown_ms = prof.fire_cooldown_ms;
	self.bot_fire_angle_deg  = prof.fire_angle_deg;

	self.bot_peek_chance_per_sec = prof.peek_chance_per_sec;
	self.bot_peek_lean_enabled   = prof.peek_lean_enabled;
	self.bot_peek_jump_enabled   = prof.peek_jump_enabled;
	self.bot_peek_prone_range_sq = prof.peek_prone_range_sq;
	self.bot_peek_duration_ms    = prof.peek_duration_ms;
	self.bot_peek_cooldown_ms    = prof.peek_cooldown_ms;

	self.bot_enemy        = undefined;
	self.bot_react_until  = undefined;
	self.bot_fire_time    = 0;

	// Wait for first alive spawn in a real team
	while(!isAlive(self) || !isDefined(self.pers["team"]))
		wait level.fps_multiplier * 0.2;

	if(self.pers["team"] != "allies" && self.pers["team"] != "axis")
		return;

	// Resolve the actual tier this bot got (after randomization)
	resolved = skill;
	if(resolved < 1 || resolved > 4)
	{
		// Find which preset matches what get_profile picked
		// (cheap reverse lookup — only runs once per bot)
		for(t = 1; t <= 4; t++)
		{
			if(level.bot_profiles[t].view_dist_sq == prof.view_dist_sq)
			{
				resolved = t;
				break;
			}
		}
	}

	self.bot_skill_tier = resolved;
	self.bot_skill_name = scripts\bots\_bot_skill::tier_name(resolved);

	// Stagger worker ticks so 32 bots don't share frames — phase 0..0.08s
	// keyed off entity number per CLAUDE.md AI/Bot perf rule.
	self.bot_phase = (self getEntityNumber() % 5) * 0.02;

	self scripts\bots\_bot_log::log_event("spawn", "spawned", "5", self.bot_skill_name);

	self thread scripts\bots\_bot_perception::run();
	self thread scripts\bots\_bot_combat::run();
	self thread scripts\bots\_bot_movement::run();
	self thread scripts\bots\_bot_peek::run();
	self thread scripts\bots\_bot_traverse::run();
	self thread respawn_input_reset();
}

// Wipe persistent bot input state on every respawn so a stance/lean/fire
// held at the moment of death does not bleed into the next life.
respawn_input_reset()
{
	self endon("disconnect");

	for(;;)
	{
		self waittill("spawned_player");
		self clearBotInputs();
	}
}
