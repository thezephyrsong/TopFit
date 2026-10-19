-- ============================================================================
-- Enchants as a per-slot layer on top of the chosen items
--
-- Items are scored WITHOUT the enchant they currently carry (TopFit.SCORE_ENCHANTS = false in
-- core.lua), because any enchant can be put on whichever item ends up worn. This file adds that
-- choice back as its own layer: for each enchant GROUP (Head, Shoulder, Chest, ... Ranged) a set
-- either pins one enchant, pins "none", or is on "auto" = the enchant with the highest weighted
-- score for that set. The chosen enchant's stats are added to the combination's totals (score and
-- cap stats) in calculation.lua.
--
-- "Enchant" here means anything that goes in an item's single permanent-enchant slot, so a group's
-- menu holds Enchanting enchants AND the crafted ones that compete with them for that slot:
-- Leatherworking armor kits, Engineering scopes, Blacksmithing shield spikes and counterweights,
-- Arcanums and the Zandalar class enchants (head and legs), and shoulder inscriptions. Choosing one
-- per group is what stops a kit and an enchant being stacked on the same item.
--
-- Data: enchant_data.lua (client enchant records: stat arrays, "pseudo" stats, flat weapon damage,
-- slot types). This file decides how those become TopFit stats; whatever it cannot turn into a stat
-- TopFit scores stays UNSCORED on purpose and says why, rather than being guessed at.
-- ============================================================================

TopFit.EnchantGroups = { "Head", "Shoulder", "Necklace", "Chest", "Cloak", "Bracer", "Gloves", "Legs", "Boots",
                         "Weapon", "2H Weapon", "Shield", "Off-Hand", "Ranged" }

