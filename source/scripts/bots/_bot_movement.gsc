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

		// ---- Idle: chase / waypoint / wander, path-followed when possible -
		if(!has_enemy)
		{
			goal = pick_idle_goal();
			step_target = resolve_path_target(goal);

			if(gettime() > self.bot_wander_until || isDefined(step_target))
			{
				if(isDefined(step_target))
				{
					face = vectortoangles(step_target - self.origin);
					self setPlayerAngles((0, face[1], 0));
				}
				else
				{
					yaw = randomint(360);
					self setPlayerAngles((0, yaw, 0));
				}
				self.bot_wander_until = gettime() + wander_repick_ms;
			}

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
		// Re-fetch — perception may have cleared bot_enemy during the wait.
		enemy = self.bot_enemy;
		if(!isDefined(enemy) || !isAlive(enemy))
		{
			self setWalkValues(0, 0);
			continue;
		}
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

// Translate the final goal into the immediate step target, using A* if a
// path can be planned. Returns:
//   - the next path-node origin if a path exists and we're not yet on it
//   - the goal itself if path is empty / unavailable (fall back to straight line)
//   - undefined if no goal at all (caller picks random yaw)
resolve_path_target(goal)
{
	if(!isDefined(goal))
		return undefined;

	advance_eps_sq = 128 * 128;
	replan_ms      = 1000;
	goal_drift_sq  = 150 * 150;

	stale = false;
	if(!isDefined(self.bot_path))
		stale = true;
	else if(!isDefined(self.bot_path_goal))
		stale = true;
	else if(distanceSquared(goal, self.bot_path_goal) > goal_drift_sq)
		stale = true;

	if(stale && (!isDefined(self.bot_path_next_ms) || gettime() >= self.bot_path_next_ms))
	{
		self.bot_path         = scripts\bots\_bot_graph::plan(self.origin, goal);
		self.bot_path_idx     = 0;
		self.bot_path_goal    = goal;
		self.bot_path_next_ms = gettime() + replan_ms;
	}

	if(!isDefined(self.bot_path) || self.bot_path.size == 0)
		return goal;

	// Advance through reached nodes
	while(self.bot_path_idx < self.bot_path.size &&
	      distanceSquared(self.origin, self.bot_path[self.bot_path_idx]) < advance_eps_sq)
		self.bot_path_idx += 1;

	if(self.bot_path_idx >= self.bot_path.size)
		return goal;

	return self.bot_path[self.bot_path_idx];
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
		self scripts\bots\_bot_log::log_event("stuck", "3", "jumping");
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
