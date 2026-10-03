-- Talent-granted percent stat bonuses -- WoW: Forever.
--
-- TopFit's caps only ever look at gear (see calculation.lua). A percentage a talent grants
-- directly never shows up on an item tooltip, so without this table TopFit has no way to know
-- about it and will keep asking for more gear-based percent than you actually need once you've
-- taken the talent.
--
-- REWRITTEN 2026-09-26 for Forever. The old version of this file (WotLK/Triumvirate) doesn't
-- apply anymore, for two independent reasons, not just one:
--   1. Triumvirate is cancelled.
--   2. Even setting that aside, the whole MECHANISM changed. Forever's talents are read via
--      TopFit:GetRetailTalentRanks() (core.lua), which uses the modern C_ClassTalents/C_Traits
--      node system -- talents are addressed by spellID/name, NOT by (tab, index), which doesn't
--      exist in this system at all. And Forever's itemization is flat percent, not WotLK-style
--      rating (see MIGRATION_WOWFOREVER.md section 8) -- so a talent granting "+1% crit" should
--      credit a TOPFIT_CRIT_CHANCE_ALL-style pseudo-stat directly, not get converted through a
--      rating-per-percent constant into ITEM_MOD_CRIT_RATING_SHORT the way the old file did.
--
-- Entry fields:
--   name            the talent's spell name, exactly as GetRetailTalentRanks()'s ranksByName
--                    table keys it. Confirm via "/topfit talentdebug" on a real character with
--                    the talent taken -- that command prints every active node's exact name,
--                    spellID, and rank, so you can copy the string instead of guessing at
--                    capitalization or wording.
--   spellID         optional but preferred once confirmed -- more stable than name across
--                    locale/rewording. Checked first if present; falls back to name if not
--                    given or not found. Same "/topfit talentdebug" output provides this too.
--   stat            the TOPFIT_* pseudo-stat key to credit (see procparser.lua's
--                    PermanentPercentStatPatterns and core.lua's statList for the full list --
--                    e.g. TOPFIT_HIT_CHANCE_ALL, TOPFIT_CRIT_CHANCE_ALL,
--                    TOPFIT_CRIT_CHANCE_MELEE/_RANGED/_SPELL, TOPFIT_DODGE_PARRY_REDUCTION). A
--                    real ITEM_MOD_*_RATING token would be wrong here -- those stats don't exist
--                    in Forever's itemization model at all (see section 8 above).
--   percentPerPoint percent granted per talent rank.
--
-- ONLY entries with real, confirmed data go here. An empty/missing class entry is a no-op --
-- intentional, not an oversight to guess-fill. Every entry below traces back to a specific
-- source; add that same trail for anything new.

TopFit.talentRatingBonuses = {}

-- Source: wowforevertalents.com Shaman page. Originally sourced from a BlizzCon 2026 footage
-- scrape (lower confidence); the Thundering Strikes/Tidal Focus entries below were independently
-- re-confirmed 2026-09-26 against a full class-data pass that IS client-data-sourced via
-- wago.tools -- both talents matched exactly, so treat those two as confirmed-by-client-data now,
-- same confidence tier as Warrior below. Anticipation added from that same newer pass (missed in
-- the original footage-based scrape). Still no numeric spellID available from either source --
-- name match only, to be confirmed against live "/topfit talentdebug" output.
TopFit.talentRatingBonuses["SHAMAN"] = {
	-- Thundering Strikes (Enhancement): "Improves your chance to get a critical strike with all
	-- spells and attacks by 1%" per rank, 5 ranks.
	{ name = "Thundering Strikes", stat = "TOPFIT_CRIT_CHANCE_ALL", percentPerPoint = 1 },
	-- Tidal Focus (Restoration): "...improves your chance to hit by 1%" per rank, 5 ranks (also
	-- reduces healing mana cost by 1%/rank, not itemization-relevant, not modeled here).
	{ name = "Tidal Focus", stat = "TOPFIT_HIT_CHANCE_ALL", percentPerPoint = 1 },
	-- Anticipation (Enhancement): "Increases your chance to dodge by an additional 2%" per rank,
	-- 3 ranks (max rank confirmed 3 in Forever, was 5 ranks/1% each in Classic).
	{ name = "Anticipation", stat = "TOPFIT_DODGE_CHANCE_ALL", percentPerPoint = 2 },
}

