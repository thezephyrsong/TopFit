TopFit
======

Author: Mirroar (Thyrfall @ EU-Die Todeskrallen) - continued by Zae
Version: see TopFit.toc
WoW Version: WoW: Forever (see TopFit.toc for the interface number)

GitHub:       http://github.com/thezephyrsong/TopFit

Data sources and credits
------------------------
The item proc data (procdata.lua), item set data (setdata.lua) and the "Sim:" stat-weight presets (presets.lua)
are generated from the WoWSims Forever project: https://github.com/wowsims/forever
(MIT License, Copyright (c) 2022 wowsims team). The license text and a description of what is derived from it
are in THIRD_PARTY_NOTICES.md. TopFit does not include any WoWSims code.
World of Warcraft is a trademark of Blizzard Entertainment. TopFit is not affiliated with or endorsed by
Blizzard Entertainment or the WoWSims team.

1. Description
--------------
TopFit is a gear management addon designed to select the best gear for you when you just can't be bothered to compare items yourself.
To make intelligent gear choices for you, you will first have to create item scales, telling the addon which stats are the most important to you. After that, just put all interesting items into your inventory and start the calculation. Voila, you have a fine new equipment set, which you can update with a single click from now on.

TopFit scores every item you carry by your stat weights and then picks the best combination for all slots. On top of that it:
 - honors caps you set (a hit chance cap for damage dealers, a defense cap for tanks, etc.),
 - credits item set bonuses (2/3/4... piece effects) when wearing a few more pieces of a set is worth more than the best single items,
 - averages the stats of on-use item effects over time, using their real duration and cooldown (chance-based procs are not valued yet),
 - lets you pick which enchant each group of gear is assumed to carry, and
 - checks whether you can dual wield, which armor types you may wear, and similar restrictions.

2. Quickstart
-------------

Opening TopFit:
 - Left-click the TopFit minimap button (a golden sword), or type /tf show.
 - There is also a TopFit tab beside the character window.
 - Ctrl+Click on the minimap button, or /tf options, opens the Interface Options page.

How to level an alt without worrying about equipment:
1. Create a set with fitting values for your character, or add one of the predefined sets.
2. In TopFit's Interface Options menu, choose that set under "Automatic update set".
3. Have fun playing! Your equipment will automatically be updated whenever you get a new equippable item.
   (This is meant for levelling. With more than one specialization it may equip this set even while your other spec is active.)

How to create your own sets:
1. Click the blue plus sign next to the set dropdown and pick "Empty Set" or a preset. The presets are:
   - ready-made weights for classes and specs (named after the class/spec), and
   - the "Sim:" presets, which come straight from the WoWSims Forever simulator's own stat weights.
   You can also import weights from a string (see "Importing and exporting" below) or rename the default set by clicking its big name.
2. Open the "Weights & Caps" tab, expand the window with the ">>" button if needed, and add any stat with "Add Stat...". Click a stat to set its weight.
3. If you need a cap, click the check box next to the stat's value. A new line appears where you can set the cap value; click the text next to it to choose a hard or soft cap.
4. Click "Start".
5. TopFit equips the result (unless you included virtual items, see below) and saves it as a Blizzard equipment set named after your set, shortened, followed by "(TF)".

