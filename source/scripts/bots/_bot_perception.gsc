#include maps\mp\gametypes\global\_global;

// Picks closest visible enemy each tick and stores it in self.bot_enemy
// (undefined if nothing visible). Filter chain (cheap to expensive):
//   range^2  ->  FOV cone (dot product)  ->  LOS trace
// 10 Hz tick keeps the trace budget bounded at scale.
run()
{
	self endon("disconnect");

	view_dist = 2000;
	view_dist_sq = view_dist * view_dist;
	fov_cos = 0.34;  // approx cos(70deg), +/-70 deg cone

	for(;;)
	{
		wait level.fps_multiplier * 0.1;

		// Master gate — clearing target when AI is off makes combat/movement idle
		if(!isDefined(level.bots_ai) || !level.bots_ai)
		{
			self.bot_enemy = undefined;
			continue;
		}

		if(!isAlive(self))
		{
			self.bot_enemy = undefined;
		}
		else
		{
			my_eye = self getViewOrigin();
			my_forward = anglestoforward(self getPlayerAngles());

			players = getentarray("player", "classname");
			best = undefined;
			best_d2 = view_dist_sq;

			team_based = (isDefined(level.gametype) && level.gametype != "dm");

			for(i = 0; i < players.size; i++)
			{
				other = players[i];
				if(!isDefined(other) || other == self) continue;
				if(!isAlive(other)) continue;
				if(!isDefined(other.pers["team"])) continue;
				if(team_based && other.pers["team"] == self.pers["team"]) continue;

				dx = other.origin[0] - self.origin[0];
				dy = other.origin[1] - self.origin[1];
				dz = other.origin[2] - self.origin[2];
				d2 = dx*dx + dy*dy + dz*dz;
				if(d2 > best_d2) continue;

				dir = vectornormalize(other.origin - self.origin);
				dot = dir[0]*my_forward[0] + dir[1]*my_forward[1] + dir[2]*my_forward[2];
				if(dot < fov_cos) continue;

				other_eye = other getViewOrigin();
				if(!sightTracePassed(my_eye, other_eye, false, self)) continue;

				best = other;
				best_d2 = d2;
			}

			// Log only on target *change* — quiet under normal load.
			// Color codes: ^2=green ^1=red ^3=yellow ^7=white. Visible in
			// player chat (iprintln) and in docker logs (as raw ^N chars).
			if(isDefined(level.debug_bots) && level.debug_bots)
			{
				prev = self.bot_enemy;
				if(!isDefined(prev) && isDefined(best))
					iprintln("^2[bots] ^7" + self.name + " ^2ACQUIRE ^7" + best.name);
				else if(isDefined(prev) && !isDefined(best))
					iprintln("^1[bots] ^7" + self.name + " ^1LOST ^7" + prev.name);
				else if(isDefined(prev) && isDefined(best) && prev != best)
					iprintln("^3[bots] ^7" + self.name + " ^3SWITCH ^7" + prev.name + " ^3-> ^7" + best.name);
			}

			self.bot_enemy = best;
		}
	}
}
