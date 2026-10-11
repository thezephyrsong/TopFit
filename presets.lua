function TopFit:GetPresets()
        local playerClass = select(2,UnitClass("player"))
        local playerRace = select(2,UnitRace("player"))
        
        if not TopFit.presets then -- don't want to create new tables every time this function is called
                -- Hit/defense cap targets, in PERCENT (and Defense skill points), to match Forever's
                -- percent-based stat model (TOPFIT_HIT_CHANCE_ALL, TOPFIT_DEFENSE_FLAT; see
                -- procparser.lua). These were rating-based (8/10 rating per 1%, 1.5 rating per Defense
                -- skill) until 2026-10-10. The target percentages below are the old WotLK/Triumvirate
                -- boss-miss figures (17/14/11 spell, 27/24/8/5 melee, 140 skill for "uncrittable") and
                -- are NOT confirmed for Forever (Classic's tables differ, e.g. 9% rather than 8% for
                -- a two-hander), so every cap that uses them ships with active = false: present and
                -- editable (/topfit caps) but not applied until real Forever targets are known, the
                -- same call the Hunter preset below makes by having no caps at all.
                local spellCap = 17 - (playerRace == "Draenei" and 1 or 0) - ((playerClass == "PRIEST" or playerClass == "DRUID") and 3 or 0)
                local spellCapMinus3 = 14 - (playerRace == "Draenei" and 1 or 0) - ((playerClass == "PRIEST" or playerClass == "DRUID") and 3 or 0)
                local spellCapMinus6 = 11 - (playerRace == "Draenei" and 1 or 0) - ((playerClass == "PRIEST" or playerClass == "DRUID") and 3 or 0)
                local meleeCap = (TopFit.playerCanDualWield and 27 or 8) - (playerRace == "Draenei" and 1 or 0)
                local meleeCapMinus3 = ((TopFit.playerCanDualWield and playerClass ~= "HUNTER") and 24 or 5) - (playerRace == "Draenei" and 1 or 0)
                local meleeCapDW = 24
                -- "Uncrittable" Defense target in skill points (a flat 0.04%-per-point mechanic in the
                -- WotLK model; unconfirmed for Forever, see above).
                local defenseCap = 140
        
                TopFit.presets = {
		-- Death Knight preset removed 2026-09-26 (Dan confirmed): Death Knight does not
		-- exist as a playable class in WoW: Forever at all, so there is nothing to keep a
		-- preset for. This was also, independently, stale WotLK/Triumvirate rating-based
		-- data (ITEM_MOD_DEFENSE_SKILL_RATING_SHORT etc.) that would have been wrong for
		-- Forever's flat-percent stat model even if the class did exist. NOTE: every
		-- other class's preset in this file below is equally still WotLK-rating-based
		-- and has NOT been rewritten for Forever's stat model yet -- flagged in
		-- REWRITE_PLAN_12_1_5.md as separate outstanding work, not silently ignored.
                        -- First real Forever EP preset, 2026-09-27 -- everything below this
                        -- comment in this file is still the old WotLK/Triumvirate rating-based
                        -- data flagged above; this one entry is the start of replacing it with
                        -- real Forever numbers, not a continuation of the old pattern.
                        ["HUNTER"] = {
                                [1] = {
                                        name = "Hunter EP",
                                        -- Source: a live SixtyUpgrades export from Dan's own Forever Hunter
                                        -- "Zae" (sixtyupgrades.com/forever/... links present -- confirmed
                                        -- Forever-sourced, not a stand-in from another game mode), "points"
                                        -- block named "Hunter EP". Values copied directly, not adjusted:
                                        --   attackPower 1, rangedAttackPower 1, agility 2.79, crit 28.57,
                                        --   hit 21.98, rangedDps 14, rangedSpeed 100, intellect 1
                                        -- Two mapping decisions made converting SixtyUpgrades' field names to
                                        -- TopFit's stat keys, flagged here rather than silently assumed:
                                        --   "crit" -> TOPFIT_CRIT_CHANCE_PHYSICAL, not TOPFIT_CRIT_CHANCE_ALL,
                                        --     matching the same judgment call already made for the Lethal
                                        --     Attacks talent entry in talentbonuses.lua (a Hunter's crit stat
                                        --     is ranged+melee, not spells) -- not independently confirmed this
                                        --     is what SixtyUpgrades' own "crit" field actually represents.
                                        --   "rangedSpeed" -> TOPFIT_WEAPON_SPEED at face value (100). This
                                        --     number is far larger than every other value here (which are all
                                        --     single or low double digits) -- possibly a different internal
                                        --     scale/unit convention on SixtyUpgrades' side rather than a
                                        --     directly comparable EP weight. Used as-is since there's no basis
                                        --     to rescale it to something else, but worth treating with more
                                        --     suspicion than the rest of this preset until checked.
                                        -- "intellect" kept at its real value (1) rather than dropped -- now
                                        -- meaningfully non-zero for a reason beyond mana, via Careful Aim's
                                        -- Intellect->Attack Power conversion (see talentbonuses.lua and
                                        -- calculation.lua's GetEffectiveWeights).
                                        -- No caps included -- Forever's actual hit/crit cap target
                                        -- percentages (how much hit/crit is "enough" vs. a level-appropriate
                                        -- target) haven't been confirmed for this client, unlike the
                                        -- meleeCap/spellCap rating-based constants computed at the top of
                                        -- this file for the old WotLK model. Add caps once that's known
                                        -- rather than guess a target percentage here.
                                        weights = {
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.79,
                                                ["TOPFIT_CRIT_CHANCE_PHYSICAL"] = 28.57,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 21.98,
                                                ["TOPFIT_RANGED_DPS"] = 14, -- SixtyUpgrades "rangedDps": ranged weapons only (the generic DPS key would score melee weapons too)
                                                ["TOPFIT_WEAPON_SPEED"] = 100,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1,
                                        },
                                },
                                -- [2]-[4] below are the pre-Forever WotLK-model Hunter presets that used to live in a
                                -- second ["HUNTER"] = { ... } block further down this table. A duplicate key in a Lua
                                -- table constructor silently keeps only the LAST one, so that block overwrote "Hunter EP"
                                -- above and it never loaded. Merged here 2026-10-10 (not deleted: still stale, rating-era
                                -- numbers, kept until replaced with real Forever data like [1]).
                                [2] = {
                                        name = "Beastmastery",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.5,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 24.5,
                                                ["TOPFIT_HASTE_PERCENT"] = 17.5,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Marksmanship",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.19,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 23.1,
                                                ["TOPFIT_HASTE_PERCENT"] = 15.3,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1.22,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [4] = {
                                        name = "Survival",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.7,
                                                ["TOPFIT_HASTE_PERCENT"] = 17,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 22.4,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                        },
                                },
                        },
                        ["DRUID"] = {
                                [1] = {
                                        name = "Feral Tank",
                                        weights = {
                                                ["ITEM_MOD_STAMINA_SHORT"] = 3,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.5,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.1,
                                                ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = 1.2,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_DODGE_CHANCE_ALL"] = 12,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 7,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 5,
                                                ["TOPFIT_HASTE_PERCENT"] = 5,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.5,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Feral DPS",
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.379,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 22.8,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.15,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 28,
                                                ["TOPFIT_HASTE_PERCENT"] = 16.7,
                                                ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = 1.2,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Balance",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 9.8,
                                                ["TOPFIT_HASTE_PERCENT"] = 7,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.41,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.34,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCap,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [4] = {
                                        name = "Restoration",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["TOPFIT_HASTE_PERCENT"] = 10,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.5,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.396,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.285,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 1.4,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["MAGE"] = {
                                [1] = {
                                        name = "Arcane",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_HASTE_PERCENT"] = 9,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 8.26,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.45,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.4,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.1,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCapMinus6,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Fire",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 11.76,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.68,
                                                ["TOPFIT_HASTE_PERCENT"] = 6.6,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.56,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.35,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Frost",
                                        weights = {
                                                ["TOPFIT_HASTE_PERCENT"] = 13.17,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 8.974,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.439,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.185,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.167,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                        },
                        ["PALADIN"] = {
                                [1] = {
                                        name = "Holy",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1.375,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 15.75,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1,
                                                ["TOPFIT_HASTE_PERCENT"] = 7.5,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [2] = {
                                        name = "Retribution",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.53,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 17,
                                                ["TOPFIT_HASTE_PERCENT"] = 13,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.1,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 15.4,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 0.33,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Protection",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["TOPFIT_DEFENSE_FLAT"] = 1.5,
                                                ["TOPFIT_DODGE_CHANCE_ALL"] = 12,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 10,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 1,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1,
                                                ["TOPFIT_PARRY_CHANCE_ALL"] = 13.5,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.4,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.4,
                                                ["TOPFIT_BLOCK_CHANCE_ALL"] = 1.65,
                                                ["ITEM_MOD_BLOCK_VALUE_SHORT"] = 0.33,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 4.62,
                                                ["TOPFIT_HASTE_PERCENT"] = 3,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 0.2,
                                                ["RESISTANCE0_NAME"] = 0.06,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                                ["TOPFIT_DEFENSE_FLAT"] = {
                                                    {
                                                        ["value"] = defenseCap,
                                                        ["soft"] = true,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Defense Cap",
                                                    },
                                                },
                                        },
                                },
                        },
                        ["PRIEST"] = {
                                [1] = {
                                        name = "Shadow",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 9.8,
                                                ["TOPFIT_HASTE_PERCENT"] = 6,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.4,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.1,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Holy",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["TOPFIT_HASTE_PERCENT"] = 15,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.25,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.875,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.875,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 7,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [3] = {
                                        name = "Discipline",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["TOPFIT_HASTE_PERCENT"] = 15,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.25,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.875,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.875,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 7,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["ROGUE"] = {
                                [1] = {
                                        name = "Assassination",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 20,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.85,
                                                ["TOPFIT_HASTE_PERCENT"] = 16,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 18.2,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = math.ceil(22*10),
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Dual Wield Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Combat",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 20,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.85,
                                                ["TOPFIT_HASTE_PERCENT"] = 18,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 16.8,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = math.ceil(22*10),
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Dual Wield Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Subtlety",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 20,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.85,
                                                ["TOPFIT_HASTE_PERCENT"] = 16,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 18.2,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = math.ceil(22*10),
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Dual Wield Hit Cap",
                                                    },
                                                },
                                        },
                                },
                        },
                        ["SHAMAN"] = {
                                [1] = {
                                        name = "Enhancement",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 40,
                                                ["TOPFIT_HASTE_PERCENT"] = 19,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1.6,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.5,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1.4,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 12.6,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCap,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                    {
                                                        ["value"] = meleeCapDW,
                                                        ["soft"] = true,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Dual Wield Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Elemental",
                                        weights = {
                                                ["TOPFIT_HASTE_PERCENT"] = 10,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 9.1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Restoration",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["TOPFIT_HASTE_PERCENT"] = 12,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.2,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 14,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["WARLOCK"] = {
                                [1] = {
                                        name = "Affliction",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_HASTE_PERCENT"] = 7.5,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 7.7,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.54,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Demonology",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_HASTE_PERCENT"] = 7,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.65,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 8.4,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.3,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCap,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Destruction",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["TOPFIT_HASTE_PERCENT"] = 7,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.65,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 8.4,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = spellCap,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Spell Hit Cap",
                                                    },
                                                },
                                        },
                                },
                        },
                        ["WARRIOR"] = {
                                [1] = {
                                        name = "Fury",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.45,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 22,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 28,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.8,
                                                ["TOPFIT_HASTE_PERCENT"] = 14,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.05,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCapDW,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Dual Wield Hit Cap",
                                                    },
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Protection",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 1,
                                                ["TOPFIT_DEFENSE_FLAT"] = 1.2,
                                                ["TOPFIT_DODGE_CHANCE_ALL"] = 8.4,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 6.7,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.6,
                                                ["ITEM_MOD_BLOCK_VALUE_SHORT"] = 0.59,
                                                ["TOPFIT_PARRY_CHANCE_ALL"] = 8.7,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["TOPFIT_BLOCK_CHANCE_ALL"] = 1.75,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 0.33,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 2.8,
                                                ["TOPFIT_HASTE_PERCENT"] = 2,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.06,
                                                ["RESISTANCE0_NAME"] = 0.05,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                                ["TOPFIT_DEFENSE_FLAT"] = {
                                                    {
                                                        ["value"] = defenseCap,
                                                        ["soft"] = true,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Defense Cap",
                                                    },
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Arms",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.2,
                                                ["TOPFIT_CRIT_CHANCE_ALL"] = 23.8,
                                                ["TOPFIT_DODGE_PARRY_REDUCTION"] = 15,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.5,
                                                ["TOPFIT_HASTE_PERCENT"] = 13,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["TOPFIT_HIT_CHANCE_ALL"] = 5,
                                                ["RESISTANCE0_NAME"] = 0.01,
                                        },
                                        caps = {
                                                ["TOPFIT_HIT_CHANCE_ALL"] = {
                                                    {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = false,
                                                        ["active"] = false, -- unconfirmed for Forever, see constants at top
                                                        ["label"] = "Melee/Ability Hit Cap",
                                                    },
                                                },
                                        },
                                },
                        },
                }
        end
        
        return TopFit.presets[playerClass]
end
