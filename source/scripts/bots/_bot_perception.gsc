#include maps\mp\gametypes\global\_global;

// Picks closest visible enemy each tick. Filter chain (cheap to expensive):
//   range^2 -> FOV cosine -> getPVS -> sightTracePassed
//
// Reaction gate: first sighting commits after reaction_ms; switches between
// visible targets are instant.
run()
{
	self endon("disconnect");

	// Phase offset: spread 32 bots across frames instead of stacking on one tick.
	if(isDefined(self.bot_phase))
		wait level.fps_multiplier * self.bot_phase;

	self.bot_last_seen_ms = 0;

	self.bot_pvs_calls       = 0;
	self.bot_pvs_skipped     = 0;
	self.bot_pvs_traces      = 0;
	self.bot_pvs_trace_hit   = 0;
	self.bot_pvs_trace_miss  = 0;
	self.bot_pvs_log_next    = gettime() + 10000;

	self.bot_threats_samples = 0;
	self.bot_threats_sum     = 0;
	self.bot_threats_peak    = 0;
	self.bot_threats_log_next = gettime() + 10000;

	self.bot_xcheck_total  = 0;
	self.bot_xcheck_agree  = 0;
	self.bot_xcheck_log_next = gettime() + 10000;

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

		my_eye     = self getViewOrigin();
		my_forward = anglestoforward(self getPlayerAngles());
		team_based = (isDefined(level.gametype) && level.gametype != "dm");
		enemy_team = enemy_team_id(team_based);

		// MASK_OPAQUE: solid + glass + slime — what blocks a player from seeing.
		mask = 524545;

		// One engine call: closest live enemy whose view origin is within
		// range AND LOS-visible from my eye. Replaces the manual range+FOV+
		// PVS+sightTrace loop. FOV filter is still applied in GSC because the
		// native doesn't know our forward vector.
		candidate = getClosestPlayerByViewOriginInRange(my_eye, self.bot_view_dist_sq, enemy_team, mask);

		best = undefined;
		if(isDefined(candidate) && candidate != self && isAlive(candidate))
		{
			dir = vectornormalize(candidate.origin - self.origin);
			dot = dir[0]*my_forward[0] + dir[1]*my_forward[1] + dir[2]*my_forward[2];
			if(dot >= self.bot_fov_cos)
				best = candidate;
		}

		// Track PVS stats by counting how often the native's result is the
		// same target as the previous tick (cheap proxy for "trace work
		// saved by sticky perception").
		self.bot_pvs_calls += 1;
		if(isDefined(best) && isDefined(self.bot_enemy) && best == self.bot_enemy)
			self.bot_pvs_skipped += 1;
		else if(isDefined(best))
			self.bot_pvs_trace_hit += 1;
		else
			self.bot_pvs_trace_miss += 1;

		log_pvs_summary();

		threat_count = count_visible_threats(my_eye, team_based);
		self.bot_visible_threats = threat_count;

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
			self scripts\bots\_bot_log::log_event("perception", "saw", "2", committed.name);
		else if(isDefined(prev) && !isDefined(committed))
			self scripts\bots\_bot_log::log_event("perception", "lost", "1", prev.name);
		else if(isDefined(prev) && isDefined(committed) && prev != committed)
			self scripts\bots\_bot_log::log_event("perception", "switch", "3", prev.name + " -> " + committed.name);

		self.bot_enemy = committed;
		if(isDefined(committed))
		{
			self.bot_last_seen_ms  = gettime();
			self.bot_last_enemy_pos = committed.origin;
		}
	}
}

// Single-call sanity probe via getClosestPlayerByViewOriginInRange with the
// built-in LOS trace. Counters feed the periodic xcheck summary.
cross_check_view_native(my_eye, team_based, loop_best)
{
	enemy_team = enemy_team_id(team_based);
	mask       = 524545;   // MASK_OPAQUE = solid + glass + slime
	native_best = getClosestPlayerByViewOriginInRange(my_eye, self.bot_view_dist_sq, enemy_team, mask);

	self.bot_xcheck_total += 1;

	agree = false;
	if(!isDefined(native_best) && !isDefined(loop_best))
		agree = true;
	else if(isDefined(native_best) && isDefined(loop_best) && native_best == loop_best)
		agree = true;

	if(agree)
		self.bot_xcheck_agree += 1;
}

