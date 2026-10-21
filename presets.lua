-- Preset stat weights, replaced 2026-10-12 with the output of a fresh WoW: Forever sim
-- (Damage/DPS metric, 10000 iterations; per-spec stat weights pasted by Dan).
--
-- How the sim columns map onto TopFit's stats:
--   * Strength/Agility/Intellect/Spirit, Attack Power, Ranged Attack Power, MP5 -> the same stat.
--   * Spell Damage -> TOPFIT_SPELL_DAMAGE_FLAT. Healing power is not in a damage-metric sim, so it is 0.
--   * The sim weighs RATING points; TopFit works in percent (Forever itemizes percent), so each rating
--     weight is multiplied by its rating-per-percent rate (TopFit.RATING_PER_PERCENT in core.lua):
--     hit and haste and expertise x10, crit x14.
--   * Melee Hit -> TOPFIT_HIT_CHANCE_ALL, Spell Hit -> TOPFIT_HIT_CHANCE_SPELL; same for crit
--     (ALL / SPELL). Pure casters have no melee column, so their spell hit and crit weights go on BOTH
--     keys: gear that says "Improves your chance to hit/get a critical strike" feeds the generic key.
--   * Melee Haste and Spell Haste -> TOPFIT_HASTE_PERCENT (Forever has one combined attack/casting
--     speed line). Expertise -> TOPFIT_DODGE_PARRY_REDUCTION.
--   * Armor Penetration is dropped: no Forever item has the stat.
--   * Weapon DPS is not a sim stat. It is set from the game's own conversion, 14 attack power = 1 weapon
--     DPS, so melee specs get ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 14 x Attack Power weight and Hunter gets
--     TOPFIT_RANGED_DPS = 14 x Ranged Attack Power weight. Casters keep a 0.001 wand tie-break. Druid
--     feral specs use no weapon DPS; their Feral Attack Power uses the Attack Power weight (assumed equal).
--   * Armor keeps a 0.001 tie-break everywhere.
--
-- Caveats:
--   * No caps. The sim's hit/expertise weights are marginal values below the cap (a weight of 0.00 means
--     the sim was already capped), and Forever's cap targets are unconfirmed, so TopFit will over-value
--     hit and expertise until you add caps in /topfit caps.
--   * "(damage metric)" tank presets hold threat/damage weights only. Stamina, defense, dodge, parry, block
--     are not in this sim's output, so tank survivability is not valued; adjust the weights yourself.
--   * Healers have no preset: the sim table has no healing-metric specs.
--   * The sim's Intellect weights already include the Intellect -> Attack Power / Spell Damage talents
--     (Careful Aim, Mental Dexterity, Champion of the Light...), assuming the sim's full talent
--     loadout. These sets carry weightsAssumeFullTalents = true: TopFit's talent credit runs in
--     reverse for them (calculation.lua, GetEffectiveWeights), taking back the share of each talent
--     the player has not got, instead of adding it a second time.
-- BEGIN GENERATED SIM PRESETS -- written by tools/gen_presets.py; edit the script, not this block
-- Source: the Forever sim's ui/specs/*/*/presets.ts EP presets.
-- Rating points per 1% at level 60 (CombatRatings.txt): hit 10, crit 14, haste 10, expertise 10, dodge 12, parry 15, block 5, defense 1.
TopFit.simPresets = {
	["DRUID"] = {
		{
			name = "Sim: Balance: P1",
			simSpec = "druid/balance",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.28,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.15,
				["ITEM_MOD_SPIRIT_SHORT"] = 0,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_ARCANE_DAMAGE_FLAT"] = 0.68,
				["TOPFIT_CRIT_CHANCE_ALL"] = 10.64,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 10.64,
				["TOPFIT_HASTE_PERCENT"] = 9.9,
				["TOPFIT_HIT_CHANCE_ALL"] = 14.8,
				["TOPFIT_HIT_CHANCE_SPELL"] = 14.8,
				["TOPFIT_NATURE_DAMAGE_FLAT"] = 0.32,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
			},
			caps = {},
		},
		{
			name = "Sim: Balance: Pre-BiS",
			simSpec = "druid/balance",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0,
				["ITEM_MOD_SPIRIT_SHORT"] = 0,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_ARCANE_DAMAGE_FLAT"] = 0.68,
				["TOPFIT_CRIT_CHANCE_ALL"] = 10.64,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 10.64,
				["TOPFIT_HASTE_PERCENT"] = 9.5,
				["TOPFIT_HIT_CHANCE_ALL"] = 14.5,
				["TOPFIT_HIT_CHANCE_SPELL"] = 14.5,
				["TOPFIT_NATURE_DAMAGE_FLAT"] = 0.32,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
			},
			caps = {},
		},
	},
	["PALADIN"] = {
		{
			name = "Sim: Retribution: Holy Shock",
			simSpec = "paladin/retribution",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 3.11,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_INTELLECT_SHORT"] = 4.53,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.01,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 0.01,
				["ITEM_MOD_STRENGTH_SHORT"] = 2.5,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 65.24,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 62,
				["TOPFIT_HASTE_PERCENT"] = 40.6,
				["TOPFIT_HIT_CHANCE_ALL"] = 102.5,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 5.78,
			},
			caps = {},
		},
		{
			name = "Sim: Retribution: Twist of Light",
			simSpec = "paladin/retribution",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 2.23,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_INTELLECT_SHORT"] = 2.06,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.23,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 0.01,
				["ITEM_MOD_STRENGTH_SHORT"] = 2.4,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 43.12,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 51,
				["TOPFIT_HASTE_PERCENT"] = 228.7,
				["TOPFIT_HIT_CHANCE_ALL"] = 68.3,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 2.36,
			},
			caps = {},
		},
	},
	["PRIEST"] = {
		{
			name = "Sim: Priest DPS: Shadow",
			simSpec = "priest/dps",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.24,
				["ITEM_MOD_SPIRIT_SHORT"] = 0.01,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 11.76,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 11.76,
				["TOPFIT_HASTE_PERCENT"] = 7.3,
				["TOPFIT_HIT_CHANCE_ALL"] = 11.4,
				["TOPFIT_HIT_CHANCE_SPELL"] = 11.4,
				["TOPFIT_SHADOW_DAMAGE_FLAT"] = 1,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
			},
			caps = {},
		},
		{
			name = "Sim: Priest DPS: Smite",
			simSpec = "priest/dps",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.58,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.46,
				["ITEM_MOD_SPIRIT_SHORT"] = 0.57,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 4.48,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 4.48,
				["TOPFIT_HASTE_PERCENT"] = 4.3,
				["TOPFIT_HIT_CHANCE_ALL"] = 3.7,
				["TOPFIT_HIT_CHANCE_SPELL"] = 3.7,
				["TOPFIT_HOLY_DAMAGE_FLAT"] = 0.81,
				["TOPFIT_SHADOW_DAMAGE_FLAT"] = 0.19,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
			},
			caps = {},
		},
		{
			name = "Sim: Priest Healer: Disc Raid Healing",
			simSpec = "priest/healer",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.19,
				["ITEM_MOD_SPIRIT_SHORT"] = 0.1,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 6.72,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 6.72,
				["TOPFIT_HASTE_PERCENT"] = 1,
				["TOPFIT_SPELL_HEALING_FLAT"] = 1,
			},
			caps = {},
		},
		{
			name = "Sim: Priest Healer: Disc Single-Target",
			simSpec = "priest/healer",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.4,
				["ITEM_MOD_SPIRIT_SHORT"] = 0.15,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 9.8,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 9.8,
				["TOPFIT_HASTE_PERCENT"] = 1.5,
				["TOPFIT_SPELL_HEALING_FLAT"] = 1,
			},
			caps = {},
		},
		{
			name = "Sim: Priest Healer: Holy Raid Healing",
			simSpec = "priest/healer",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.3,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.6,
				["ITEM_MOD_SPIRIT_SHORT"] = 0.25,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 3.22,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 3.22,
				["TOPFIT_HASTE_PERCENT"] = 4.8,
				["TOPFIT_SPELL_HEALING_FLAT"] = 1,
			},
			caps = {},
		},
		{
			name = "Sim: Priest Healer: Holy Single-Target",
			simSpec = "priest/healer",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.35,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.6,
				["ITEM_MOD_SPIRIT_SHORT"] = 0.3,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 4.2,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 4.2,
				["TOPFIT_HASTE_PERCENT"] = 5,
				["TOPFIT_SPELL_HEALING_FLAT"] = 1,
			},
			caps = {},
		},
	},
	["ROGUE"] = {
		{
			name = "Sim: Rogue: Assassination",
			simSpec = "rogue/dps",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 2.06,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 0.65,
				["ITEM_MOD_STAMINA_SHORT"] = 0.01,
				["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 28.28,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 27.7,
				["TOPFIT_HASTE_PERCENT"] = 19.3,
				["TOPFIT_HIT_CHANCE_ALL"] = 28,
			},
			caps = {},
		},
		{
			name = "Sim: Rogue: Combat Daggers",
			simSpec = "rogue/dps",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 1.95,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 0.21,
				["ITEM_MOD_STAMINA_SHORT"] = 0.01,
				["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 23.52,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 22.1,
				["TOPFIT_HASTE_PERCENT"] = 17,
				["TOPFIT_HIT_CHANCE_ALL"] = 23.5,
			},
			caps = {},
		},
		{
			name = "Sim: Rogue: Combat Sinister",
			simSpec = "rogue/dps",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 1.96,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 0.19,
				["ITEM_MOD_STAMINA_SHORT"] = 0.01,
				["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 23.8,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 25.5,
				["TOPFIT_HASTE_PERCENT"] = 17.2,
				["TOPFIT_HIT_CHANCE_ALL"] = 24.2,
			},
			caps = {},
		},
		{
			name = "Sim: Rogue: Subtlety",
			simSpec = "rogue/dps",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 1.93,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 0.16,
				["ITEM_MOD_STAMINA_SHORT"] = 0.01,
				["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 22.82,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 24.2,
				["TOPFIT_HASTE_PERCENT"] = 14.3,
				["TOPFIT_HIT_CHANCE_ALL"] = 21.2,
			},
			caps = {},
		},
	},
	["SHAMAN"] = {
		{
			name = "Sim: Elemental: Testing",
			simSpec = "shaman/elemental",
			weights = {
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
				["ITEM_MOD_INTELLECT_SHORT"] = 0.19,
				["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.04,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 1.81,
				["ITEM_MOD_SPIRIT_SHORT"] = 0.02,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 8.54,
				["TOPFIT_CRIT_CHANCE_SPELL"] = 8.54,
				["TOPFIT_FIRE_DAMAGE_FLAT"] = 0.31,
				["TOPFIT_HASTE_PERCENT"] = 12.3,
				["TOPFIT_HIT_CHANCE_ALL"] = 11.8,
				["TOPFIT_HIT_CHANCE_SPELL"] = 11.8,
				["TOPFIT_NATURE_DAMAGE_FLAT"] = 0.69,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
			},
			caps = {},
		},
		{
			name = "Sim: Enhancement: Pre-BiS",
			simSpec = "shaman/enhancement",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 1.32,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_INTELLECT_SHORT"] = 1.99,
				["ITEM_MOD_SPELL_PENETRATION_SHORT"] = 2.52,
				["ITEM_MOD_STRENGTH_SHORT"] = 2.2,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 33.88,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 35,
				["TOPFIT_HASTE_PERCENT"] = 28.1,
				["TOPFIT_HIT_CHANCE_ALL"] = 52,
				["TOPFIT_NATURE_DAMAGE_FLAT"] = 0.72,
				["TOPFIT_SPELL_DAMAGE_FLAT"] = 1.27,
			},
			caps = {},
		},
	},
	["WARRIOR"] = {
		{
			name = "Sim: Warrior: Pre-BiS - Arms",
			simSpec = "warrior/dps",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 1.82,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_STRENGTH_SHORT"] = 2.2,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 33.04,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 22.3,
				["TOPFIT_HASTE_PERCENT"] = 20,
				["TOPFIT_HIT_CHANCE_ALL"] = 45.9,
			},
			caps = {},
		},
		{
			name = "Sim: Warrior: Pre-BiS - Fury",
			simSpec = "warrior/dps",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 2.25,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
				["ITEM_MOD_STRENGTH_SHORT"] = 2.2,
				["RESISTANCE0_NAME"] = 0.001,
				["TOPFIT_CRIT_CHANCE_ALL"] = 40.88,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 19,
				["TOPFIT_HASTE_PERCENT"] = 22.9,
				["TOPFIT_HIT_CHANCE_ALL"] = 22.9,
			},
			caps = {},
		},
		{
			name = "Sim: Protection Warrior: Pre-BiS (Defense Cap)",
			simSpec = "warrior/protection",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 0.66,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.27,
				["ITEM_MOD_BLOCK_VALUE_SHORT"] = 0.6,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 3.78,
				["ITEM_MOD_STAMINA_SHORT"] = 1.15,
				["ITEM_MOD_STRENGTH_SHORT"] = 0.62,
				["RESISTANCE0_NAME"] = 0.05,
				["TOPFIT_BLOCK_CHANCE_ALL"] = 0.1,
				["TOPFIT_CRIT_CHANCE_ALL"] = 8.12,
				["TOPFIT_DEFENSE_FLAT"] = 0.22,
				["TOPFIT_DODGE_CHANCE_ALL"] = 2.04,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 23.2,
				["TOPFIT_HASTE_PERCENT"] = 3.6,
				["TOPFIT_HIT_CHANCE_ALL"] = 11.3,
				["TOPFIT_PARRY_CHANCE_ALL"] = 2.7,
			},
			caps = {},
		},
		{
			name = "Sim: Protection Warrior: Pre-BiS (Threat)",
			simSpec = "warrior/protection",
			weights = {
				["ITEM_MOD_AGILITY_SHORT"] = 0.61,
				["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.27,
				["ITEM_MOD_BLOCK_VALUE_SHORT"] = 0.6,
				["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 3.78,
				["ITEM_MOD_STAMINA_SHORT"] = 1.15,
				["ITEM_MOD_STRENGTH_SHORT"] = 0.62,
				["RESISTANCE0_NAME"] = 0.05,
				["TOPFIT_BLOCK_CHANCE_ALL"] = 0.05,
				["TOPFIT_CRIT_CHANCE_ALL"] = 7.7,
				["TOPFIT_DEFENSE_FLAT"] = 0.26,
				["TOPFIT_DODGE_CHANCE_ALL"] = 1.56,
				["TOPFIT_DODGE_PARRY_REDUCTION"] = 23.5,
				["TOPFIT_HASTE_PERCENT"] = 3.8,
				["TOPFIT_HIT_CHANCE_ALL"] = 0.5,
				["TOPFIT_PARRY_CHANCE_ALL"] = 2.25,
			},
			caps = {},
		},
	},
}
-- END GENERATED SIM PRESETS

