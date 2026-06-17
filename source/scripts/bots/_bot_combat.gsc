#include maps\mp\gametypes\global\_global;

// Reads self.bot_enemy (set by perception). Lerps view angles toward the
// target's eye and pulses the fire button when aim is within fire_angle_deg
// and the cooldown has elapsed. fireWeapon(1/0) is a button-hold toggle —
// semi-auto/bolt fire on the 0->1 edge so each shot must be pulsed.
// v0: no skill ladder, no aim noise.
run()
{
	self endon("disconnect");

	fire_cooldown_ms = 250;     // ms between trigger pulses (gettime() units)
	aim_blend        = 0.35;
	fire_angle_deg   = 6;

	for(;;)
	{
		wait level.fps_multiplier * 0.05;

		// Master gate — toggle scr_bots_ai 0 actually stops firing now
		if(!isDefined(level.bots_ai) || !level.bots_ai)
		{
			self fireWeapon(0);
			continue;
		}

		if(!isAlive(self))
		{
			self fireWeapon(0);
			continue;
		}

		if(!isDefined(self.bot_enemy) || !isAlive(self.bot_enemy))
		{
			self fireWeapon(0);
			continue;
		}

		enemy = self.bot_enemy;
		desired = vectortoangles(enemy getViewOrigin() - self getViewOrigin());
		current = self getPlayerAngles();

		self setPlayerAngles(lerp_angles(current, desired, aim_blend));

		yaw_err   = abs_angle(angle_delta(current[1], desired[1]));
		pitch_err = abs_angle(angle_delta(current[0], desired[0]));

		on_target = (yaw_err < fire_angle_deg && pitch_err < fire_angle_deg);
		ready     = (gettime() - self.bot_fire_time >= fire_cooldown_ms);

		if(on_target && ready)
		{
			self thread fire_pulse();
			self.bot_fire_time = gettime();
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