-- Source: wowforevertalents.com Warrior page, saved copy provided directly (not the earlier
-- BlizzCon-footage scrape) -- MUCH higher confidence than the Shaman entries above: this page's
-- own data is sourced from actual WoW: Forever beta client trait data via wago.tools (build
-- 1.60.1.70009), with a side-by-side Classic Era comparison per talent, not footage guesses.
-- Still no numeric spellID available from this source (same limitation as Shaman) -- name match
-- only, to be confirmed against live "/topfit talentdebug" output.
--
-- Talents seen but deliberately NOT included here, with why:
--   Toughness (Protection): "Increases your Armor value from items by 2%" per rank -- this is a
--     multiplicative armor scalar, not an additive stat bonus, and doesn't fit this table's
--     {stat, percentPerPoint} model at all. Would need its own dedicated handling in
--     calculation.lua if ever modeled, not a talentbonuses.lua entry.
--   Weaponmaster (Arms): grants a DIFFERENT effect depending on the equipped weapon type
--     (Axe/Polearm crit%, Mace/Staff armor pen%, Sword extra-attack chance) -- too conditional
--     on current gear to express as a flat per-rank bonus here.
--   Dual Wield Specialization (Fury): grants three simultaneous effects (off-hand damage%,
--     off-hand Rage generation%, off-hand hit%), none of which are known to be itemized on gear
--     separately from general hit/damage stats -- low value for the gear-cap-crediting purpose
--     this table exists for, and the multi-effect shape doesn't fit cleanly either.
TopFit.talentRatingBonuses["WARRIOR"] = {
	-- Deflection (Arms): "Increases your Parry chance by N%" per rank, 5 ranks, unchanged from
	-- Classic per the source's own comparison.
	{ name = "Deflection", stat = "TOPFIT_PARRY_CHANCE_ALL", percentPerPoint = 1 },
	-- Cruelty (Fury): "Improves your chance to get a critical strike with melee attacks by N%"
	-- per rank, 5 ranks.
	{ name = "Cruelty", stat = "TOPFIT_CRIT_CHANCE_MELEE", percentPerPoint = 1 },
	-- Precision (Fury, new talent -- added, not in Classic): "Improves your chance to hit by N%"
	-- per rank, 3 ranks. Phrasing doesn't specify melee-only, matches the generic/combined
	-- template elsewhere in this codebase -- mapped to the "ALL" variant.
	{ name = "Precision", stat = "TOPFIT_HIT_CHANCE_ALL", percentPerPoint = 1 },
	-- Anticipation (Protection -- a different talent from Shaman's same-named one above, do not
	-- confuse the two): "Increases your Defense Skill by 4" per rank, 5 ranks. Flat, not
	-- percent -- matches TOPFIT_DEFENSE_FLAT's existing flat-stat convention exactly.
	{ name = "Anticipation", stat = "TOPFIT_DEFENSE_FLAT", percentPerPoint = 4 },
	-- Shield Specialization (Protection): "Increases your chance to Block attacks with your
	-- shield by N%" per rank, 5 ranks (also grants a Rage-on-Block proc, not modeled here --
	-- proc effects are procparser.lua's domain, not this table's).
	{ name = "Shield Specialization", stat = "TOPFIT_BLOCK_CHANCE_ALL", percentPerPoint = 1 },
}

