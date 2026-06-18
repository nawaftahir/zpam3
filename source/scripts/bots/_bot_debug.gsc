#include maps\mp\gametypes\global\_global;

// Live skill overlay. One HUD line per bot, top-left of screen. Visible to
// everyone when debug_bots is on, all elems destroyed when it's off.
//
// Row format:  bot<N>   T<tier> <TierName>     (color = state)
//   gray   = idle / no target
//   yellow = reaction window
//   red    = engaging
//
// Bot names (bot0..bot63) and the 5 tier labels are precached once at level
// init so setText is legal at runtime.

init()
{
	level.bot_dbg_label = [];
	level.bot_dbg_label[0] = "T? Mixed";
	level.bot_dbg_label[1] = "T1 Recruit";
	level.bot_dbg_label[2] = "T2 Regular";
	level.bot_dbg_label[3] = "T3 Veteran";
	level.bot_dbg_label[4] = "T4 Elite";

	// Anchor elems hold the strings alive so setText is legal post-init.
	level.bot_dbg_anchor = [];
	for(i = 0; i < 5; i++)
	{
		a = newHudElem2();
		a setText(level.bot_dbg_label[i]);
		a.alpha = 0;
		a.x = 0;
		a.y = 0;
		level.bot_dbg_anchor[i] = a;
	}

	level thread run();
}

run()
{
	level endon("game_ended");

	for(;;)
	{
		wait level.fps_multiplier * 0.4;

		on = (isDefined(level.debug_bots) && level.debug_bots);
		bots = get_bots();

		if(!on)
		{
			for(i = 0; i < bots.size; i++)
				cleanup(bots[i]);
			continue;
		}

		row = 0;
		for(i = 0; i < bots.size; i++)
		{
			b = bots[i];
			if(!isDefined(b))
				continue;

			if(!isDefined(b.bot_dbg_label))
				attach(b);

			place(b, row);
			paint(b);
			row += 1;
		}
	}
}

get_bots()
{
	out = [];
	players = getentarray("player", "classname");
	for(i = 0; i < players.size; i++)
	{
		p = players[i];
		if(!isDefined(p.pers["isBot"]) || !p.pers["isBot"])
			continue;
		out[out.size] = p;
	}
	return out;
}

attach(b)
{
	b.bot_dbg_label = newHudElem2();
	b.bot_dbg_label.alignX = "left";
	b.bot_dbg_label.alignY = "top";
	b.bot_dbg_label.horzAlign = "fullscreen";
	b.bot_dbg_label.vertAlign = "fullscreen";
	b.bot_dbg_label.fontScale = 1.0;
	b.bot_dbg_label.alpha = 1;

	b.bot_dbg_name = newHudElem2();
	b.bot_dbg_name.alignX = "left";
	b.bot_dbg_name.alignY = "top";
	b.bot_dbg_name.horzAlign = "fullscreen";
	b.bot_dbg_name.vertAlign = "fullscreen";
	b.bot_dbg_name.fontScale = 1.0;
	b.bot_dbg_name.alpha = 1;
	b.bot_dbg_name.color = (1, 1, 1);
	b.bot_dbg_name setValue(b getEntityNumber());

	b thread cleanup_on_disconnect();
}

cleanup_on_disconnect()
{
	self waittill("disconnect");
	cleanup(self);
}

cleanup(b)
{
	if(isDefined(b.bot_dbg_label))
	{
		b.bot_dbg_label destroy();
		b.bot_dbg_label = undefined;
	}
	if(isDefined(b.bot_dbg_name))
	{
		b.bot_dbg_name destroy();
		b.bot_dbg_name = undefined;
	}
}

place(b, row)
{
	y = 60 + row * 12;
	b.bot_dbg_name.x = 8;
	b.bot_dbg_name.y = y;
	b.bot_dbg_label.x = 40;
	b.bot_dbg_label.y = y;
}

paint(b)
{
	tier = 0;
	if(isDefined(b.bot_skill_tier))
		tier = b.bot_skill_tier;
	if(tier < 0 || tier > 4)
		tier = 0;

	b.bot_dbg_label setText(level.bot_dbg_label[tier]);

	col = (0.55, 0.55, 0.55); // idle / gray
	if(isDefined(b.bot_enemy) && isAlive(b.bot_enemy))
		col = (1, 0.25, 0.25); // engaging / red
	else if(isDefined(b.bot_react_until))
		col = (1, 0.85, 0.25); // reacting / yellow

	b.bot_dbg_label.color = col;
}
