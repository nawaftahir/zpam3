#include maps\mp\gametypes\global\_global;

// Per-bot movement. Drives setWalkValues based on self.bot_enemy:
//   no enemy            -> idle, no input
//   too far from enemy  -> walk forward (combat thread is already aiming the
//                          view at the enemy, so "forward" = toward enemy)
//   close enough        -> stop walking, let combat handle the kill
//
// Stuck recovery: if the bot has not moved more than stuck_eps units in
// stuck_check_ms while it is supposed to be walking, pulse a jump.
//
// v0: naive line-of-sight pursuit. Pathfinding lands in a later iteration.
run()
{
	self endon("disconnect");

	walk_speed       = 127;     // setWalkValues max forward magnitude
	engage_range     = 350;     // stop within this 3D distance
	stuck_check_ms   = 2000;    // ms with no real displacement = "stuck"
	stuck_eps_sq     = 256;     // 16^2 — less than this = stuck
	wander_trace_len = 200;     // forward clearance check distance
	wander_repick_ms = 2500;    // ms between random heading picks while idle
	strafe_flip_ms   = 700;     // ms between strafe direction flips under fire

	self.bot_last_origin       = self.origin;
	self.bot_last_origin_time  = gettime();
	self.bot_wander_until      = 0;
	self.bot_strafe_until      = 0;
	self.bot_strafe_dir        = 0;

	if(isDefined(self.bot_phase))
		wait level.fps_multiplier * self.bot_phase;

	for(;;)
	{
		has_enemy = (isDefined(self.bot_enemy) && isAlive(self.bot_enemy));
		ai_on    = (isDefined(level.bots_ai) && level.bots_ai);
		if(ai_on && isAlive(self) && has_enemy)
			wait level.fps_multiplier * 0.1;
		else
			wait level.fps_multiplier * 0.25;

		if(!ai_on)
		{
			self setWalkValues(0, 0);
			continue;
		}

		if(!isAlive(self))
		{
			self setWalkValues(0, 0);
			continue;
		}

		// ---- Idle: chase last-known -> waypoint -> wander -----------------
		if(!has_enemy)
		{
			goal = pick_idle_goal();

			if(gettime() > self.bot_wander_until || isDefined(goal))
			{
				if(isDefined(goal))
				{
					face = vectortoangles(goal - self.origin);
					self setPlayerAngles((0, face[1], 0));
				}
				else
				{
					yaw = randomint(360);
					self setPlayerAngles((0, yaw, 0));
				}
				self.bot_wander_until = gettime() + wander_repick_ms;
			}

			// Trace forward — if blocked, repick next tick
			fwd = anglestoforward(self getPlayerAngles());
			ahead = (self.origin[0] + fwd[0] * wander_trace_len,
			         self.origin[1] + fwd[1] * wander_trace_len,
			         self.origin[2] + fwd[2] * wander_trace_len + 32);
			eye = (self.origin[0], self.origin[1], self.origin[2] + 32);

			if(!bulletTracePassed(eye, ahead, false, self))
			{
				self setWalkValues(0, 0);
				self.bot_wander_until = 0;
				continue;
			}

			self setWalkValues(walk_speed, 0);
			update_stuck();
			continue;
		}

		// ---- Engaging: strafe + close to engage range ----------------------
		enemy = self.bot_enemy;
		d2 = distanceSquared(self.origin, enemy.origin);
		close_enough = (d2 < engage_range * engage_range);

		if(gettime() > self.bot_strafe_until)
		{
			// -1 left, 0 none, +1 right — flip every flip_ms with a 1/4 chance of "hold"
			pick = randomint(4);
			if(pick == 0)      self.bot_strafe_dir = 0;
			else if(pick == 1) self.bot_strafe_dir = -1;
			else               self.bot_strafe_dir = 1;
			self.bot_strafe_until = gettime() + strafe_flip_ms;
		}

		forward_cmd = walk_speed;
		if(close_enough)
			forward_cmd = 0;

		right_cmd = self.bot_strafe_dir * 96; // ~75% strafe speed
		self setWalkValues(forward_cmd, right_cmd);

		if(close_enough)
		{
			self.bot_last_origin      = self.origin;
			self.bot_last_origin_time = gettime();
		}
		else
		{
			update_stuck();
		}
	}
}

// Decide where to walk while idle.
//   1. recent lost enemy (< 6s)        -> last-known origin (chase)
//   2. else 50% chance + waypoint pool -> random waypoint
//   3. else                            -> undefined (pick random yaw)
pick_idle_goal()
{
	chase_window_ms = 6000;
	goal_reach_sq   = 64 * 64;

	if(isDefined(self.bot_last_enemy_pos) && isDefined(self.bot_last_seen_ms))
	{
		if(gettime() - self.bot_last_seen_ms < chase_window_ms)
		{
			if(distanceSquared(self.origin, self.bot_last_enemy_pos) > goal_reach_sq)
				return self.bot_last_enemy_pos;
			self.bot_last_enemy_pos = undefined;
		}
	}

	if(randomint(100) < 50)
	{
		wp = scripts\bots\_bot_waypoints::pick_random();
		if(isDefined(wp))
		{
			if(distanceSquared(self.origin, wp) > goal_reach_sq)
				return wp;
		}
	}

	return undefined;
}

update_stuck()
{
	stuck_eps_sq   = 256;
	stuck_check_ms = 2000;

	if(distanceSquared(self.origin, self.bot_last_origin) > stuck_eps_sq)
	{
		self.bot_last_origin      = self.origin;
		self.bot_last_origin_time = gettime();
	}
	else if(gettime() - self.bot_last_origin_time > stuck_check_ms)
	{
		self thread jump_pulse();
		self.bot_last_origin_time = gettime();
	}
}

// Jump = a pulse of setBotStance("jump") then return to stand.
jump_pulse()
{
	self endon("disconnect");
	self setBotStance("jump");
	wait level.fps_multiplier * 0.1;
	self setBotStance("stand");
}