-- Everything below (Hunter through Warlock) sourced 2026-09-26 from a full 8-class data pass Dan
-- provided directly (saved wowforevertalents.com pages, one zip). Same confidence tier as
-- Warrior -- every entry in that source data is explicitly marked client_data-sourced via
-- wago.tools, not footage. No numeric spellID available from any of them -- name match only,
-- same as everywhere else in this file, to be confirmed against live "/topfit talentdebug"
-- output. TOPFIT_HIT_CHANCE_SPELL/TOPFIT_CRIT_CHANCE_SPELL are deliberately generic single
-- "spell" buckets rather than split per school -- see core.lua's comment on those keys.
--
-- Talents seen across all 8 classes but deliberately NOT included, with why (grouped by reason
-- rather than repeated per class):
--   Pet-only stats (Hunter's Ferocity -- pet/hawk crit) -- not the player's own itemization.
--   Derived-from-another-stat scaling (Hunter's Careful Aim, Paladin's Champion of the Light,
--     Priest's Spiritual Guidance, Shaman's Mental Dexterity/Mental Quickness, Warlock's
--     Demonic Knowledge -- all "+X% of your Intellect/Spirit/level") -- different math shape
--     (percent of another stat, not a flat additive percent), doesn't fit this table.
--   Proc/conditional/temporary effects (Hunter's Intimidation, Paladin's Redoubt/Holy Shield/
--     Vindication, Rogue's Remorseless Attacks/Cold Blood/Ghostly Strike, Mage's Wake of Fire/
--     Combustion, Priest's Renewed Hope/Power Infusion/Vampiric Embrace/Early Demise, Shaman's
--     Elemental Devastation/Spirit Weapons/Ancestral Healing) -- not passive/always-on.
--   Form-locked (Druid's Feral Swiftness/Thick Hide/Sharpened Claws/Leader of the Pack/Berserk/
--     Moonkin Form) -- conditional on shapeshift state, which this table doesn't track.
--   Single-specific-spell bonuses, not a general stat (Rogue's Puncturing Wounds/Improved
--     Ambush, Mage's Improved Flamestrike, Shaman's Call of Thunder, Warlock's Agonizing Flames/
--     Fire and Brimstone) -- too narrow to be a general gear-cap-relevant stat.
--   Weapon-type-conditional multi-effect (Rogue's Hack and Slash, same shape as Warrior's
--     Weaponmaster) -- doesn't fit a flat per-rank model.
--   Damage/healing % multipliers, debuffs on enemies, or non-itemization utility (Druid's
--     Genesis/Improved Moonfire/Insect Swarm, Mage's Arcane Instability's damage component,
--     Priest's Spell Warding, Warlock's Suppression's threat-reduction component, Warlock's
--     Demonic Energies) -- different stat category entirely, out of scope for this table.
TopFit.talentRatingBonuses["HUNTER"] = {
	-- Lethal Attacks (Marksmanship): "Increases your critical strike chance with all attacks by
	-- 1%" per rank, 5 ranks. "All attacks" (no spell mention) but Hunter is ranged-primary, so
	-- mapped to the PHYSICAL bucket (melee+ranged, no spell) rather than MELEE alone.
	-- spellID 19426 + exact name "Lethal Attacks" (rank 5) both come from a live Forever
	-- SixtyUpgrades export of Dan's Hunter (2026-09-27) -- the first entry in this file with a
	-- spellID from a real Forever character rather than a scraped page. Not yet checked against
	-- what C_Traits' definitionInfo.spellID actually returns, but the lookup falls back to name
	-- if the spellID doesn't match, so a mismatch is harmless.
	{ name = "Lethal Attacks", spellID = 19426, stat = "TOPFIT_CRIT_CHANCE_PHYSICAL", percentPerPoint = 1 },
	-- Savage Strikes (Survival): "Increases the critical strike chance of all your melee
	-- abilities by 2%" per rank, 2 ranks.
	{ name = "Savage Strikes", stat = "TOPFIT_CRIT_CHANCE_MELEE", percentPerPoint = 2 },
}

TopFit.talentRatingBonuses["PALADIN"] = {
	-- Divine Precision (Holy): "Improves your chance to hit with Holy spells by 6%" per rank,
	-- 3 ranks.
	{ name = "Divine Precision", stat = "TOPFIT_HIT_CHANCE_SPELL", percentPerPoint = 6 },
	-- Holy Power (Holy): "...and all other spells by 1%" per rank, 5 ranks -- only the general
	-- component is modeled; the extra bonus specifically for Holy Shock/Holy Strike (3%/rank) is
	-- too spell-specific to fit here, so this entry understates Holy Power's true value for a
	-- Holy Shock/Strike-heavy rotation. Flagged, not silently ignored.
	{ name = "Holy Power", stat = "TOPFIT_CRIT_CHANCE_SPELL", percentPerPoint = 1 },
	-- Precision (Protection): "Improves your chance to hit by 1%" per rank, 3 ranks -- same
	-- generic talent name/effect as Warrior's and Rogue's own "Precision".
	{ name = "Precision", stat = "TOPFIT_HIT_CHANCE_ALL", percentPerPoint = 1 },
	-- Anticipation (Protection): "Increases your Defense Skill by 4" per rank, 5 ranks -- same
	-- generic talent name/effect as Warrior's own "Anticipation" (a different talent from
	-- Shaman's same-named dodge one -- three classes share this exact name across different
	-- effects, watch for the collision if adding more).
	{ name = "Anticipation", stat = "TOPFIT_DEFENSE_FLAT", percentPerPoint = 4 },
	-- Conviction (Retribution): "Improves your chance to get a critical strike with melee attacks
	-- by 1%" per rank, 5 ranks.
	{ name = "Conviction", stat = "TOPFIT_CRIT_CHANCE_MELEE", percentPerPoint = 1 },
}