// Count alive opposing-team players visible from my_eye via the consolidated
// native with built-in LOS trace. Updates running min/max/avg for the
// periodic threats summary.
count_visible_threats(my_eye, team_based)
{
	enemy_team = enemy_team_id(team_based);
	mask       = 524545;
	threats    = getPlayersByViewOriginInRange(my_eye, self.bot_view_dist_sq, enemy_team, mask);

	n = threats.size;
	self.bot_threats_samples += 1;
	self.bot_threats_sum     += n;
	if(n > self.bot_threats_peak)
		self.bot_threats_peak = n;

	log_threats_summary();
	log_xcheck_summary();

	return n;
}

enemy_team_id(team_based)
{
	if(!team_based || !isDefined(self.pers["team"]))
		return -1;
	if(self.pers["team"] == "allies")
		return 1;
	return 2;
}

log_pvs_summary()
{
	if(!isDefined(level.debug_bot_flags) || !isDefined(level.debug_bot_flags["pvs"]) || !level.debug_bot_flags["pvs"])
		return;
	if(gettime() < self.bot_pvs_log_next)
		return;

	total = self.bot_pvs_calls;
	if(total > 0)
	{
		skip_pct = (self.bot_pvs_skipped * 100) / total;
		tag = "calls=" + total + " skip=" + self.bot_pvs_skipped + "(" + skip_pct + "%) traces=" + self.bot_pvs_traces + " hit=" + self.bot_pvs_trace_hit + " miss=" + self.bot_pvs_trace_miss;
		self scripts\bots\_bot_log::log_event("pvs", "pvs", "5", tag);
	}

	self.bot_pvs_calls      = 0;
	self.bot_pvs_skipped    = 0;
	self.bot_pvs_traces     = 0;
	self.bot_pvs_trace_hit  = 0;
	self.bot_pvs_trace_miss = 0;
	self.bot_pvs_log_next   = gettime() + 10000;
}

log_threats_summary()
{
	if(!isDefined(level.debug_bot_flags) || !isDefined(level.debug_bot_flags["threats"]) || !level.debug_bot_flags["threats"])
		return;
	if(gettime() < self.bot_threats_log_next)
		return;

	if(self.bot_threats_samples > 0)
	{
		avg10 = int((self.bot_threats_sum * 10) / self.bot_threats_samples);
		tag   = "samples=" + self.bot_threats_samples + " peak=" + self.bot_threats_peak + " avg=" + int(avg10 / 10) + "." + int(avg10 % 10);
		self scripts\bots\_bot_log::log_event("threats", "threats", "3", tag);
	}

	self.bot_threats_samples = 0;
	self.bot_threats_sum     = 0;
	self.bot_threats_peak    = 0;
	self.bot_threats_log_next = gettime() + 10000;
}

log_xcheck_summary()
{
	if(!isDefined(level.debug_bot_flags) || !isDefined(level.debug_bot_flags["xcheck"]) || !level.debug_bot_flags["xcheck"])
		return;
	if(gettime() < self.bot_xcheck_log_next)
		return;

	if(self.bot_xcheck_total > 0)
	{
		pct = (self.bot_xcheck_agree * 100) / self.bot_xcheck_total;
		tag = "agree=" + self.bot_xcheck_agree + "/" + self.bot_xcheck_total + " (" + pct + "%)";
		self scripts\bots\_bot_log::log_event("xcheck", "xcheck", "2", tag);
	}

	self.bot_xcheck_total = 0;
	self.bot_xcheck_agree = 0;
	self.bot_xcheck_log_next = gettime() + 10000;
}