-- Index -> TopFit stat for the client's `stats` array (0-based). Confirmed against rows whose
-- in-game values are known (Healing Power enchants, Arcane/Fire/Frost/Holy/Nature/Shadow Power gloves,
-- Falcon's Call, Presence of Might, Rugged Armor Kit, Deflection...).
local STAT_INDEX_MAP = {
    [0]  = "ITEM_MOD_STRENGTH_SHORT",
    [1]  = "ITEM_MOD_AGILITY_SHORT",
    [2]  = "ITEM_MOD_STAMINA_SHORT",
    [3]  = "ITEM_MOD_INTELLECT_SHORT",
    [4]  = "TOPFIT_SPELL_HEALING_FLAT",   -- Healing Power enchants: 4 = healing, 5 = damage ("+24 healing, +8 damage");
    [5]  = "TOPFIT_SPELL_DAMAGE_FLAT",    --   a plain "Spell Power" fills both
    [6]  = "TOPFIT_ARCANE_DAMAGE_FLAT",
    [7]  = "TOPFIT_FIRE_DAMAGE_FLAT",
    [8]  = "TOPFIT_FROST_DAMAGE_FLAT",
    [9]  = "TOPFIT_HOLY_DAMAGE_FLAT",
    [10] = "TOPFIT_NATURE_DAMAGE_FLAT",
    [11] = "TOPFIT_SHADOW_DAMAGE_FLAT",
    [16] = "ITEM_MOD_SPIRIT_SHORT",
    [17] = "ITEM_MOD_ATTACK_POWER_SHORT",
    [18] = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    [25] = "TOPFIT_DEFENSE_FLAT",
    [27] = "ITEM_MOD_BLOCK_VALUE_SHORT",
    [31] = "RESISTANCE0_NAME",            -- armor
    [34] = "ITEM_MOD_MANA_REGENERATION_SHORT",
    [35] = "RESISTANCE6_NAME",            -- arcane
    [36] = "RESISTANCE2_NAME",            -- fire
    [37] = "RESISTANCE3_NAME",            -- nature
    [38] = "RESISTANCE4_NAME",            -- frost
    [39] = "RESISTANCE5_NAME",            -- shadow
}
-- Indices seen in the data that TopFit has no stat for: 30, 32, 33 (health / mana / similar pools).
-- Index 34 is mana regeneration per 5 sec, but the Lesser Arcanums also put a 100-150 MANA POOL
-- there, so a value that large is ignored as "not MP5".
local MAX_PLAUSIBLE_MP5 = 49

-- "Pseudo" stats (percent effects), indices inferred from rows with known effects: 4 dodge (Arcanum of
-- Protection, Cloak - Dodge), 12 melee hit / 13 spell hit / 24 ranged hit (Falcon's Call, Presence of
-- Sight, Biznicks scope), 14 melee crit / 15 spell crit / 25 ranged crit (Might / Power of the Scourge,
-- SAF-T scope), 16 block (Lesser Block), 20 melee / 21 ranged / 22 cast haste (Minor Haste, Arcanum of
-- Rapidity, Counterweight). These indices are INFERRED from those rows, not read from a definition.
-- TopFit has one key per concept, so melee+ranged hit/crit collapse to the generic key (max, not sum).
local function PseudoToStats(pseudo, add)
    if not pseudo then return end
    local function p(i) return pseudo[i + 1] or 0 end
    add("TOPFIT_DODGE_CHANCE_ALL", p(4))
    add("TOPFIT_BLOCK_CHANCE_ALL", p(16))
    add("TOPFIT_HIT_CHANCE_ALL", math.max(p(12), p(24)))
    add("TOPFIT_HIT_CHANCE_SPELL", p(13))
    add("TOPFIT_CRIT_CHANCE_ALL", math.max(p(14), p(25)))
    add("TOPFIT_CRIT_CHANCE_SPELL", p(15))
    add("TOPFIT_HASTE_PERCENT", math.max(p(20), p(21), p(22)))
end
local KNOWN_PSEUDO = { [4] = true, [12] = true, [13] = true, [14] = true, [15] = true, [16] = true,
                       [20] = true, [21] = true, [22] = true, [24] = true, [25] = true }

local TYPE_TO_GROUP = {
    [1] = "Head", [2] = "Necklace", [3] = "Shoulder", [4] = "Cloak", [5] = "Chest", [6] = "Bracer",
    [7] = "Gloves", [9] = "Legs", [10] = "Boots", [14] = "Ranged",
}
-- "Enchant <Group> - <Name>" rows name their own group; that is more reliable than the type field
-- (some Cloak/Weapon rows carry the weapon type).
local PREFIX_TO_GROUP = {
    ["Chest"] = "Chest", ["Bracer"] = "Bracer", ["Cloak"] = "Cloak", ["Gloves"] = "Gloves", ["Boots"] = "Boots",
    ["Shield"] = "Shield", ["Weapon"] = "Weapon", ["2H Weapon"] = "2H Weapon", ["Off-Hand"] = "Off-Hand",
    ["Off Hand"] = "Off-Hand", ["Necklace"] = "Necklace",
}
local function GroupForRow(row)
    local prefix = row.name:match("^Enchant (.-) %- ")
    if prefix and PREFIX_TO_GROUP[prefix] then return PREFIX_TO_GROUP[prefix] end
    if row.type == 13 then
        if row.enchantType == 1 then return "2H Weapon" end
        if row.enchantType == 2 then return "Shield" end
        if row.enchantType == 5 then return "Off-Hand" end
        return "Weapon"
    end
    return TYPE_TO_GROUP[row.type]
end

-- Zandalar class enchants: usable by one class only.
local CLASS_RESTRICTIONS = {
    ["Presence of Might"] = "WARRIOR",
    ["Syncretist's Sigil"] = "PALADIN",
    ["Death's Embrace"] = "ROGUE",
    ["Falcon's Call"] = "HUNTER",
    ["Vodouisant's Vigilant Embrace"] = "WARLOCK",
    ["Presence of Sight"] = "MAGE",
    ["Hoodoo Hex"] = "SHAMAN",
    ["Prophetic Aura"] = "PRIEST",
    ["Animist's Caress"] = "DRUID",
}

-- readable labels for the keys this file produces (used to build entry.text)
local LABELS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility", ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect", ITEM_MOD_SPIRIT_SHORT = "Spirit",
    TOPFIT_SPELL_HEALING_FLAT = "Healing", TOPFIT_SPELL_DAMAGE_FLAT = "Spell Damage",
    TOPFIT_ARCANE_DAMAGE_FLAT = "Arcane Damage", TOPFIT_FIRE_DAMAGE_FLAT = "Fire Damage",
    TOPFIT_FROST_DAMAGE_FLAT = "Frost Damage", TOPFIT_HOLY_DAMAGE_FLAT = "Holy Damage",
    TOPFIT_NATURE_DAMAGE_FLAT = "Nature Damage", TOPFIT_SHADOW_DAMAGE_FLAT = "Shadow Damage",
    ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "Ranged AP",
    TOPFIT_DEFENSE_FLAT = "Defense", ITEM_MOD_BLOCK_VALUE_SHORT = "Block Value", RESISTANCE0_NAME = "Armor",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    RESISTANCE6_NAME = "Arcane Res", RESISTANCE2_NAME = "Fire Res", RESISTANCE3_NAME = "Nature Res",
    RESISTANCE4_NAME = "Frost Res", RESISTANCE5_NAME = "Shadow Res",
    TOPFIT_DODGE_CHANCE_ALL = "% Dodge", TOPFIT_BLOCK_CHANCE_ALL = "% Block", TOPFIT_HIT_CHANCE_ALL = "% Hit",
    TOPFIT_HIT_CHANCE_SPELL = "% Spell Hit", TOPFIT_CRIT_CHANCE_ALL = "% Crit", TOPFIT_CRIT_CHANCE_SPELL = "% Spell Crit",
    TOPFIT_HASTE_PERCENT = "% Haste",
}
local LABEL_ORDER = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT",
    "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "TOPFIT_SPELL_HEALING_FLAT",
    "TOPFIT_SPELL_DAMAGE_FLAT", "TOPFIT_ARCANE_DAMAGE_FLAT", "TOPFIT_FIRE_DAMAGE_FLAT", "TOPFIT_FROST_DAMAGE_FLAT",
    "TOPFIT_HOLY_DAMAGE_FLAT", "TOPFIT_NATURE_DAMAGE_FLAT", "TOPFIT_SHADOW_DAMAGE_FLAT", "TOPFIT_HIT_CHANCE_ALL",
    "TOPFIT_HIT_CHANCE_SPELL", "TOPFIT_CRIT_CHANCE_ALL", "TOPFIT_CRIT_CHANCE_SPELL", "TOPFIT_HASTE_PERCENT",
    "TOPFIT_DODGE_CHANCE_ALL", "TOPFIT_BLOCK_CHANCE_ALL", "TOPFIT_DEFENSE_FLAT", "ITEM_MOD_BLOCK_VALUE_SHORT",
    "ITEM_MOD_MANA_REGENERATION_SHORT", "RESISTANCE0_NAME", "RESISTANCE6_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME",
    "RESISTANCE4_NAME", "RESISTANCE5_NAME" }