TopFit.talentRatingBonuses["ROGUE"] = {
	-- Malice (Assassination): "Increases your critical strike chance with all attacks and
	-- Poisons by 1%" per rank, 5 ranks. Same PHYSICAL-bucket reasoning as Hunter's Lethal
	-- Attacks (no spell mention, and Poisons aren't spells either).
	{ name = "Malice", stat = "TOPFIT_CRIT_CHANCE_PHYSICAL", percentPerPoint = 1 },
	-- Precision (Combat): "Improves your chance to hit by 1%" per rank, 3 ranks.
	{ name = "Precision", stat = "TOPFIT_HIT_CHANCE_ALL", percentPerPoint = 1 },
}

TopFit.talentRatingBonuses["MAGE"] = {
	-- Arcane Focus (Arcane): "Improves your chance to hit with Arcane spells by 1%" per rank,
	-- 5 ranks.
	{ name = "Arcane Focus", stat = "TOPFIT_HIT_CHANCE_SPELL", percentPerPoint = 1 },
	-- Arcane Impact (Arcane): "Increases the critical strike chance of your Arcane spells by 2%"
	-- per rank, 3 ranks.
	{ name = "Arcane Impact", stat = "TOPFIT_CRIT_CHANCE_SPELL", percentPerPoint = 2 },
	-- Arcane Instability (Arcane): "...and your critical strike chance by 1%" per rank, 3 ranks
	-- -- only the crit component is modeled; the accompanying 1%/rank damage-done increase is a
	-- multiplicative damage modifier, a different stat category, not included here.
	{ name = "Arcane Instability", stat = "TOPFIT_CRIT_CHANCE_SPELL", percentPerPoint = 1 },
	-- Critical Mass (Fire): "Increases the critical strike chance of your Fire spells by 2%" per
	-- rank, 3 ranks -- school-general (all Fire spells), not a single named spell.
	{ name = "Critical Mass", stat = "TOPFIT_CRIT_CHANCE_SPELL", percentPerPoint = 2 },
	-- Elemental Precision (Frost): "Improves your chance to hit with Frost and Fire spells by 1%"
	-- per rank, 5 ranks.
	{ name = "Elemental Precision", stat = "TOPFIT_HIT_CHANCE_SPELL", percentPerPoint = 1 },
}

TopFit.talentRatingBonuses["PRIEST"] = {
	-- Holy Precision (Discipline): "Improves your chance to hit with Holy spells by 6%" per
	-- rank, 3 ranks.
	{ name = "Holy Precision", stat = "TOPFIT_HIT_CHANCE_SPELL", percentPerPoint = 6 },
	-- Shadow Focus (Shadow Magic): "Improves your chance to hit with Shadow spells by 1%" per
	-- rank, 5 ranks.
	{ name = "Shadow Focus", stat = "TOPFIT_HIT_CHANCE_SPELL", percentPerPoint = 1 },
}

TopFit.talentRatingBonuses["DRUID"] = {
	-- Nature's Majesty (Balance): "Increases your critical strike chance with spells and melee
	-- attacks by 2%" per rank, 2 ranks -- close enough to the ALL bucket's definition (spells +
	-- physical combined); Druids have no relevant ranged component.
	{ name = "Nature's Majesty", stat = "TOPFIT_CRIT_CHANCE_ALL", percentPerPoint = 2 },
	-- Nature's Reach (Balance): "...improves your chance to hit by 2%" per rank, 2 ranks (also
	-- increases spell range, not itemization-relevant, not modeled here).
	{ name = "Nature's Reach", stat = "TOPFIT_HIT_CHANCE_ALL", percentPerPoint = 2 },
}

