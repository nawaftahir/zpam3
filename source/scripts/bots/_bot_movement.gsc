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

	self.bot_last_origin      = self.origin;
	self.bot_last_origin_time = gettime();

	for(;;)
	{
		wait level.fps_multiplier * 0.1;

		// Master gate — released inputs when AI is off, so the toggle works both ways
		if(!isDefined(level.bots_ai) || !level.bots_ai)
		{
			self setWalkValues(0, 0);
			continue;
		}

		if(!isAlive(self))
		{
			self setWalkValues(0, 0);
			continue;
		}

		if(!isDefined(self.bot_enemy) || !isAlive(self.bot_enemy))
		{
			self setWalkValues(0, 0);
			continue;
		}

		enemy = self.bot_enemy;
		d2 = distanceSquared(self.origin, enemy.origin);

		if(d2 < engage_range * engage_range)
		{
			self setWalkValues(0, 0);
			// reset stuck timer while stopped on purpose
			self.bot_last_origin      = self.origin;
			self.bot_last_origin_time = gettime();
			continue;
		}

		self setWalkValues(walk_speed, 0);

		// Stuck detection: while we intend to be moving, if origin hasn't
		// shifted, jump-pulse to unstick from a ledge or doorframe.
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
}

// Jump = a pulse of setBotStance("jump") then return to stand.
jump_pulse()
{
	self endon("disconnect");
	self setBotStance("jump");
	wait level.fps_multiplier * 0.1;
	self setBotStance("stand");
}
