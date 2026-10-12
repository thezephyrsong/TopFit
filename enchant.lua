-- ============================================================================
-- Enchants as a per-slot layer on top of the chosen items (added 2026-10-11)
--
-- Items are scored WITHOUT the enchant they currently carry (TopFit.SCORE_ENCHANTS = false in
-- core.lua), because any enchant can be put on whichever item ends up worn. This file adds that
-- choice back as its own layer: for each enchant GROUP (Weapon, 2H Weapon, Shield, Off-Hand, Chest,
-- Cloak, Bracer, Gloves, Boots, Necklace) a set either pins one enchant, pins "none", or is on
-- "auto" = the enchant with the highest weighted score for that set. The chosen enchant's stats are
-- added to the combination's totals (score and cap stats) in calculation.lua.
--
-- Data: enchant_data.lua. Everything about which entries are scored is decided in
-- ParseEnchantText below; anything it cannot turn into stats TopFit already scores is left
-- UNSCORED on purpose and says why, rather than being guessed at.
-- ============================================================================

TopFit.EnchantGroups = { "Weapon", "2H Weapon", "Shield", "Off-Hand", "Chest", "Cloak", "Bracer", "Gloves", "Boots", "Necklace" }

local SCHOOL_RESISTANCE = {
    Holy = "RESISTANCE1_NAME", Fire = "RESISTANCE2_NAME", Nature = "RESISTANCE3_NAME",
    Frost = "RESISTANCE4_NAME", Shadow = "RESISTANCE5_NAME", Arcane = "RESISTANCE6_NAME",
}
local SCHOOL_DAMAGE = {
    Holy = "TOPFIT_HOLY_DAMAGE_FLAT", Fire = "TOPFIT_FIRE_DAMAGE_FLAT", Nature = "TOPFIT_NATURE_DAMAGE_FLAT",
    Frost = "TOPFIT_FROST_DAMAGE_FLAT", Shadow = "TOPFIT_SHADOW_DAMAGE_FLAT", Arcane = "TOPFIT_ARCANE_DAMAGE_FLAT",
}
local PRIMARY = {
    Strength = "ITEM_MOD_STRENGTH_SHORT", Agility = "ITEM_MOD_AGILITY_SHORT", Stamina = "ITEM_MOD_STAMINA_SHORT",
    Intellect = "ITEM_MOD_INTELLECT_SHORT", Spirit = "ITEM_MOD_SPIRIT_SHORT",
}

-- Turns an enchant's effect line into { statKey = amount } plus, when nothing is scorable, the
-- reason. Handles the shapes seen in Forever's 165 enchants ("Stamina +2", "+9 Agility", "All
-- Stats +3", "Healing Spells +16, Damage Spells +6", "Healing Spells +35/Damage Spells +12",
-- "Spell Power +30", "+6 Spell Power", "Frost Spell Damage +15", "Arcane Damage +20", "Armor +30",
-- "Defense +5", "+10 Fire Resistance", "+2 All Resistances", "Blocking +2%", "Dodge +1%",
-- "Haste +1%", "Mana Regen 4 per 5 sec.").
function TopFit:ParseEnchantText(text)
    local stats = {}
    local function add(key, value)
        value = tonumber(value)
        if key and value and value > 0 then stats[key] = (stats[key] or 0) + value end
    end

    local allStats = text:match("All Stats %+(%d+)") or text:match("%+(%d+) All Stats")
    if allStats then
        for _, key in pairs(PRIMARY) do add(key, allStats) end
    end
    for name, key in pairs(PRIMARY) do
        add(key, text:match(name .. " %+(%d+)") or text:match("%+(%d+) " .. name))
    end

    add("RESISTANCE0_NAME", text:match("Armor %+(%d+)") or text:match("%+(%d+) Armor"))
    add("TOPFIT_DEFENSE_FLAT", text:match("Defense %+(%d+)") or text:match("%+(%d+) Defense"))

    local allRes = text:match("%+(%d+) All Resistances")
    if allRes then
        for _, key in pairs(SCHOOL_RESISTANCE) do add(key, allRes) end
    end
    for school, key in pairs(SCHOOL_RESISTANCE) do
        add(key, text:match("%+(%d+) " .. school .. " Resistance"))
    end

    add("TOPFIT_BLOCK_CHANCE_ALL", text:match("Blocking %+(%d+)%%"))
    add("TOPFIT_DODGE_CHANCE_ALL", text:match("Dodge %+(%d+)%%"))
    add("TOPFIT_HASTE_PERCENT", text:match("Haste %+(%d+)%%"))
    add("ITEM_MOD_MANA_REGENERATION_SHORT", text:match("Mana Regen (%d+) per 5 sec"))

    -- spell damage / healing. "Spell Power" is one number credited to both, exactly like the
    -- combined "increases damage and healing done by magical spells..." item line (procparser.lua).
    local spellPower = text:match("Spell Power %+(%d+)") or text:match("%+(%d+) Spell Power")
    add("TOPFIT_SPELL_DAMAGE_FLAT", spellPower)
    add("TOPFIT_SPELL_HEALING_FLAT", spellPower)
    add("TOPFIT_SPELL_HEALING_FLAT", text:match("Healing Spells %+(%d+)"))
    add("TOPFIT_SPELL_DAMAGE_FLAT", text:match("Damage Spells %+(%d+)"))
    for school, key in pairs(SCHOOL_DAMAGE) do
        add(key, text:match(school .. " Spell Damage %+(%d+)") or text:match(school .. " Damage %+(%d+)"))
    end

    if next(stats) then return stats end

    -- nothing scorable: say why, so the tab can show it instead of silently valuing it at 0
    local reason
    if text:find("Weapon Damage %+") then
        reason = "flat weapon damage depends on weapon speed; not scored yet"
    elseif text:find("chance") or text:find("Often") or text:find("Trigger") then
        reason = "proc effect; not scored"
    elseif text:find("Fishing") or text:find("Herbalism") or text:find("Mining") or text:find("Skinning")
        or text:find("Riding") or text:find("movement") or text:find("stealth") or text:find("Death Lotus") then
        reason = "profession/utility effect; no combat stats"
    elseif text:find("Threat") or text:find("threat") then
        reason = "threat modifier; not scored"
    elseif text:find("Beastslaying") or text:find("Elemental Slayer") or text:find("demons") then
        reason = "bonus against one creature type; not scored"
    else
        reason = "no stat TopFit scores"
    end
    return stats, reason
