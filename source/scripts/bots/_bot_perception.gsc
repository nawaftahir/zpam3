#include maps\mp\gametypes\global\_global;

// Picks closest visible enemy each tick. Filter chain (cheap to expensive):
//   range^2  ->  FOV cone (dot product)  ->  LOS trace
//
// Per-bot knobs are copied onto self by _bot_brain at init:
//   self.bot_view_dist_sq, self.bot_fov_cos, self.bot_reaction_ms
//
// Reaction window: when going from "no enemy" to "enemy visible", commit is
// delayed by reaction_ms. While committed to a target, switching to a closer
// visible enemy is instant (no second reaction).
run()
{
	self endon("disconnect");

	// Phase offset: spread 32 bots across frames instead of stacking on one tick.
	if(isDefined(self.bot_phase))
		wait level.fps_multiplier * self.bot_phase;

	self.bot_last_seen_ms = 0;

	for(;;)
	{
		// Active = 0.1s tick. Idle (no enemy 3s+) = 0.3s tick. Cuts the cost
		// of getentarray + sightTrace by ~3x while standing around empty.
		idle_for = gettime() - self.bot_last_seen_ms;
		tick = 0.1;
		if(self.bot_last_seen_ms > 0 && idle_for > 3000)
			tick = 0.3;
		wait level.fps_multiplier * tick;

		if(!isDefined(level.bots_ai) || !level.bots_ai)
		{
			self.bot_enemy = undefined;
			self.bot_react_until = undefined;
			continue;
		}

		if(!isAlive(self))
		{
			self.bot_enemy = undefined;
			self.bot_react_until = undefined;
			continue;
		}

		my_eye = self getViewOrigin();
		my_forward = anglestoforward(self getPlayerAngles());

		// Pull the candidate list from the shared pool rebuilt by _bot_pool.
		// In team modes use just the opposing pool; in DM use all-alive.
		team_based = (isDefined(level.gametype) && level.gametype != "dm");
		if(team_based)
		{
			if(self.pers["team"] == "allies")
				players = level.bot_pool_axis;
			else
				players = level.bot_pool_allies;
		}
		else
		{
			players = level.bot_pool_all;
		}
		if(!isDefined(players))
			players = [];

		best = undefined;
		best_d2 = self.bot_view_dist_sq;

		for(i = 0; i < players.size; i++)
		{
			other = players[i];
			if(!isDefined(other) || other == self) continue;
			if(!isAlive(other)) continue;

			dx = other.origin[0] - self.origin[0];
			dy = other.origin[1] - self.origin[1];
			dz = other.origin[2] - self.origin[2];
			d2 = dx*dx + dy*dy + dz*dz;
			if(d2 > best_d2) continue;

			dir = vectornormalize(other.origin - self.origin);
			dot = dir[0]*my_forward[0] + dir[1]*my_forward[1] + dir[2]*my_forward[2];
			if(dot < self.bot_fov_cos) continue;

			other_eye = other getViewOrigin();
			if(!sightTracePassed(my_eye, other_eye, false, self)) continue;

			best = other;
			best_d2 = d2;
		}

		// Reaction gate: only fires when going from "no current enemy" to
		// "first sighting". Free target switching once already committed.
		committed = best;
		if(isDefined(best))
		{
			already_engaged = (isDefined(self.bot_enemy) && isAlive(self.bot_enemy));
			if(!already_engaged)
			{
				if(!isDefined(self.bot_react_until))
					self.bot_react_until = gettime() + self.bot_reaction_ms;

				if(gettime() < self.bot_react_until)
					committed = undefined;
				else
					self.bot_react_until = undefined;
			}
		}
		else
		{
			self.bot_react_until = undefined;
		}

		// Color logging on state changes (chat + server log)
		prev = self.bot_enemy;
		if(!isDefined(prev) && isDefined(committed))
			self scripts\bots\_bot_log::log_event("saw", "2", committed.name);
		else if(isDefined(prev) && !isDefined(committed))
			self scripts\bots\_bot_log::log_event("lost", "1", prev.name);
		else if(isDefined(prev) && isDefined(committed) && prev != committed)
			self scripts\bots\_bot_log::log_event("switch", "3", prev.name + " -> " + committed.name);

		self.bot_enemy = committed;
		if(isDefined(committed))
		{
			self.bot_last_seen_ms  = gettime();
			self.bot_last_enemy_pos = committed.origin;
		}
	}
}