-- The presets below are hand-made from per-spec sim runs. The block above holds the Forever sim's own EP-weight
-- presets, regenerated by `python tools/gen_presets.py` (or tools/update_data.py) whenever the sim is updated;
-- they are appended after the hand-made ones as "Sim: <spec>: <preset>" and never replace one.
function TopFit:GetPresets()
        local playerClass = select(2,UnitClass("player"))
        
        if not TopFit.presets then -- don't want to create new tables every time this function is called
                TopFit.presets = {
                        ["DRUID"] = {
                                [1] = {
                                        name = "Balance",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Spell Damage = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.21,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.02,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 8.8,
                                                ["TOPFIT_HIT_CHANCE_SPELL"] = 8.8,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 8.82,
                                                ["TOPFIT_CRIT_CHANCE_SPELL"] = 8.82,
                                                ["TOPFIT_HASTE_PERCENT"] = 7.1,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.12,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [2] = {
                                        name = "Feral Bear (damage metric)",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Agility = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.75,
                                                ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = 0.75,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 20.58,
                                                ["TOPFIT_HASTE_PERCENT"] = 9,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 36.7,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [3] = {
                                        name = "Feral Cat",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Agility = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.09,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.5,
                                                ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = 0.5,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5.2,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 10.08,
                                                ["TOPFIT_HASTE_PERCENT"] = 1.9,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 4.9,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["HUNTER"] = {
                                [1] = {
                                        name = "Hunter",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Agility = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1.15,
                                                ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = 0.39,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 11,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 11.34,
                                                ["TOPFIT_HASTE_PERCENT"] = 5.6,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.28,
                                                ["TOPFIT_RANGED_DPS"] = 5.46,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["MAGE"] = {
                                [1] = {
                                        name = "Mage",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Spell Damage = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.17,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 16.9,
                                                ["TOPFIT_HIT_CHANCE_SPELL"] = 16.9,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 10.78,
                                                ["TOPFIT_CRIT_CHANCE_SPELL"] = 10.78,
                                                ["TOPFIT_HASTE_PERCENT"] = 13.6,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["PALADIN"] = {
                                [1] = {
                                        name = "Protection (damage metric)",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Strength = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.85,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.01,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.45,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 1.82,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 18.48,
                                                ["TOPFIT_CRIT_CHANCE_SPELL"] = 0.28,
                                                ["TOPFIT_HASTE_PERCENT"] = 13.2,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 29,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 6.3,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [2] = {
                                        name = "Retribution",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Strength = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.94,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1.93,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.42,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 1.65,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 16.94,
                                                ["TOPFIT_HASTE_PERCENT"] = 11.7,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 15.4,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 5.88,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["PRIEST"] = {
                                [1] = {
                                        name = "Shadow",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Spell Damage = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.23,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.02,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 10.9,
                                                ["TOPFIT_HIT_CHANCE_SPELL"] = 10.9,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 12.88,
                                                ["TOPFIT_CRIT_CHANCE_SPELL"] = 12.88,
                                                ["TOPFIT_HASTE_PERCENT"] = 5.8,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.09,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["ROGUE"] = {
                                [1] = {
                                        name = "Rogue",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Attack Power = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.94,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 21.6,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 22.12,
                                                ["TOPFIT_HASTE_PERCENT"] = 13.6,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 21.6,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["SHAMAN"] = {
                                [1] = {
                                        name = "Elemental",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Spell Damage = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.5,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 10.2,
                                                ["TOPFIT_HIT_CHANCE_SPELL"] = 10.2,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 7.98,
                                                ["TOPFIT_CRIT_CHANCE_SPELL"] = 7.98,
                                                ["TOPFIT_HASTE_PERCENT"] = 6.1,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.7,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [2] = {
                                        name = "Enhancement",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Attack Power = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.09,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 2.42,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 0.95,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 21.1,
                                                ["TOPFIT_HIT_CHANCE_SPELL"] = 8.5,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 21.28,
                                                ["TOPFIT_CRIT_CHANCE_SPELL"] = 3.5,
                                                ["TOPFIT_HASTE_PERCENT"] = 17.3,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 32.9,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["WARLOCK"] = {
                                [1] = {
                                        name = "Warlock",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Spell Damage = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.38,
                                                ["TOPFIT_SPELL_DAMAGE_FLAT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 9.4,
                                                ["TOPFIT_HIT_CHANCE_SPELL"] = 9.4,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 11.34,
                                                ["TOPFIT_CRIT_CHANCE_SPELL"] = 11.34,
                                                ["TOPFIT_HASTE_PERCENT"] = 4.6,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.22,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["WARRIOR"] = {
                                [1] = {
                                        name = "DPS Warrior",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Strength = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.69,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.45,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 16.2,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 12.04,
                                                ["TOPFIT_HASTE_PERCENT"] = 9.2,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 10.2,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 6.3,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [2] = {
                                        name = "Protection (damage metric)",
                                        weightsAssumeFullTalents = true,
                                        -- sim weights are relative to Strength = 1 for this spec
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.41,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.44,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 15.82,
                                                ["TOPFIT_HASTE_PERCENT"] = 7.5,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 37.5,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 6.16,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                }

                for classToken, list in pairs(TopFit.simPresets or {}) do
                        local classPresets = TopFit.presets[classToken]
                        if not classPresets then
                                classPresets = {}
                                TopFit.presets[classToken] = classPresets
                        end
                        local have = {}
                        for _, preset in ipairs(classPresets) do have[preset.name] = true end
                        for _, preset in ipairs(list) do
                                if not have[preset.name] then table.insert(classPresets, preset) end
                        end
                end
        end
        
        return TopFit.presets[playerClass]
end