local function BuildText(entry)
    local parts = {}
    for _, key in ipairs(LABEL_ORDER) do
        local v = entry.stats[key]
        if v and v > 0 then
            local label = LABELS[key]
            if label:sub(1, 1) == "%" then
                tinsert(parts, string.format("+%g%s", v, label))
            else
                tinsert(parts, string.format("+%g %s", v, label))
            end
        end
    end
    if entry.weaponDamage and entry.weaponDamage > 0 then
        tinsert(parts, string.format("+%g weapon damage", entry.weaponDamage))
    end
    return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------
-- Index (built once, lazily): one entry per (group, name); a row that fits several slots
-- (extraTypes: an armor kit goes on chest/gloves/legs/boots, a ZG enchant on head and legs) becomes
-- one entry in each of those groups.
-- ---------------------------------------------------------------------------
local function BuildEnchantIndex()
    if TopFit.EnchantIndex then return end
    TopFit.EnchantIndex = {}
    TopFit.EnchantIndexByID = {}
    TopFit.EnchantsByGroup = {}
    for _, group in ipairs(TopFit.EnchantGroups) do TopFit.EnchantsByGroup[group] = {} end

    for _, row in ipairs(TopFit.EnchantData or {}) do
        local groups = {}
        local primary = GroupForRow(row)
        if primary then tinsert(groups, primary) end
        for _, extra in ipairs(row.extraTypes or {}) do
            local g = TYPE_TO_GROUP[extra]
            if g and g ~= primary then tinsert(groups, g) end
        end

        local stats, unmapped = {}, {}
        local function add(key, value)
            value = tonumber(value)
            if key and value and value > 0 then stats[key] = (stats[key] or 0) + value end
        end
        for i, value in ipairs(row.stats or {}) do
            if value and value ~= 0 then
                local index = i - 1
                local key = STAT_INDEX_MAP[index]
                if key and not (index == 34 and value > MAX_PLAUSIBLE_MP5) then
                    add(key, value)
                else
                    unmapped[#unmapped + 1] = index
                end
            end
        end
        -- the client lists "+26 Attack Power" as AP 26 AND ranged AP 26; attack power already grants
        -- ranged attack power (see GetEffectiveWeights), so keep only the AP half
        local apKey, rapKey = "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT"
        if stats[apKey] and stats[rapKey] and stats[apKey] == stats[rapKey] then stats[rapKey] = nil end
        PseudoToStats(row.pseudoStats, add)
        local unknownPseudo
        for i, value in ipairs(row.pseudoStats or {}) do
            if value and value ~= 0 and not KNOWN_PSEUDO[i - 1] then unknownPseudo = true end
        end

        local shortName = row.name:gsub("^Enchant [^%-]*%- ", ""):gsub("^Enchant: ", "")
        local class = CLASS_RESTRICTIONS[row.name] or CLASS_RESTRICTIONS[shortName]

        for _, group in ipairs(groups) do
            local key = group .. "|" .. row.name
            if TopFit.EnchantsByGroup[group] and not TopFit.EnchantIndex[key] then
                local entry = {
                    group = group, name = row.name, shortName = shortName, id = row.effectId,
                    spellId = row.spellId, itemId = row.itemId, class = class, stats = stats,
                    weaponDamage = (row.weaponDamage and row.weaponDamage > 0) and row.weaponDamage or nil,
                }
                entry.text = BuildText(entry)
                if not next(stats) and not entry.weaponDamage then
                    if row.name:find("Shield Spike") then
                        entry.unscoredReason = "damage dealt to attackers when you block; not scored"
                    elseif #unmapped > 0 then
                        entry.unscoredReason = "gives health/mana, which TopFit does not score"
                    elseif unknownPseudo then
                        entry.unscoredReason = "percent effect TopFit does not know"
                    else
                        entry.unscoredReason = "proc or utility effect with no stats in the client data"
                    end
                end
                TopFit.EnchantIndex[key] = entry
                TopFit.EnchantIndexByShortName = TopFit.EnchantIndexByShortName or {}
                TopFit.EnchantIndexByShortName[group .. "|" .. shortName] = TopFit.EnchantIndexByShortName[group .. "|" .. shortName] or entry
                tinsert(TopFit.EnchantsByGroup[group], entry)
                if row.effectId and not TopFit.EnchantIndexByID[row.effectId] then
                    TopFit.EnchantIndexByID[row.effectId] = entry
                end
            end
        end
    end
end

-- entries a player may use: not restricted to another class
local function UsableByPlayer(entry)
    if not entry.class then return true end
    return entry.class == select(2, UnitClass("player"))
end

function TopFit:GetEnchantEntry(group, name)
    BuildEnchantIndex()
    -- full name first; short names too, so pins saved by an earlier version still resolve
    return TopFit.EnchantIndex[group .. "|" .. name]
        or (TopFit.EnchantIndexByShortName and TopFit.EnchantIndexByShortName[group .. "|" .. name])
end

-- The enchant behind an item link's enchant field (item:ID:ENCHANTID:...), if we know that ID.
function TopFit:GetEnchantByID(enchantID)
    BuildEnchantIndex()
    return TopFit.EnchantIndexByID[tonumber(enchantID) or 0]
end

-- Entries of a group that the player could actually use (class-restricted ones filtered out).
function TopFit:GetEnchantsForGroup(group)
    BuildEnchantIndex()
    local list = {}
    for _, entry in ipairs(TopFit.EnchantsByGroup[group] or {}) do
        if UsableByPlayer(entry) then tinsert(list, entry) end
    end
    return list
end

local function IsScorable(entry)
    return next(entry.stats) ~= nil or entry.weaponDamage ~= nil
end

-- Does this group hold anything TopFit can score? (the tab hides groups that don't)
function TopFit:GroupHasScoredEnchants(group)
    for _, entry in ipairs(TopFit:GetEnchantsForGroup(group)) do
        if IsScorable(entry) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Slot / item -> group
-- ---------------------------------------------------------------------------
local FIXED_SLOT_GROUP = { [1] = "Head", [2] = "Necklace", [3] = "Shoulder", [5] = "Chest", [7] = "Legs",
                           [8] = "Boots", [9] = "Bracer", [10] = "Gloves", [15] = "Cloak" }

-- Scopes fit bows, guns and crossbows, not wands or thrown weapons.
local function IsScopeWeapon(itemTable)
    local subType = itemTable and itemTable.itemSubType
    local getName = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    if not subType or not getName then return true end   -- can't tell: allow
    for _, subClass in ipairs({ 2, 3, 18 }) do          -- bow, gun, crossbow (weapon class 2)
        if getName(2, subClass) == subType then return true end
    end
    return false
end

function TopFit:GetEnchantGroup(slotID, itemTable)
    if FIXED_SLOT_GROUP[slotID] then return FIXED_SLOT_GROUP[slotID] end
    local loc = itemTable and itemTable.itemEquipLoc
    if slotID == 16 then
        return (loc == "INVTYPE_2HWEAPON") and "2H Weapon" or "Weapon"
    elseif slotID == 17 then
        if loc == "INVTYPE_SHIELD" then return "Shield" end
        if loc == "INVTYPE_HOLDABLE" then return "Off-Hand" end
        if loc and loc:find("WEAPON") then return "Weapon" end
    elseif slotID == 18 then
        if IsScopeWeapon(itemTable) then return "Ranged" end
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
-- Flat weapon damage is item-dependent (it becomes DPS through the weapon's speed), so entries that
-- only carry weapon damage are compared on the DPS they would add to a typical 2.0-speed weapon.
function TopFit:GetBestEnchant(group, setTable)
    local weights = TopFit:GetEffectiveWeights(setTable.weights or {}, setTable)
    local best, bestScore
    for _, entry in ipairs(TopFit:GetEnchantsForGroup(group)) do
        if IsScorable(entry) then
            local score = TopFit:ScoreEnchantEntry(entry, weights)
            if entry.weaponDamage then
                local dps = entry.weaponDamage / 2.0
                score = score + dps * ((weights["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] or 0)
                    + (group == "Ranged" and (weights["TOPFIT_RANGED_DPS"] or 0) or (weights["TOPFIT_MELEE_DPS"] or 0)))
            end
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
        if choice and not UsableByPlayer(choice) then choice = nil end
        if not choice then choice = TopFit:GetBestEnchant(group, setTable) end
    end
    TopFit.enchantChoiceCache[cacheKey] = choice or false
    return choice
end

-- { entry, stats, score } for the enchant that would go on this item in this slot, or nil.
-- Flat weapon damage is turned into DPS here, using THIS item's weapon speed (damage / speed), and
-- credited to the generic weapon-DPS stat plus the melee- or ranged-specific one (a set weights one
-- or the other, never both).
function TopFit:GetEnchantForItem(setCode, slotID, itemTable)
    local group = TopFit:GetEnchantGroup(slotID, itemTable)
    if not group then return nil end
    local entry = TopFit:GetChosenEnchant(setCode, group)
    if not entry or not IsScorable(entry) then return nil end
    local setTable = TopFit.db.profile.sets[setCode]
    local weights = TopFit:GetEffectiveWeights(setTable.weights or {}, setTable)

    local stats = entry.stats
    if entry.weaponDamage then
        local speed = itemTable and itemTable.totalBonus and itemTable.totalBonus["TOPFIT_WEAPON_SPEED"]
        if speed and speed > 0 then
            local dps = entry.weaponDamage / speed
            stats = {}
            for k, v in pairs(entry.stats) do stats[k] = v end
            stats["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = (stats["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] or 0) + dps
            local specific = (group == "Ranged") and "TOPFIT_RANGED_DPS" or "TOPFIT_MELEE_DPS"
            stats[specific] = (stats[specific] or 0) + dps
        end
    end

    local score = 0
    for stat, value in pairs(stats) do score = score + (weights[stat] or 0) * value end
    return { entry = entry, stats = stats, score = score }
end

function TopFit:GetEnchantStatValue(slotID, itemTable, stat)
    if not TopFit.setCode or not itemTable then return 0 end
    local e = TopFit:GetEnchantForItem(TopFit.setCode, slotID, itemTable)
    return e and e.stats[stat] or 0
end
