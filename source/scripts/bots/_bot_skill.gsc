#include maps\mp\gametypes\global\_global;

// Four skill tiers. Knobs based on the master synthesis plan §9.
// Profiles are built lazily on first access and cached on level.
//
//   Tier 1 — Recruit  : slow react, sloppy aim, fires often
//   Tier 2 — Regular  : middle of the road
//   Tier 3 — Veteran  : tight aim, fair reaction
//   Tier 4 — Elite    : near-instant react, wide cone, snap aim

get_profile(skill)
{
	if(!isDefined(level.bot_profiles))
		build_profiles();

	if(skill < 1 || skill > 4)
		skill = randomint(4) + 1;

	return level.bot_profiles[skill];
}

build_profiles()
{
	level.bot_profiles = [];
	level.bot_profiles[1] = recruit();
	level.bot_profiles[2] = regular();
	level.bot_profiles[3] = veteran();
	level.bot_profiles[4] = elite();
}

// view_dist_sq: squared world-units, used directly without sqrt
// fov_cos: cosine of FOV half-angle; -1 = full sphere, +1 = forward only
// reaction_ms: gap between "saw nothing" and "engages first target"
// aim_blend: 0..1 lerp factor applied per 50ms combat tick
// aim_noise_deg: +/- degrees of random jitter added to each aim sample
// fire_cooldown_ms: ms between trigger pulses
// fire_angle_deg: aim must be within this angle of target before firing

recruit()
{
	p = spawnstruct();
	p.view_dist_sq    = 1200 * 1200;
	p.fov_cos         = 0.34;   // ~70 deg cone
	p.reaction_ms     = 700;
	p.aim_blend       = 0.10;
	p.aim_noise_deg   = 4.5;
	p.fire_cooldown_ms = 400;
	p.fire_angle_deg  = 10;
	return p;
}

regular()
{
	p = spawnstruct();
	p.view_dist_sq    = 1800 * 1800;
	p.fov_cos         = 0.17;   // ~80 deg cone
	p.reaction_ms     = 400;
	p.aim_blend       = 0.20;
	p.aim_noise_deg   = 2.5;
	p.fire_cooldown_ms = 300;
	p.fire_angle_deg  = 8;
	return p;
}

veteran()
{
	p = spawnstruct();
	p.view_dist_sq    = 2200 * 2200;
	p.fov_cos         = -0.17;  // ~100 deg cone
	p.reaction_ms     = 200;
	p.aim_blend       = 0.40;
	p.aim_noise_deg   = 1.0;
	p.fire_cooldown_ms = 220;
	p.fire_angle_deg  = 6;
	return p;
}

elite()
{
	p = spawnstruct();
	p.view_dist_sq    = 2600 * 2600;
	p.fov_cos         = -0.64;  // ~130 deg cone (near full half-sphere)
	p.reaction_ms     = 100;
	p.aim_blend       = 0.60;
	p.aim_noise_deg   = 0.4;
	p.fire_cooldown_ms = 180;
	p.fire_angle_deg  = 4;
	return p;
}

tier_name(skill)
{
	if(skill == 1) return "Recruit";
	if(skill == 2) return "Regular";
	if(skill == 3) return "Veteran";
	if(skill == 4) return "Elite";
	return "Mixed";
}
