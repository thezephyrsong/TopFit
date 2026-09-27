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

-- Source: wowforevertalents.com Shaman page scrape (fan-built from BlizzCon 2026 footage,
-- marked provisional there) -- NOT yet cross-checked against a live character's
-- "/topfit talentdebug" output. spellID intentionally omitted: the scrape didn't capture one,
-- and a fabricated number would be worse than leaving it out -- a wrong spellID would silently
-- never match, where a missing one just falls through to the name match, which is confirmed as
-- far as the source goes. Fill in spellID once confirmed live, and flip this comment once the
-- name match itself has been confirmed too.
TopFit.talentRatingBonuses["SHAMAN"] = {
	-- Thundering Strikes (Enhancement): "Improves your chance to get a critical strike with all
	-- spells and attacks by 1%" per rank, 5 ranks.
	{ name = "Thundering Strikes", stat = "TOPFIT_CRIT_CHANCE_ALL", percentPerPoint = 1 },
	-- Tidal Focus (Restoration): "...increases your chance to hit with all spells and attacks by
	-- 1%" per rank, 5 ranks.
	{ name = "Tidal Focus", stat = "TOPFIT_HIT_CHANCE_ALL", percentPerPoint = 1 },
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

-- Every other class (Rogue, Priest, Mage, Warlock, Hunter, Paladin, Druid, Death Knight, and
-- Evoker/Demon Hunter/Monk if present): no confirmed Forever talent data yet. Do NOT port the
-- old WotLK/Triumvirate entries over even as a rough starting guess -- Forever's talents are a
-- real redesign, not a renumbering (e.g. Shaman's own Stormstrike and Flurry came back
-- completely reworked, not just moved -- see REWRITE_PLAN_12_1_5.md), so a WotLK-based guess
-- isn't an approximation, it's just wrong. Populate the same way Shaman/Warrior were: get the
-- class's wowforevertalents.com page (client-data-sourced pages, like Warrior's, are higher
-- confidence than footage-sourced ones, like Shaman's -- check each page's own sourcing), then
-- cross-check with "/topfit talentdebug" on a real character with the relevant talents taken,
-- using the format above.
