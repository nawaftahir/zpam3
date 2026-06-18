#include maps\mp\gametypes\global\_global;

// Reads self.bot_enemy (set by perception). Lerps view angles toward the
// target's eye and pulses the fire button when aim is within fire_angle_deg
// and the cooldown has elapsed. fireWeapon(1/0) is a button-hold toggle —
// semi-auto/bolt fire on the 0->1 edge so each shot must be pulsed.
// v0: no skill ladder, no aim noise.
// Per-bot knobs (copied onto self by _bot_brain at init):
//   self.bot_aim_blend, self.bot_aim_noise_deg,
//   self.bot_fire_cooldown_ms, self.bot_fire_angle_deg
run()
{
	self endon("disconnect");

	if(isDefined(self.bot_phase))
		wait level.fps_multiplier * self.bot_phase;

	for(;;)
	{
		// 20Hz when shooting, 5Hz when idle/dead/disabled. Aim math +
		// getPlayerAngles is the hottest per-tick cost — only pay it when
		// there's actually a target.
		has_enemy = (isDefined(self.bot_enemy) && isAlive(self.bot_enemy));
		ai_on    = (isDefined(level.bots_ai) && level.bots_ai);
		if(ai_on && isAlive(self) && has_enemy)
			wait level.fps_multiplier * 0.05;
		else
			wait level.fps_multiplier * 0.2;

		if(!ai_on)
		{
			self fireWeapon(0);
			continue;
		}

		if(!isAlive(self))
		{
			self fireWeapon(0);
			continue;
		}

		// Re-check after the wait — perception may have cleared bot_enemy
		// while we were asleep, so has_enemy from before the wait is stale.
		enemy = self.bot_enemy;
		if(!isDefined(enemy) || !isAlive(enemy))
		{
			self fireWeapon(0);
			continue;
		}

		desired = vectortoangles(enemy getViewOrigin() - self getViewOrigin());

		// Aim noise: random jitter +/- noise_deg/2 on pitch and yaw.
		// Recruit ~4.5 deg of slop, Elite ~0.4 deg.
		if(self.bot_aim_noise_deg > 0)
		{
			n = self.bot_aim_noise_deg;
			noise_pitch = randomfloat(n) - n * 0.5;
			noise_yaw   = randomfloat(n) - n * 0.5;
			desired = (desired[0] + noise_pitch, desired[1] + noise_yaw, 0);
		}

		current = self getPlayerAngles();
		self setPlayerAngles(lerp_angles(current, desired, self.bot_aim_blend));

		yaw_err   = abs_angle(angle_delta(current[1], desired[1]));
		pitch_err = abs_angle(angle_delta(current[0], desired[0]));

		on_target = (yaw_err < self.bot_fire_angle_deg && pitch_err < self.bot_fire_angle_deg);
		ready     = (gettime() - self.bot_fire_time >= self.bot_fire_cooldown_ms);

		if(on_target && ready)
		{
			self thread fire_pulse();
			self.bot_fire_time = gettime();
			self scripts\bots\_bot_log::log_event("fired", "6", enemy.name);
		}
	}
}

// One trigger pulse — press, brief hold, release. Works for both
// semi-auto (fires on the press) and short-burst with auto weapons.
fire_pulse()
{
	self endon("disconnect");
	self fireWeapon(1);
	wait level.fps_multiplier * 0.05;
	self fireWeapon(0);
}

// Shortest-arc angle delta in degrees, result in (-180, 180].
angle_delta(from_deg, to_deg)
{
	d = to_deg - from_deg;
	if(d > 180)  d -= 360;
	if(d < -180) d += 360;
	return d;
}

abs_angle(a)
{
	if(a < 0) return 0 - a;
	return a;
}

// Per-component lerp for pitch + yaw using shortest-arc delta.
lerp_angles(a, b, t)
{
	dp = angle_delta(a[0], b[0]);
	dy = angle_delta(a[1], b[1]);
	return (a[0] + dp * t, a[1] + dy * t, 0);
}