Extra options per set: force a specific item for a slot ("Force Item for <slot>" in the calculation window), force armor type (only wear your class's armor material), simulate dual wield, force two-handed weapons, and whether the set's scores appear in item tooltips.

3. Importing and exporting
--------------------------
Weights:
 - /tf import (or Shift+Click on the minimap button, or the import/export button next to the set dropdown) takes a Pawn, AskMrRobot or TopFit string.
 - If you already have a set with the same name, or a set selected, TopFit asks whether to update that set with the new weights or to create a new set. Updating replaces the set's weights, keeps its name, forced items, assumed enchants and caps (caps are only replaced if the string contains caps), and keeps any "SET: ..." weights you added by hand.
 - /tf export exports the selected set as a TopFit string; /tf export pawn uses Pawn's format.

Your gear for the WoWSims simulator:
 - /tf simc (or Right-Click on the minimap button, or "Export equipped gear (SimC)" in the import/export menu) shows a string for your worn gear, race, level and talents. Paste it into the simulator's addon import.
 - Professions are not exported; set them in the simulator.

A note on stat units: on Forever, hit, crit, haste, dodge, parry, block (and defense skill) work in percent, not ratings. Weights for those stats are per 1% (defense: per skill point). Pawn strings are taken as given. Weights from a rating-based source, such as the simulator's own EP weights, have to be multiplied by the rating points needed for 1%; the "Sim:" presets are already converted.

4. In-depth: Stat-weights and Caps
----------------------------------
Once upon a time, in a simplified world where you can only equip a single item...

Whenever you calculate a set in TopFit, it will first of all scan all the items in your inventory and those that are equipped on your character. These items are then given a score depending on the stat weights you set.
Say [Item A] has 10 agility, 2% hit chance and 1% critical strike chance, and you gave agility a weight of 1 and each percent of hit and crit a weight of 2, but nothing else. [Item A] will then have a score of 16 (10 * 1 + 2 * 2 + 1 * 2).
[Item B], which has 20 strength and 5% hit chance, will then have a score of 10 (20 * 0 + 5 * 2). In this case, [Item A] is the better choice.

In another scenario though, you might only want 5% hit chance. Any more than that is a waste for you, so you set a hard cap of 5. TopFit will then try to give you at least 5%, but will ignore any excess on items. The weight you set for hit chance will actually be ignored as long as the cap can be reached.
To be specific, [Item A], now with a score of 12 (10 * 1 + 2 * 0 + 1 * 2) will be considered better than [Item B], which now has a score of 0. Any other item with a score higher than 12 will be considered better than [Item A], as long as it has at least 5% hit chance. If it has less, it will not be considered for calculation.

The matter is entirely different if you set a cap to be a "soft cap", like you might do with defense as a tank, for example. This is because you have to hit this defense cap, but any excess defense still benefits you somewhat.
If you set a soft cap of 10 defense, for example, TopFit is still forced to equip at least 10 defense with your items, but will gladly take more if it can.
Comparing [Item C] (10 stamina, 10 defense) and [Item D] (8 stamina, 15 defense), with both stats valued at 1, will give you [Item D] as the winner, even though it has less stamina. Any item with less than 10 defense will still not fulfill our cap, and is therefore not chosen, no matter how much stamina it has.

These examples are of course extremely simplified, in WoW you can wear more than one item. When TopFit calculates a set with a cap, it has to reach that cap with the sum of all equipped items. Single items might not contribute to caps at all, or only little, but will be chosen based on score instead.

5. Item sets, effects, enchants and virtual items
-------------------------------------------------
Item set bonuses: when your bags hold pieces of a set, TopFit also tries wearing more of them. Each bonus whose stats you value is added to the combination's score and cap totals, counting each different item once. Bonuses that are not plain stats (procs, movement speed, ...) are ignored. Weapons are left as the normal calculation picked them.

Use effects and procs: an on-use item (a trinket, for instance) counts as its stats multiplied by how much of the time it is active (duration divided by cooldown). Effects that only trigger by chance, such as "chance on hit", are not valued yet, because that depends on how often you attack; items with one are marked as having an unscored proc.

Enchants: enchants are not counted on the items themselves, since any enchant can go on whichever item you wear. Use the "Enchants" tab to choose which enchant each gear group is assumed to have.

Virtual items: the "Virtual Items" tab lets you add items you do not have yet, to see what they would do to your set. When a calculation includes virtual items, TopFit shows the result but does not equip anything.

6. Slash commands
-----------------
/tf, /topfit            open the options
/tf show                show the calculation window
/tf options             show the options
/tf import              import a Pawn / AskMrRobot / TopFit string
/tf export [pawn]       export the selected set
/tf simc                export your equipped gear for the WoWSims simulator
/tf caps                list, add, remove or toggle caps for the selected set (type it alone for help)
/tf unrecognized        list stats and "Equip:" lines TopFit has seen but can't score yet
/tf itemdump <link>     show what TopFit reads from one item's tooltip
/tf talentdebug         print talent information, for debugging
/tf saveset [name]      save the gear you wear into an equipment set (for testing)
/tf weapondebug         print weapon slot information, for debugging

7. Feature Suggestions
----------------------
If you're missing a feature in TopFit, first check the project's GitHub page and see if it is already mentioned there, please. If not, feel free to open an issue with your suggestion.

8. What to do if you encounter a bug
------------------------------------
If anything does not work as intended, you'll again want to check the GitHub page and its open issues before posting about it. When you report something, please say which game build you are on and what you did; for item problems, the output of /tf itemdump <link> helps a lot. I'll try to get back to you as soon as possible, or maybe another helpful user will be able to provide you with the necessary hints.
