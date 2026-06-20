#include maps\mp\gametypes\global\_global;

// Proactive jump/mantle detection. Runs alongside perception/combat/movement
// and watches for short walls / low ledges in the direction of travel. When
// feet are blocked but chest height is clear, pulses setBotStance("jump")
// — CoD2 turns a jump into geometry into an automatic mantle, so we don't
// need a separate mantle action.
//
// Movement still owns the "stuck recovery" jump (no movement for 2 s + pulse
// jump). This module beats that case 90% of the time by jumping BEFORE the
// stall instead of after.
//
// Detection (per tick while moving):
//   feet_trace : origin+8  +forward*reach   - blocked = obstacle in path
//   chest_trace: origin+44 +forward*reach   - clear   = obstacle low enough to vault
//   both true  -> pulse jump
//
// Skips if:
//   - AI off
//   - bot dead
//   - bot stationary (getSpeed < min_speed) — no point vaulting if not moving
//   - cooldown not elapsed
//
// Per-tier knobs aren't applied here yet — bots all use the same detection.
// Adding lookahead distance / cooldown / reach as profile fields if we want
// to differentiate (e.g. recruits hesitate before vaulting) is a small step.

run()
{
	self endon("disconnect");

	if(isDefined(self.bot_phase))
		wait level.fps_multiplier * (self.bot_phase + 0.04);

	tick_ms          = 200;
	dt_sec           = tick_ms / 1000.0;
	cooldown_ms      = 1500;     // min gap between vaults
	reach            = 44;       // forward look-ahead distance
	feet_h           = 8;        // foot-height vertical offset for floor trace
	chest_h          = 48;       // chest-height offset; trace must be CLEAR here
	head_h           = 64;       // engine mantle ceiling; trace must be CLEAR here too
	min_speed_walk   = 30;       // below this units/sec = standing still

	self.bot_traverse_until = 0;

	for(;;)
	{
		wait level.fps_multiplier * dt_sec;

		ai_on = (isDefined(level.bots_ai) && level.bots_ai);
		if(!ai_on || !isAlive(self))
			continue;
		if(gettime() < self.bot_traverse_until)
			continue;
		if(self getSpeed() < min_speed_walk)
			continue;

		if(!needs_vault(reach, feet_h, chest_h, head_h))
			continue;

		self thread vault_pulse();
		self.bot_traverse_until = gettime() + cooldown_ms;
		self scripts\bots\_bot_log::log_event("movement", "vault", "3", "obstacle");
	}
}

needs_vault(reach, feet_h, chest_h, head_h)
{
	fwd = anglestoforward(self getPlayerAngles());
	o = self.origin;

	feet_start  = (o[0],                      o[1],                      o[2] + feet_h);
	feet_end    = (o[0] + fwd[0] * reach,     o[1] + fwd[1] * reach,     o[2] + feet_h);

	// Floor-level trace blocked = obstacle in the way.
	if(bulletTracePassed(feet_start, feet_end, false, self))
		return false;

	chest_start = (o[0],                      o[1],                      o[2] + chest_h);
	chest_end   = (o[0] + fwd[0] * reach,     o[1] + fwd[1] * reach,     o[2] + chest_h);

	// Chest-level trace must be CLEAR — confirms the obstacle is low.
	if(!bulletTracePassed(chest_start, chest_end, false, self))
		return false;

	// Head-clearance above the bot's CURRENT spot — don't try to jump
	// inside a low tunnel where the vault landing would clip ceiling.
	head_start = (o[0],                       o[1],                       o[2] + feet_h);
	head_end   = (o[0],                       o[1],                       o[2] + head_h);
	if(!bulletTracePassed(head_start, head_end, false, self))
		return false;

	return true;
}

vault_pulse()
{
	self endon("disconnect");
	self setBotStance("jump");
	wait level.fps_multiplier * 0.15;
	self setBotStance("stand");
}
