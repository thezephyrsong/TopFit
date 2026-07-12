function TopFit:GetPresets()
        local playerClass = select(2,UnitClass("player"))
        local playerRace = select(2,UnitRace("player"))
        
        if not TopFit.presets then -- don't want to create new tables every time this function is called
                -- Rating-per-percent conversion for hit rating scales with player level. 26.23 (spell)
                -- and 32.79 (melee) are the retail level-80 constants; Triumvirate is a level-60 cap
                -- server, where the confirmed conversions (cross-checked against simc-triumvirate and
                -- in-game tooltips) are 8 rating/1% spell hit and 10 rating/1% melee hit. The target
                -- percentages themselves (17/14/11 spell, 27/8/24/5 melee) come from the fixed +3-level
                -- boss/player level-difference mechanic and are unaffected by the level-60 cap, so only
                -- the conversion constants change here.
                local spellCap = math.ceil(8 * (17 - (playerRace == "Draenei" and 1 or 0) - ((playerClass == "PRIEST" or playerClass == "DRUID") and 3 or 0)))
                local spellCapMinus3 = math.ceil(8 * (14 - (playerRace == "Draenei" and 1 or 0) - ((playerClass == "PRIEST" or playerClass == "DRUID") and 3 or 0)))
                local spellCapMinus6 = math.ceil(8 * (11 - (playerRace == "Draenei" and 1 or 0) - ((playerClass == "PRIEST" or playerClass == "DRUID") and 3 or 0)))
                local meleeCap = math.ceil(10 * ((TopFit.playerCanDualWield and 27 or 8) - (playerRace == "Draenei" and 1 or 0)))
                local meleeCapMinus3 = math.ceil(10 * (((TopFit.playerCanDualWield and playerClass ~= "HUNTER") and 24 or 5) - (playerRace == "Draenei" and 1 or 0)))
                local meleeCapDW = math.ceil(10 * 24)
        
                TopFit.presets = {
                        ["DEATHKNIGHT"] = {
                                [1] = {
                                        name = "Blood Tank",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 1,
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = 0.8,
                                                ["ITEM_MOD_DODGE_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 0.67,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.6,
                                                ["ITEM_MOD_PARRY_RATING_SHORT"] = 0.58,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 0.33,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 0.2,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.2,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.06,
                                                ["RESISTANCE0_NAME"] = 0.05,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = {
                                                        ["value"] = 689,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Frost Tank",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 41.9,
                                                ["ITEM_MOD_PARRY_RATING_SHORT"] = 10,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 9.7,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 9.6,
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = 8.5,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 6.9,
                                                ["ITEM_MOD_DODGE_RATING_SHORT"] = 6.1,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 6.1,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 6.1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 4.9,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 4.1,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 3.1,
                                                ["RESISTANCE0_NAME"] = 0.5,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCapDW,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = {
                                                        ["value"] = "689",
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Blood DPS",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 4,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.6,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.4,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 0.1,
                                                ["RESISTANCE0_NAME"] = 0.01,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [4] = {
                                        name = "Frost DPS",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.9,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 1.7,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.3,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.3,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.1,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCapDW,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [5] = {
                                        name = "Unholy DPS",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 3.2,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.9,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.7,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.1,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = true,
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
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_DODGE_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.5,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Feral DPS",
                                        weights = {
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.379,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 2.28,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.15,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.67,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 1.66,
                                                ["ITEM_MOD_FERAL_ATTACK_POWER_SHORT"] = 1.2,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Balance",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.41,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.34,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCap,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [4] = {
                                        name = "Restoration",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.5,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.396,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.285,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.1,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                        },
                        ["HUNTER"] = {
                                [1] = {
                                        name = "Beastmastery",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.5,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.75,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.75,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 1.5,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Marksmanship",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.19,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.65,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.53,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 1.52,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1.22,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Survival",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 12.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 2.7,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.7,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.6,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 1.33,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                        },
                        ["MAGE"] = {
                                [1] = {
                                        name = "Arcane",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.9,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.59,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.45,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.4,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.1,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCapMinus6,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Fire",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.84,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.68,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.66,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.56,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.35,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Frost",
                                        weights = {
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.317,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.641,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 0.439,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.185,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.167,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
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
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.125,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.75,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [2] = {
                                        name = "Retribution",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.53,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 1.7,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.3,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 0.33,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Protection",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_DODGE_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 1,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1,
                                                ["ITEM_MOD_PARRY_RATING_SHORT"] = 0.9,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.4,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.4,
                                                ["ITEM_MOD_BLOCK_RATING_SHORT"] = 0.33,
                                                ["ITEM_MOD_BLOCK_VALUE_SHORT"] = 0.33,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.33,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.3,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 0.2,
                                                ["RESISTANCE0_NAME"] = 0.06,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = {
                                                        ["value"] = 689,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                        },
                        ["PRIEST"] = {
                                [1] = {
                                        name = "Shadow",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.6,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.4,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.1,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Holy",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.5,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.25,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.875,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.875,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {},
                                },
                                [3] = {
                                        name = "Discipline",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.5,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.25,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.875,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.875,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.5,
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
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.85,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.6,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.3,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 0.8,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = math.ceil(22*10),
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Combat",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.85,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.8,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 1.2,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.2,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = math.ceil(22*10),
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Subtlety",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.85,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.6,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.3,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 0.8,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = math.ceil(22*10),
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                        },
                        ["SHAMAN"] = {
                                [1] = {
                                        name = "Enhancement",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 4,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.9,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 1.6,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.5,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1.4,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 1.1,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.9,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 0.43,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCapDW,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Elemental",
                                        weights = {
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1,
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.65,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Restoration",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.2,
                                                ["ITEM_MOD_MANA_REGENERATION_SHORT"] = 1.2,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1,
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
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.75,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.55,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.54,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCapMinus3,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Demonology",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.65,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.6,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.3,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCap,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Destruction",
                                        weights = {
                                                ["ITEM_MOD_SPELL_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_SPIRIT_SHORT"] = 0.65,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.6,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_INTELLECT_SHORT"] = 0.2,
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 0.001,
                                                ["RESISTANCE0_NAME"] = 0.001,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = spellCap,
                                                        ["soft"] = false,
                                                        ["active"] = true,
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
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 2.2,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 2,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.8,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.4,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.05,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCapDW,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [2] = {
                                        name = "Protection",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STAMINA_SHORT"] = 1,
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = 0.8,
                                                ["ITEM_MOD_DODGE_RATING_SHORT"] = 0.7,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 0.67,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 0.6,
                                                ["ITEM_MOD_BLOCK_VALUE_SHORT"] = 0.59,
                                                ["ITEM_MOD_PARRY_RATING_SHORT"] = 0.58,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["ITEM_MOD_BLOCK_RATING_SHORT"] = 0.35,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 0.33,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 0.2,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 0.2,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 0.2,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 0.06,
                                                ["RESISTANCE0_NAME"] = 0.05,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                                ["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = {
                                                        ["value"] = "689",
                                                        ["soft"] = true,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                                [3] = {
                                        name = "Arms",
                                        weights = {
                                                ["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = 14,
                                                ["ITEM_MOD_STRENGTH_SHORT"] = 2.2,
                                                ["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = 2.3,
                                                ["ITEM_MOD_CRIT_RATING_SHORT"] = 1.7,
                                                ["ITEM_MOD_EXPERTISE_RATING_SHORT"] = 1.5,
                                                ["ITEM_MOD_AGILITY_SHORT"] = 1.5,
                                                ["ITEM_MOD_HASTE_RATING_SHORT"] = 1.3,
                                                ["ITEM_MOD_ATTACK_POWER_SHORT"] = 1,
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = 0.5,
                                                ["RESISTANCE0_NAME"] = 0.01,
                                        },
                                        caps = {
                                                ["ITEM_MOD_HIT_RATING_SHORT"] = {
                                                        ["value"] = meleeCap,
                                                        ["soft"] = false,
                                                        ["active"] = true,
                                                },
                                        },
                                },
                        },
                }
        end
        
        return TopFit.presets[playerClass]
end
