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

-- ============================================================================================
-- The classes below use STANDARD RETAIL TAB ORDERING as their tab-number label (e.g. Mage
-- Arcane=1/Fire=2/Frost=3), which is NOT the same thing as this data file's own internal
-- declaration order -- those two disagree for at least one class already confirmed in-code
-- (Warrior's own data lists tabs as [arms, protection, fury], but calculation.lua's existing,
-- game-confirmed GetTalentInfo(2, 27) Titan's Grip check proves tab 2 is actually Fury, not
-- Protection). Standard retail ordering is what's used throughout, since it's consistent with
-- the two tabs that ARE confirmed in-code (Shaman Enhancement=2, Warrior Fury=2) -- but for every
-- class below, NEITHER the tab number NOR the index has an independent in-code confirmation the
-- way those two do. Verify before trusting, same as everywhere else in this file.
--
-- A couple of these talents grant "hitPercent" without specifying melee/spell/ranged in
-- Triumvirate's own data (unlike Virulence or Precision, which say so explicitly) -- in those
-- cases the type below was inferred from what the class/spec actually uses (e.g. a pure caster's
-- hit talent is spell, a pure melee class's is melee). Hunter's Focused Aim is a special case:
-- it's ranged hit, and Triumvirate's stat-scaling data doesn't give a separate ranged-hit
-- conversion constant, only melee and spell -- retail WotLK uses the same conversion for ranged
-- and melee hit rating, so melee's constant is used here, but this hasn't been separately
-- confirmed for Triumvirate.
TopFit.talentRatingBonuses["DRUID"] = {
    -- Balance of Power (tab 1 "Balance", spellId 33592): +3% spell hit/rank, 2 ranks.
    { tab = 1, index = 17, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 3, percentType = "spell" },
}

TopFit.talentRatingBonuses["HUNTER"] = {
    -- Focused Aim (tab 2 "Marksmanship", spellId 53620): +1% ranged hit/rank, 3 ranks.
    -- Uses the melee hit conversion (see note above) since Triumvirate doesn't expose a
    -- separate ranged conversion constant.
    { tab = 2, index = 2, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "melee" },
    -- Master Marksman (tab 2 "Marksmanship", spellId 34485): +1% crit/rank, 5 ranks.
    { tab = 2, index = 21, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
    -- Killer Instinct (tab 3 "Survival", spellId 19370): +1% crit/rank, 3 ranks.
    { tab = 3, index = 15, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
    -- Master Tactician (tab 3 "Survival", spellId 34506): +2% crit/rank, 5 ranks.
    { tab = 3, index = 22, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 28 },
}

TopFit.talentRatingBonuses["MAGE"] = {
    -- Arcane Focus (tab 1 "Arcane", spellId 11222): +1% spell hit/rank, 3 ranks.
    { tab = 1, index = 2, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "spell" },
    -- Pyromaniac (tab 2 "Fire", spellId 34293): +1% crit/rank, 3 ranks.
    { tab = 2, index = 19, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
    -- Precision (tab 3 "Frost", spellId 29438): +1% spell hit/rank, 3 ranks.
    { tab = 3, index = 6, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "spell" },
}

TopFit.talentRatingBonuses["PALADIN"] = {
    -- Enlightened Judgements (tab 1 "Holy", spellId 53556): +2% hit/rank, 2 ranks. Judgement is a
    -- spell-type ability in retail's hit-chance model, so this uses the spell hit conversion.
    { tab = 1, index = 25, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 2, percentType = "spell" },
    -- Conviction (tab 3 "Retribution", spellId 20117): +1% crit/rank, 5 ranks.
    { tab = 3, index = 7, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
}

TopFit.talentRatingBonuses["PRIEST"] = {
    -- Shadow Focus (tab 3 "Shadow", spellId 15260): +1% spell hit/rank, 3 ranks.
    { tab = 3, index = 6, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "spell" },
}

TopFit.talentRatingBonuses["ROGUE"] = {
    -- Malice (tab 1 "Assassination", spellId 14138): +1% crit/rank, 5 ranks.
    { tab = 1, index = 3, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
    -- Precision (tab 2 "Combat", spellId 13705): +1% hit/rank, 5 ranks. Rogue is a pure melee
    -- class, so this uses the melee hit conversion.
    { tab = 2, index = 6, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "melee" },
}

TopFit.talentRatingBonuses["WARLOCK"] = {
    -- Suppression (tab 1 "Affliction", spellId 18174): +1% spell hit/rank, 3 ranks.
    { tab = 1, index = 2, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "spell" },
    -- Demonic Tactics (tab 2 "Demonology", spellId 30242): +2% crit/rank, 5 ranks.
    { tab = 2, index = 21, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 28 },
}

TopFit.talentRatingBonuses["WARRIOR"] = {
    -- Cruelty (tab 2 "Fury", spellId 12320): +1% crit/rank, 5 ranks.
    { tab = 2, index = 3, stat = "ITEM_MOD_CRIT_RATING_SHORT", perPoint = 14 },
    -- Precision (tab 2 "Fury", spellId 29590): +1% MELEE hit/rank (explicit in Triumvirate's
    -- data), 3 ranks.
    { tab = 2, index = 13, stat = "ITEM_MOD_HIT_RATING_SHORT", percentPerPoint = 1, percentType = "melee" },
}
