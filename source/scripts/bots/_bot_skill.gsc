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

	if (getCvarInt("scr_bots_profiles_load"))
		try_load_overrides();
}

// Optional JSON overlay. Lets server owners tune knobs without recompiling.
// Schema (all fields optional, missing falls back to compiled-in):
//   { "recruit": { "view_dist": 1200, "fov_deg": 70, "reaction_ms": 700,
//                  "aim_blend": 0.10, "aim_noise_deg": 4.5,
//                  "fire_cooldown_ms": 400, "fire_angle_deg": 10 },
//     "regular": {...}, "veteran": {...}, "elite": {...} }
//
// view_dist is plain world units, squared on apply. fov_deg is the FOV cone
// half-angle in degrees (matches the comments next to the compiled-in tiers);
// stored as cosine on apply. Both are friendlier to hand-edit than the raw
// squared / cosine forms.
try_load_overrides()
{
	data = json_load("bot_profiles.json");
	if (!isDefined(data))
		return;

	apply_one(1, "recruit", data);
	apply_one(2, "regular", data);
	apply_one(3, "veteran", data);
	apply_one(4, "elite",   data);

	iprintln("^5[bot] ^7profiles: overrides loaded from bot_profiles.json");
}

apply_one(slot, key, data)
{
	if (!isDefined(data[key]))
		return;
	src = data[key];
	p = level.bot_profiles[slot];

	if (isDefined(src["view_dist"]))
		p.view_dist_sq = src["view_dist"] * src["view_dist"];
	if (isDefined(src["fov_deg"]))
		p.fov_cos = cos(src["fov_deg"]);
	if (isDefined(src["reaction_ms"]))
		p.reaction_ms = src["reaction_ms"];
	if (isDefined(src["aim_blend"]))
		p.aim_blend = src["aim_blend"];
	if (isDefined(src["aim_noise_deg"]))
		p.aim_noise_deg = src["aim_noise_deg"];
	if (isDefined(src["aim_turn_rate_dps"]))
		p.aim_turn_rate_dps = src["aim_turn_rate_dps"];
	if (isDefined(src["fire_cooldown_ms"]))
		p.fire_cooldown_ms = src["fire_cooldown_ms"];
	if (isDefined(src["fire_angle_deg"]))
		p.fire_angle_deg = src["fire_angle_deg"];

	if (isDefined(src["peek_chance_per_sec"]))
		p.peek_chance_per_sec = src["peek_chance_per_sec"];
	if (isDefined(src["peek_lean_enabled"]))
		p.peek_lean_enabled = src["peek_lean_enabled"];
	if (isDefined(src["peek_jump_enabled"]))
		p.peek_jump_enabled = src["peek_jump_enabled"];
	if (isDefined(src["peek_prone_range"]))
		p.peek_prone_range_sq = src["peek_prone_range"] * src["peek_prone_range"];
	if (isDefined(src["peek_duration_ms"]))
		p.peek_duration_ms = src["peek_duration_ms"];
	if (isDefined(src["peek_cooldown_ms"]))
		p.peek_cooldown_ms = src["peek_cooldown_ms"];
}

// view_dist_sq: squared world-units, used directly without sqrt
// fov_cos: cosine of FOV half-angle; -1 = full sphere, +1 = forward only
// reaction_ms: gap between "saw nothing" and "engages first target"
// aim_blend: 0..1 lerp factor applied per 50ms combat tick
// aim_noise_deg: +/- degrees of random jitter added to each aim sample
// fire_cooldown_ms: ms between trigger pulses
// fire_angle_deg: aim must be within this angle of target before firing
//
// Combat peek knobs (consumed by scripts\bots\_bot_peek):
//   peek_chance_per_sec : probability of starting a peek action per second
//                         of engagement (0 = never peek)
//   peek_lean_enabled   : 1 = may use setLean(left|right)
//   peek_jump_enabled   : 1 = may pulse a jump-shot
//   peek_prone_range_sq : >0 = may drop prone if target is further than this
//                         (squared world-units; 0 = never prone)
//   peek_duration_ms    : how long a single peek action is held
//   peek_cooldown_ms    : minimum gap between peeks

recruit()
{
	p = spawnstruct();
	p.view_dist_sq    = 1500 * 1500;
	p.fov_cos         = 0.34;          // ~70 deg cone
	p.reaction_ms     = 550;
	p.aim_blend       = 0.20;          // legacy knob, unused by new aim model
	p.aim_noise_deg   = 4.0;           // per-shot offset peak (degrees)
	p.aim_turn_rate_dps = 180;
	p.fire_cooldown_ms = 350;
	p.fire_angle_deg  = 7;
	p.peek_chance_per_sec = 0.0;
	p.peek_lean_enabled   = 0;
	p.peek_jump_enabled   = 0;
	p.peek_prone_range_sq = 0;
	p.peek_duration_ms    = 700;
	p.peek_cooldown_ms    = 2500;
	return p;
}

regular()
{
	p = spawnstruct();
	p.view_dist_sq    = 2000 * 2000;
	p.fov_cos         = 0.17;          // ~80 deg cone
	p.reaction_ms     = 280;
	p.aim_blend       = 0.25;
	p.aim_noise_deg   = 2.5;
	p.aim_turn_rate_dps = 260;
	p.fire_cooldown_ms = 260;
	p.fire_angle_deg  = 5;
	p.peek_chance_per_sec = 0.05;
	p.peek_lean_enabled   = 1;
	p.peek_jump_enabled   = 0;
	p.peek_prone_range_sq = 0;
	p.peek_duration_ms    = 700;
	p.peek_cooldown_ms    = 2200;
	return p;
}

veteran()
{
	p = spawnstruct();
	p.view_dist_sq    = 2200 * 2200;
	p.fov_cos         = -0.17;         // ~100 deg cone
	p.reaction_ms     = 180;
	p.aim_blend       = 0.30;
	p.aim_noise_deg   = 1.5;
	p.aim_turn_rate_dps = 360;
	p.fire_cooldown_ms = 220;
	p.fire_angle_deg  = 3.5;
	p.peek_chance_per_sec = 0.15;
	p.peek_lean_enabled   = 1;
	p.peek_jump_enabled   = 1;
	p.peek_prone_range_sq = 0;
	p.peek_duration_ms    = 800;
	p.peek_cooldown_ms    = 1800;
	return p;
}

elite()
{
	p = spawnstruct();
	p.view_dist_sq    = 2600 * 2600;
	p.fov_cos         = -0.64;         // ~130 deg cone
	p.reaction_ms     = 110;
	p.aim_blend       = 0.40;
	p.aim_noise_deg   = 0.8;
	p.aim_turn_rate_dps = 500;
	p.fire_cooldown_ms = 180;
	p.fire_angle_deg  = 2.5;
	p.peek_chance_per_sec = 0.30;
	p.peek_lean_enabled   = 1;
	p.peek_jump_enabled   = 1;
	p.peek_prone_range_sq = 900 * 900;
	p.peek_duration_ms    = 900;
	p.peek_cooldown_ms    = 1400;
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
