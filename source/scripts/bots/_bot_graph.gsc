#include maps\mp\gametypes\global\_global;

// A* over the waypoint pool maintained by _bot_waypoints. Node count is
// capped at 64 by the ring buffer, so linear-scan min-f selection is fine
// (no priority queue needed). Hard iteration cap as a runaway guard.
//
// plan(start_origin, goal_origin) returns an array of waypoint origins from
// (nearest-to-start) to (nearest-to-goal), inclusive. Empty array on trivial
// success (same node). undefined if no path. Iteration cap (200) lives
// inline in plan() — GSC has no module-level constants.

nearest_node(origin)
{
	if(!isDefined(level.bot_waypoints) || level.bot_waypoints.size == 0)
		return -1;

	best_i  = -1;
	best_d2 = 0;
	for(i = 0; i < level.bot_waypoints.size; i++)
	{
		if(!isDefined(level.bot_waypoints[i])) continue;
		d2 = distanceSquared(origin, level.bot_waypoints[i]);
		if(best_i < 0 || d2 < best_d2)
		{
			best_i  = i;
			best_d2 = d2;
		}
	}
	return best_i;
}

plan(start_origin, goal_origin)
{
	start_idx = nearest_node(start_origin);
	goal_idx  = nearest_node(goal_origin);

	if(start_idx < 0 || goal_idx < 0)
		return undefined;
	if(start_idx == goal_idx)
		return [];

	n = level.bot_waypoints.size;
	in_open  = [];
	closed   = [];
	g_score  = [];
	parent   = [];
	open_idx = [];

	for(i = 0; i < n; i++)
	{
		in_open[i] = false;
		closed[i]  = false;
		g_score[i] = 999999;
		parent[i]  = -1;
	}

	g_score[start_idx] = 0;
	open_idx[0] = start_idx;
	in_open[start_idx] = true;

	goal_pos = level.bot_waypoints[goal_idx];
	iters    = 0;

	while(open_idx.size > 0 && iters < 200)
	{
		iters += 1;

		// Linear scan for min-f over the open set
		best_i = 0;
		best_f = g_score[open_idx[0]] + heuristic_to(open_idx[0], goal_pos);
		for(i = 1; i < open_idx.size; i++)
		{
			f = g_score[open_idx[i]] + heuristic_to(open_idx[i], goal_pos);
			if(f < best_f)
			{
				best_f = f;
				best_i = i;
			}
		}

		cur = open_idx[best_i];
		if(cur == goal_idx)
			return reconstruct(parent, goal_idx);

		open_idx = remove_at(open_idx, best_i);
		in_open[cur] = false;
		closed[cur]  = true;

		nbrs = level.bot_wp_neighbors[cur];
		if(!isDefined(nbrs)) continue;

		for(i = 0; i < nbrs.size; i++)
		{
			nb = nbrs[i];
			if(closed[nb]) continue;

			step = edge_cost(cur, nb);
			tentative_g = g_score[cur] + step;
			if(tentative_g < g_score[nb])
			{
				parent[nb]  = cur;
				g_score[nb] = tentative_g;
				if(!in_open[nb])
				{
					open_idx[open_idx.size] = nb;
					in_open[nb] = true;
				}
			}
		}
	}

	return undefined;
}

heuristic_to(idx, goal_pos)
{
	// Squared distance keeps A* admissible up to scale — fine because we
	// compare same-shape f values; never call sqrt in the inner loop.
	d2 = distanceSquared(level.bot_waypoints[idx], goal_pos);
	return d2;
}

edge_cost(a, b)
{
	return distanceSquared(level.bot_waypoints[a], level.bot_waypoints[b]);
}

reconstruct(parent, goal_idx)
{
	rev = [];
	cur = goal_idx;
	guard = 0;
	while(cur >= 0 && guard < 200)
	{
		rev[rev.size] = level.bot_waypoints[cur];
		cur = parent[cur];
		guard += 1;
	}
	// rev is goal -> start; flip to start -> goal
	out = [];
	for(i = rev.size - 1; i >= 0; i -= 1)
		out[out.size] = rev[i];
	return out;
}

remove_at(arr, idx)
{
	out = [];
	for(i = 0; i < arr.size; i++)
		if(i != idx)
			out[out.size] = arr[i];
	return out;
}
