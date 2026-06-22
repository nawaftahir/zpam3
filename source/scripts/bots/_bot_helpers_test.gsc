#include maps\mp\gametypes\global\_global;

// Chat-driven exercise of the 5 libcod perception helpers. Routed from
// _callbacksetup.gsc::CodeCallback_PlayerCommand when a player types !hp.
//
//   !hp           run all 5 from self.origin / self viewOrigin, default range
//   !hp pvs       getPVS only
//   !hp players   getPlayersInRange
//   !hp closest   getClosestPlayerInRange
//   !hp viewmulti getPlayersByViewOriginInRange
//   !hp view      getClosestPlayerByViewOriginInRange
//
// Output goes to the issuer's chat via iprintln so other players see nothing.

onPlayerCommand(args)
{
	self endon("disconnect");

	if (!isDefined(args[2]))
		sub = "all";
	else
		sub = args[2];

	if (sub == "all")
	{
		run_pvs();
		run_players();
		run_closest();
		run_view_closest();
		run_view_players();
	}
	else if (sub == "pvs")           run_pvs();
	else if (sub == "players")       run_players();
	else if (sub == "closest")       run_closest();
	else if (sub == "view")          run_view_closest();
	else if (sub == "viewmulti")     run_view_players();
	else self iprintln("^1!hp: unknown subcommand '" + sub + "'");
}

// getPVS between caller's eye and every other live player's eye
run_pvs()
{
	pool = getPlayersInRange((0, 0, 0), 100000.0 * 100000.0, -1);
	my_eye = self getViewOrigin();

	hits  = 0;
	skips = 0;
	for (i = 0; i < pool.size; i++)
	{
		p = pool[i];
		if (p == self) continue;
		if (getPVS(my_eye, p getViewOrigin()))
			hits += 1;
		else
			skips += 1;
	}
	self iprintln("^5[hp] ^7getPVS: visible=" + hits + " skipped=" + skips + " of " + (pool.size - 1) + " players");
}

run_players()
{
	r       = 2000.0 * 2000.0;
	all     = getPlayersInRange(self.origin, r,        -1);
	allies  = getPlayersInRange(self.origin, r,         2);
	axis    = getPlayersInRange(self.origin, r,         1);
	self iprintln("^5[hp] ^7getPlayersInRange(2000): all=" + all.size + " allies=" + allies.size + " axis=" + axis.size);
}

run_closest()
{
	r    = 2000.0 * 2000.0;
	near = getClosestPlayerInRange(self.origin, r, -1);
	if (isDefined(near))
		self iprintln("^5[hp] ^7getClosestPlayerInRange: ^6" + near.name);
	else
		self iprintln("^5[hp] ^7getClosestPlayerInRange: ^1none");
}

run_view_closest()
{
	r    = 2000.0 * 2000.0;
	near = getClosestPlayerByViewOriginInRange(self getViewOrigin(), r, -1);
	if (isDefined(near))
		self iprintln("^5[hp] ^7getClosestPlayerByViewOriginInRange: ^6" + near.name);
	else
		self iprintln("^5[hp] ^7getClosestPlayerByViewOriginInRange: ^1none");
}

run_view_players()
{
	r       = 2000.0 * 2000.0;
	all     = getPlayersByViewOriginInRange(self getViewOrigin(), r, -1);
	self iprintln("^5[hp] ^7getPlayersByViewOriginInRange(2000): n=" + all.size);
}