TopFit.talentRatingBonuses["WARLOCK"] = {
	-- Suppression (Affliction): "Improves your chance to hit by 1%" per rank, 5 ranks -- generic,
	-- not Shadow/Fire-school-specific despite being in a caster tree (also reduces threat
	-- generated by 4%/rank, not itemization-relevant, not modeled here).
	{ name = "Suppression", stat = "TOPFIT_HIT_CHANCE_ALL", percentPerPoint = 1 },
}

-- All nine classes that exist in WoW: Forever are covered above. Death Knight, Evoker, Demon
-- Hunter, and Monk are NOT playable classes in Forever at all -- confirmed 2026-09-26 (Dan) --
-- so there is nothing to gather or add for them, not just "not yet confirmed." If any of these
-- names show up again in a future data source, treat that source with suspicion rather than
-- assuming Forever's class roster changed.

-- ============================================================================
-- Stat-conversion talents -- "X% of stat A becomes stat B"
-- ============================================================================
-- Different mechanic from TopFit.talentRatingBonuses above: these don't grant a flat amount of
-- a stat, they make one of the character's OWN stats (usually Intellect or Spirit) partly count
-- as a different stat (usually Attack Power, or spell damage/healing) for classes that wouldn't
-- otherwise value it -- e.g. Hunter/Enhancement Shaman converting Intellect into Attack Power.
-- Without this, TopFit would correctly score gear's own AP/spell-damage stats, but silently
-- undervalue Intellect/Spirit on a character with one of these talents taken, since nothing
-- credits the EXTRA value those stats carry once the conversion applies.
--
-- Source: same full class-data pass as the rest of this file (client-data-sourced via
-- wago.tools, 2026-09-27) -- re-extracted specifically to get the exact per-rank progression
-- rather than estimate it, since not all of these scale evenly per rank (see Spiritual Guidance
-- below). Confirm against "/topfit talentdebug" the same as everything else in this file.
--
-- Entry fields:
--   name            talent name, matched the same way as talentRatingBonuses above
--   spellID         optional, same semantics as talentRatingBonuses above (none confirmed yet)
--   fromStat        the stat that partly becomes toStat (e.g. ITEM_MOD_INTELLECT_SHORT)
--   toStat          the stat it becomes (e.g. ITEM_MOD_ATTACK_POWER_SHORT)
--   percentPerRank  percent of fromStat converted, PER RANK -- use when the talent scales evenly
--                    (confirm this is actually true per rank before using it; several of these
--                    LOOK evenly-scaled from rank 1 alone but aren't once every rank is checked)
--   ranks           {[rank] = totalPercent, ...} -- use instead of percentPerRank when the talent
--                    does NOT scale evenly per rank (confirmed by checking every rank's tooltip
--                    text individually, not assumed from the formula implied by rank 1)
--
-- Consumed by TopFit:GetEffectiveWeights (calculation.lua), which resolves these against live
-- talent ranks once per calculation pass and adds the converted value to the source stat's
-- effective weight -- see that function's own comment for how caps interact with this.

TopFit.talentStatConversions = {}

TopFit.talentStatConversions["HUNTER"] = {
	-- Careful Aim (Marksmanship): confirmed evenly-scaled 20%/rank, 5 ranks (20,40,60,80,100%
	-- checked per rank, not assumed from rank 1 alone).
	{ name = "Careful Aim", fromStat = "ITEM_MOD_INTELLECT_SHORT", toStat = "ITEM_MOD_ATTACK_POWER_SHORT", percentPerRank = 20 },
}

TopFit.talentStatConversions["SHAMAN"] = {
	-- Mental Dexterity (Enhancement): displayed per-rank text reads 33%/67%/100% (whole-number
	-- rounding in the tooltip) -- true value is almost certainly 100/3 = 33.33.../rank, used here
	-- rather than the rounded display values so 3 ranks sums to exactly 100%, not 99%.
	{ name = "Mental Dexterity", fromStat = "ITEM_MOD_INTELLECT_SHORT", toStat = "ITEM_MOD_ATTACK_POWER_SHORT", percentPerRank = 100/3 },
	-- Mental Quickness (Enhancement): confirmed evenly-scaled 15%/rank, 2 ranks (15%, 30%),
	-- applies to BOTH spell damage and spell healing simultaneously -- two entries, same source.
	{ name = "Mental Quickness", fromStat = "ITEM_MOD_INTELLECT_SHORT", toStat = "TOPFIT_SPELL_DAMAGE_FLAT", percentPerRank = 15 },
	{ name = "Mental Quickness", fromStat = "ITEM_MOD_INTELLECT_SHORT", toStat = "TOPFIT_SPELL_HEALING_FLAT", percentPerRank = 15 },
}

TopFit.talentStatConversions["PALADIN"] = {
	-- Champion of the Light (Retribution): same 33/66/100% rounded-display pattern as Mental
	-- Dexterity above -- true value 100/3 per rank. Applies to both spell damage and healing.
	{ name = "Champion of the Light", fromStat = "ITEM_MOD_INTELLECT_SHORT", toStat = "TOPFIT_SPELL_DAMAGE_FLAT", percentPerRank = 100/3 },
	{ name = "Champion of the Light", fromStat = "ITEM_MOD_INTELLECT_SHORT", toStat = "TOPFIT_SPELL_HEALING_FLAT", percentPerRank = 100/3 },
}

TopFit.talentStatConversions["PRIEST"] = {
	-- Spiritual Guidance (Holy), healing component: confirmed evenly-scaled 5%/rank, 5 ranks
	-- (5,10,15,20,25% checked per rank).
	{ name = "Spiritual Guidance", fromStat = "ITEM_MOD_SPIRIT_SHORT", toStat = "TOPFIT_SPELL_HEALING_FLAT", percentPerRank = 5 },
	-- Spiritual Guidance, damage component: NOT evenly scaled -- checked every rank individually
	-- (1%, 3%, 5%, 6%, 8%), a genuinely non-uniform progression, not a rounding artifact like
	-- Mental Dexterity/Champion of the Light above. Using percentPerRank here would be wrong at
	-- every rank except rank 5 (1x5=5, not 1; nor does any single multiplier produce 1,3,5,6,8).
	{ name = "Spiritual Guidance", fromStat = "ITEM_MOD_SPIRIT_SHORT", toStat = "TOPFIT_SPELL_DAMAGE_FLAT",
	  ranks = { [1] = 1, [2] = 3, [3] = 5, [4] = 6, [5] = 8 } },
}

-- Mage's Arcane Resilience (Intellect -> Armor, 25%/rank at rank 2 max per the same data pass)
-- and Priest's Mental Strength (straight +3%/rank TOTAL Intellect, not a cross-stat conversion)
-- were both found during this same pass but deliberately NOT added: Arcane Resilience converts
-- into Armor, which none of this addon's scoring treats as an EP-relevant stat the way AP/spell
-- damage are (armor matters for mitigation, not DPS/HPS throughput, and isn't itemized as a
-- primary stat casters weight); Mental Strength is a different mechanic entirely (a stat
-- multiplying ITSELF, not converting into a different one) and doesn't fit this table's
-- fromStat/toStat shape at all. Noted here so neither gets "rediscovered" and force-fit in later
-- without this context.
