#include maps\mp\gametypes\global\_global;

// Drives view angles toward self.bot_enemy and pulses fire when aim error
// is within fire_angle_deg.
//
// Aim model: direct-track + per-shot noise.
//   1. View rotates toward the true target each tick, capped by
//      aim_turn_rate_dps. No drift; the crosshair always heads for the enemy.
//   2. When aim error is inside fire_angle_deg AND cooldown is up, a small
//      random offset (peak aim_noise_deg) is applied to the view just before
//      the fire pulse. This produces a realistic per-shot inaccuracy without
//      making the bot visibly miss the enemy with the crosshair.
//
// Per-bot knobs (copied by _bot_brain): aim_turn_rate_dps, aim_noise_deg,
// fire_cooldown_ms, fire_angle_deg.
run()
{
	self endon("disconnect");

	if(isDefined(self.bot_phase))
		wait level.fps_multiplier * self.bot_phase;

	for(;;)
	{
		has_enemy = (isDefined(self.bot_enemy) && isAlive(self.bot_enemy));
		ai_on     = (isDefined(level.bots_ai) && level.bots_ai);
		if(ai_on && isAlive(self) && has_enemy)
			tick_s = 0.05;
		else
			tick_s = 0.2;
		wait level.fps_multiplier * tick_s;

		if(!ai_on)        { self fireWeapon(0); continue; }
		if(!isAlive(self)){ self fireWeapon(0); continue; }

		enemy = self.bot_enemy;
		if(!isDefined(enemy) || !isAlive(enemy))
		{
			self fireWeapon(0);
			continue;
		}

		desired  = vectortoangles(enemy getViewOrigin() - self getViewOrigin());
		current  = self getPlayerAngles();
		next_ang = step_aim(current, desired, self.bot_aim_turn_rate_dps, tick_s);
		self setPlayerAngles(next_ang);

		yaw_err   = abs_angle(angle_delta(next_ang[1], desired[1]));
		pitch_err = abs_angle(angle_delta(next_ang[0], desired[0]));

		on_target = (yaw_err < self.bot_fire_angle_deg && pitch_err < self.bot_fire_angle_deg);
		ready     = (gettime() - self.bot_fire_time >= self.bot_fire_cooldown_ms);

		if(on_target && ready && !teammate_in_line(enemy))
		{
			if(self.bot_aim_noise_deg > 0)
			{
				n = self.bot_aim_noise_deg;
				noise_pitch = randomfloat(n) - n * 0.5;
				noise_yaw   = randomfloat(n) - n * 0.5;
				self setPlayerAngles((next_ang[0] + noise_pitch, next_ang[1] + noise_yaw, 0));
			}
			self thread fire_pulse();
			self.bot_fire_time = gettime();
			self scripts\bots\_bot_log::log_event("combat", "fired", "6", enemy.name);
		}
	}
}

// Rotate `cur` angles toward `tgt` by at most rate_dps * dt on each axis.
// Replaces the snap-lerp aim — crosshair tracks at human-feasible rate.
step_aim(cur, tgt, rate_dps, dt)
{
	max_step = rate_dps * dt;

	dp = angle_delta(cur[0], tgt[0]);
	dy = angle_delta(cur[1], tgt[1]);

	if(dp >  max_step) dp =  max_step;
	if(dp < 0 - max_step) dp = 0 - max_step;
	if(dy >  max_step) dy =  max_step;
	if(dy < 0 - max_step) dy = 0 - max_step;

	return (cur[0] + dp, cur[1] + dy, 0);
}

// Returns true if a live teammate is between self and enemy within ~500 units
// of self. Uses getClosestPlayerInRange filtered to own team, then a simple
// "is this body closer to enemy than my own origin" check. Cheap engine-side
// scan + one dot product.
teammate_in_line(enemy)
{
	if(!isDefined(self.pers["team"]))
		return false;
	if(self.pers["team"] != "allies" && self.pers["team"] != "axis")
		return false;

	if(self.pers["team"] == "allies")
		my_team = 2;
	else
		my_team = 1;

	check_radius_sq = 500.0 * 500.0;
	mate = getClosestPlayerInRange(self.origin, check_radius_sq, my_team);
	if(!isDefined(mate) || mate == self)
		return false;

	// Vector from self toward enemy
	to_enemy = enemy.origin - self.origin;
	to_mate  = mate.origin  - self.origin;

	enemy_d2 = to_enemy[0]*to_enemy[0] + to_enemy[1]*to_enemy[1] + to_enemy[2]*to_enemy[2];
	mate_d2  = to_mate[0]*to_mate[0]   + to_mate[1]*to_mate[1]   + to_mate[2]*to_mate[2];

	// Teammate is in the same direction as enemy AND closer than enemy.
	dot = to_enemy[0]*to_mate[0] + to_enemy[1]*to_mate[1] + to_enemy[2]*to_mate[2];
	if(dot <= 0)
		return false;   // teammate is behind me
	if(mate_d2 >= enemy_d2)
		return false;   // teammate is past the enemy

	self scripts\bots\_bot_log::log_event("ff", "ff-hold", "3", mate.name);
	return true;
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