end

-- ---------------------------------------------------------------------------
-- Index and parsing of the data table (done once, lazily)
-- ---------------------------------------------------------------------------
local function BuildEnchantIndex()
    if TopFit.EnchantIndex then return end
    TopFit.EnchantIndex = {}
    TopFit.EnchantsByGroup = {}
    for _, group in ipairs(TopFit.EnchantGroups) do TopFit.EnchantsByGroup[group] = {} end
    for _, row in ipairs(TopFit.EnchantData or {}) do
        local entry = { group = row[1], name = row[2], text = row[3] }
        entry.stats, entry.unscoredReason = TopFit:ParseEnchantText(entry.text)
        TopFit.EnchantIndex[entry.group .. "|" .. entry.name] = entry
        if TopFit.EnchantsByGroup[entry.group] then
            tinsert(TopFit.EnchantsByGroup[entry.group], entry)
        end
    end
end

function TopFit:GetEnchantEntry(group, name)
    BuildEnchantIndex()
    return TopFit.EnchantIndex[group .. "|" .. name]
end

function TopFit:GetEnchantsForGroup(group)
    BuildEnchantIndex()
    return TopFit.EnchantsByGroup[group] or {}
end

-- ---------------------------------------------------------------------------
-- Slot / item -> group
-- ---------------------------------------------------------------------------
local FIXED_SLOT_GROUP = { [2] = "Necklace", [5] = "Chest", [8] = "Boots", [9] = "Bracer", [10] = "Gloves", [15] = "Cloak" }

function TopFit:GetEnchantGroup(slotID, itemTable)
    if FIXED_SLOT_GROUP[slotID] then return FIXED_SLOT_GROUP[slotID] end
    local loc = itemTable and itemTable.itemEquipLoc
    if slotID == 16 then
        return (loc == "INVTYPE_2HWEAPON") and "2H Weapon" or "Weapon"
    elseif slotID == 17 then
        if loc == "INVTYPE_SHIELD" then return "Shield" end
        if loc == "INVTYPE_HOLDABLE" then return "Off-Hand" end
        if loc and loc:find("WEAPON") then return "Weapon" end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Choosing and scoring
-- ---------------------------------------------------------------------------
TopFit.enchantChoiceCache = TopFit.enchantChoiceCache or {}
function TopFit:ClearEnchantCache()
    TopFit.enchantChoiceCache = {}
end

function TopFit:ScoreEnchantEntry(entry, weights)
    local score = 0
    for stat, value in pairs(entry.stats) do
        score = score + (weights[stat] or 0) * value
    end
    return score
end

-- The highest-scoring enchant in a group for this set's (effective) weights, or nil if none scores > 0.
function TopFit:GetBestEnchant(group, setTable)
    local weights = TopFit:GetEffectiveWeights(setTable.weights or {}, setTable)
    local best, bestScore
    for _, entry in ipairs(TopFit:GetEnchantsForGroup(group)) do
        if next(entry.stats) then
            local score = TopFit:ScoreEnchantEntry(entry, weights)
            if score > 0 and (not bestScore or score > bestScore) then
                best, bestScore = entry, score
            end
        end
    end
    return best, bestScore
end

-- What a set will use for a group: its pinned enchant, nothing (pinned "none" or enchants switched
-- off), or the auto pick. A pinned name that no longer exists falls back to auto.
function TopFit:GetChosenEnchant(setCode, group)
    local setTable = setCode and TopFit.db and TopFit.db.profile.sets[setCode]
    if not setTable or setTable.skipEnchants then return nil end
    local cacheKey = setCode .. "|" .. group
    local cached = TopFit.enchantChoiceCache[cacheKey]
    if cached ~= nil then return cached or nil end

    local choice
    local pin = setTable.enchants and setTable.enchants[group]
    if pin == "none" then
        choice = nil
    else
        choice = pin and TopFit:GetEnchantEntry(group, pin)
        if not choice then choice = TopFit:GetBestEnchant(group, setTable) end
    end
    TopFit.enchantChoiceCache[cacheKey] = choice or false
    return choice
end

-- { entry, stats, score } for the enchant that would go on this item in this slot, or nil.
function TopFit:GetEnchantForItem(setCode, slotID, itemTable)
    local group = TopFit:GetEnchantGroup(slotID, itemTable)
    if not group then return nil end
    local entry = TopFit:GetChosenEnchant(setCode, group)
    if not entry or not next(entry.stats) then return nil end
    local setTable = TopFit.db.profile.sets[setCode]
    local weights = TopFit:GetEffectiveWeights(setTable.weights or {}, setTable)
    return { entry = entry, stats = entry.stats, score = TopFit:ScoreEnchantEntry(entry, weights) }
end

function TopFit:GetEnchantStatValue(slotID, itemTable, stat)
    if not TopFit.setCode or not itemTable then return 0 end
    local e = TopFit:GetEnchantForItem(TopFit.setCode, slotID, itemTable)
    return e and e.stats[stat] or 0
end
