-- Talent-granted rating bonuses.
--
-- TopFit's caps only ever look at gear (see calculation.lua). Ratings a talent grants directly
-- (flat rating, or a percentage that converts to rating) never show up on an item tooltip, so
-- without this table TopFit has no way to know about them and will keep asking for more
-- gear-based rating than you actually need once you've taken the talent.
--
-- This table is read once per calculation (see TopFit:GetTalentRatingBonuses in calculation.lua)
-- using the same GetTalentInfo() calls simc_export.lua already uses to build the talent string --
-- it just also reads the current rank of whichever talents are listed here and adds their rating
-- to the running total before caps are checked.
--
-- IMPORTANT: Triumvirate uses custom 71-point compressed talent trees, not the retail WotLK
-- layout, so the (tab, index) pairs below are NOT filled in -- they have to match Triumvirate's
-- actual tree positions, which only Dan can confirm (same rule as everywhere else: authoritative
-- source is Triumvirate's own talent calculator / SpellData, not retail Wowhead). Nothing in this
-- table takes effect until real entries are added; an empty/missing class entry is a no-op.
--
-- Entry fields:
--   tab             talent tab index (1, 2, or 3), as passed to GetTalentInfo()
--   index           talent index within that tab, as passed to GetTalentInfo()
--   stat            the ITEM_MOD_* token to credit (see core.lua's statList for valid tokens --
--                   e.g. ITEM_MOD_HIT_RATING_SHORT, ITEM_MOD_EXPERTISE_RATING_SHORT,
--                   ITEM_MOD_CRIT_RATING_SHORT, ITEM_MOD_HASTE_RATING_SHORT)
--   perPoint        rating granted per talent point, for talents whose tooltip states a flat
--                   rating bonus (e.g. "+7 Expertise Rating per point")
--   percentPerPoint percentage granted per talent point, for talents whose tooltip states a
--                   percentage instead (e.g. "+1% Hit Chance per point"). Mutually exclusive
--                   with perPoint -- use one or the other per entry, not both.
--   percentType     required when percentPerPoint is used: "melee" or "spell". Melee and spell
--                   hit convert to rating at different rates at level 60 (10 rating/1% melee,
--                   8 rating/1% spell -- see presets.lua), so this picks the right constant.
--
-- Example (left commented out -- confirm the real tab/index on Triumvirate's talent calculator
-- before enabling anything here):
-- TopFit.talentRatingBonuses = {
--     ["SHAMAN"] = {
--         -- e.g. a talent granting +2 Expertise Rating per point, 3 points, tab 2 index 5:
--         -- { tab = 2, index = 5, stat = "ITEM_MOD_EXPERTISE_RATING_SHORT", perPoint = 2 },
--         -- e.g. a talent granting +1% melee Hit per point, tab 2 index 9:
--         -- { tab = 2, index = 9, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "melee" },
--     },
-- }

TopFit.talentRatingBonuses = TopFit.talentRatingBonuses or {}

-- Populated from Triumvirate's own talent-calculator data (source: "triumvirate-dbc"), which lists
-- each talent's spell ID and grid (row, column) position per tab. The (tab, index) values below were
-- derived by numbering each tab's non-empty grid cells in row-major order (top-to-bottom,
-- left-to-right), which is how the WoW 3.3.5a client assigns GetTalentInfo() indices -- but that
-- derivation itself hasn't been checked against a live client. Verify one entry in-game (e.g.
-- /topfit talentdebug once available, or a manual GetTalentInfo(2, 19) print) before trusting this
-- for anything you're relying on.
--
-- Shaman tab order confirmed against the existing dual-wield detection in calculation.lua
-- (GetTalentInfo(2, 20) there): 1 = Elemental, 2 = Enhancement, 3 = Restoration.
TopFit.talentRatingBonuses["SHAMAN"] = {
    -- Unleashed Rage (tab 2 "Enhancement", spellId 30802): grants flat Expertise skill points
    -- (3/6/9 per rank on Triumvirate -- a custom redesign, not the retail AP-buff version).
    -- 3 skill points/rank * 2.5 rating/skill point (EXPERTISE_RATING_TO_SKILL) = 7.5 rating/rank.
    { tab = 2, index = 16, stat = "ITEM_MOD_EXPERTISE_RATING_SHORT", perPoint = 7.5 },
    -- Dual Wield Specialization (tab 2 "Enhancement", spellId 30816): grants +3%/rank to BOTH melee
    -- and spell hit on Triumvirate. Only the melee component is included here, since TopFit's
    -- Enhancement Hit Rating cap is built from meleeCap (melee/dual-wield hit) -- adding the spell
    -- component too would double-credit rating that doesn't actually reduce the melee hit
    -- requirement this cap represents.
    { tab = 2, index = 19, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 3, percentType = "melee" },
}

-- Death Knight tab order: 1 = Blood, 2 = Frost, 3 = Unholy (standard WotLK ordering; unlike Shaman's
-- dual-wield tab this hasn't been cross-checked against another in-code GetTalentInfo call, so treat
-- the tab numbers here with the same "verify before trusting" caveat as the indices).
--
-- Rating amounts use Triumvirate's confirmed level-60 conversions (crit: 14 rating/1%, per the
-- realm's own DBC data; Armor Penetration: ~4.268 rating/1%, confirmed empirically in-game this
-- session across two different characters/classes -- see conversation history -- since the
-- datamined ArP constant turned out to be wrong even though it checked out for every other stat).
TopFit.talentRatingBonuses["DEATHKNIGHT"] = {
    -- Dark Conviction (tab 1 "Blood", spellId 48987): +1% crit/rank, 5 ranks.
    -- 1% * 14 rating/1% = 14 rating/rank.
    { tab = 1, index = 8, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
    -- Blood Gorged (tab 1 "Blood", spellId 61154): +2% Armor Penetration/rank, 5 ranks.
    -- 2% * 4.268 rating/1% = 8.536 rating/rank.
    { tab = 1, index = 27, stat = "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", perPoint = 8.536 },
    -- Improved Icy Talons (tab 2 "Frost", spellId 55610): single-rank talent, flat +5% haste.
    -- 5% * 10 rating/1% = 50 rating (rank is always 0 or 1 here, so perPoint doubles as the total).
    { tab = 2, index = 16, stat = "ITEM_MOD_HASTE_RATING_SHORT", perPoint = 50 },
    -- Virulence (tab 3 "Unholy", spellId 48962): +2% SPELL hit/rank, 3 ranks.
    { tab = 3, index = 2, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 2, percentType = "spell" },
    -- Ebon Plaguebringer (tab 3 "Unholy", spellId 51099): +1% crit/rank, 3 ranks.
    { tab = 3, index = 28, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
}
