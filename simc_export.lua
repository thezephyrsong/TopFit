--[[
	simc_export.lua
	Exports currently equipped gear, talents, and character state as a JSON string
	compatible with the WoWsims Web App (Import -> Addon / Text).
]]

local function GetItemInfoSafe(item)
	if not item then return nil end
	local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if GetInfo then
		return GetInfo(item)
	end
	return nil
end

-- ============================================================================
-- JSON SERIALIZER
-- ============================================================================

local JSON_NULL = {} -- sentinel: encodes as null (used for empty gear slots)

local function EncodeString(str)
	return '"' .. str:gsub('[%c"\\]', function(c)
		local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
		return map[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local function EncodeJSON(val)
	local t = type(val)
	if val == JSON_NULL then
		return "null"
	elseif t == "number" or t == "boolean" then
		return tostring(val)
	elseif t == "string" then
		return EncodeString(val)
	elseif t == "table" then
		local isArray = (#val > 0) or (next(val) == nil)
		local parts = {}
		if isArray then
			for _, v in ipairs(val) do
				table.insert(parts, EncodeJSON(v))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			for k, v in pairs(val) do
				table.insert(parts, EncodeString(tostring(k)) .. ":" .. EncodeJSON(v))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

-- ============================================================================
-- MAPPERS & ENUMS
-- ============================================================================

local CLASS_TO_WOWSIMS = {
	WARRIOR = "warrior",
	PALADIN = "paladin",
	HUNTER  = "hunter",
	ROGUE   = "rogue",
	PRIEST  = "priest",
	SHAMAN  = "shaman",
	MAGE    = "mage",
	WARLOCK = "warlock",
	DRUID   = "druid",
}

-- Names exactly as the sim's importer knows them (it lower-cases and drops spaces before matching, see
-- nameToRace in ui/sim/proto/names.ts). Keyed by UnitRace's token and by its English name. WoW: Forever has no
-- Draenei. Both Skyborne variants come back from the client as plain "Skyborne"; they are told apart by
-- faction in GenerateWowsimsExportString (Windshaper = Horde, High Order = Alliance).
local RACE_TO_WOWSIMS = {
	Human    = "Human",
	Dwarf    = "Dwarf",
	NightElf = "Night Elf",
	["Night Elf"] = "Night Elf",
	Gnome    = "Gnome",
	Orc      = "Orc",
	Undead   = "Undead",
	Scourge  = "Undead",
	Tauren   = "Tauren",
	Troll    = "Troll",
	BloodElf = "Blood Elf",
	["Blood Elf"] = "Blood Elf",
	HighOrderSkyborne = "High Order Skyborne",
	WindshaperSkyborne = "Windshaper Skyborne",
}

-- The sim's addon importer compares this with the latest release tag of wowsims/exporter and only shows a
-- "not up to date" toast when it differs (an absent version shows as 'undefined'); it never blocks the import.
local EXPORT_VERSION = "v3.2.6"

-- Slot mapping ordered by inventory slot IDs
local SLOT_MAPPING = {
	{ slotID = 1,  name = "head" },
	{ slotID = 2,  name = "neck" },
	{ slotID = 3,  name = "shoulders" },
	{ slotID = 15, name = "back" },
	{ slotID = 5,  name = "chest" },
	{ slotID = 9,  name = "wrists" },
	{ slotID = 10, name = "hands" },
	{ slotID = 6,  name = "waist" },
	{ slotID = 7,  name = "legs" },
	{ slotID = 8,  name = "feet" },
	{ slotID = 11, name = "finger1" },
	{ slotID = 12, name = "finger2" },
	{ slotID = 13, name = "trinket1" },
	{ slotID = 14, name = "trinket2" },
	{ slotID = 16, name = "mainHand" },
	{ slotID = 17, name = "offHand" },
	{ slotID = 18, name = "ranged" },
}

-- Extract numeric item details from item link
local function ParseItemLink(itemLink)
	if not itemLink then return nil end

	-- Link format: |cffffffff|Hitem:itemID:enchantID:gemID1:gemID2:gemID3:gemID4...
	local itemID, enchantID, g1, g2, g3, g4, suffixID = itemLink:match(
		"item:(%d+):(%d*):(%d*):(%d*):(%d*):(%d*):(%-?%d*)"
	)

	if not itemID then return nil end

	local gems = {}
	for _, g in ipairs({ g1, g2, g3, g4 }) do
		local gemID = tonumber(g)
		if gemID and gemID > 0 then
			table.insert(gems, gemID)
		end
	end

	return {
		id = tonumber(itemID),
		enchant = tonumber(enchantID) or 0,
		gems = #gems > 0 and gems or nil,
		randomSuffix = tonumber(suffixID) or 0,
	}
end

-- Builds the talent string the way the WoWSims sim reads it: one digit per talent, trees joined by "-", e.g.
-- "0500032-05-3". Digit i of tree t is talent i of tree t in the sim's own tree files
-- (ui/sim/talents/trees/<class>.json), which are sorted tab, then row, then column.
--
-- Forever exposes talents through C_Traits, not GetTalentInfo, so the client's nodes are matched to the sim's
-- order by TraitDefinition ID using TopFit.TalentTrees (talentdata.lua, generated from the sim by
-- tools/gen_talents.py). The official WoWSims exporter addon does the same. As in the sim's own serializer,
-- trailing zeroes of every tree and trailing dashes are cut off.
local lastTalentInfo

local function GetActiveTalentConfigID()
	if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
		return C_ClassTalents.GetActiveConfigID()
	end
	if C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
		local group = C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup() or 1
		return C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group)
	end
end

-- { [TraitDefinition ID] = rank } for every talent with points in the active config, or nil if unreadable
local function ReadTalentRanks()
	if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo and C_Traits.GetEntryInfo) then
		return nil
	end
	local configID = GetActiveTalentConfigID()
	if not configID then return nil end
	local configInfo = C_Traits.GetConfigInfo(configID)
	if not (configInfo and configInfo.treeIDs) then return nil end

	local ranks = {}
	for _, treeID in ipairs(configInfo.treeIDs) do
		for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			-- currentRank also counts ranks granted without spending points
			local rank = node and (node.currentRank or node.ranksPurchased) or 0
			if rank > 0 and node.activeEntry then
				local entry = C_Traits.GetEntryInfo(configID, node.activeEntry.entryID)
				if entry and entry.definitionID then
					ranks[entry.definitionID] = rank
				end
			end
		end
	end
	return ranks
end

local function GetTalentString()
	lastTalentInfo = nil
	local _, classToken = UnitClass("player")
	local trees = TopFit.TalentTrees and TopFit.TalentTrees[classToken]
	if not trees then
		lastTalentInfo = { problem = "talentdata.lua has no talent trees for class " .. tostring(classToken)
			.. " (run: python tools/update_data.py --only talents)" }
		return ""
	end
	local ranks = ReadTalentRanks()
	if not ranks then
		lastTalentInfo = { problem = "the client's talent API (C_Traits) returned nothing" }
		return ""
	end

	local treeStrings, spent = {}, {}
	for treeIdx, definitionIds in ipairs(trees) do
		local digits, points = {}, 0
		for talentIdx, definitionId in ipairs(definitionIds) do
			local rank = ranks[definitionId] or 0
			digits[talentIdx] = tostring(rank)
			points = points + rank
		end
		treeStrings[treeIdx] = (table.concat(digits):gsub("0+$", ""))
		spent[treeIdx] = points
	end
	lastTalentInfo = { spent = spent }
	return (table.concat(treeStrings, "-"):gsub("%-+$", ""))
end

-- /run TopFit:DebugTalents()  -- prints the points spent per tree and the string that will be exported
function TopFit:DebugTalents()
	local str = GetTalentString()
	if lastTalentInfo and lastTalentInfo.spent then
		TopFit:Print(("talents: points per tree %s -> \"%s\""):format(table.concat(lastTalentInfo.spent, "/"), str))
	else
		TopFit:Print("talents could not be read: " .. ((lastTalentInfo and lastTalentInfo.problem) or "unknown reason")
			.. ". The export will have an empty talents string.")
	end
end

-- Professions, read like the official exporter on the retail-based Forever client (skill line -> sim name).
local PROFESSION_BY_SKILL_LINE = {
	[164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism", [186] = "Mining",
	[197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [393] = "Skinning",
}

local function GetProfessionList()
	local list = {}
	if not (GetProfessions and GetProfessionInfo) then return list end
	pcall(function()
		local first, second = GetProfessions()
		for _, index in pairs({ first, second }) do
			local _, _, skillLevel, _, _, _, skillLine = GetProfessionInfo(index)
			local name = PROFESSION_BY_SKILL_LINE[skillLine]
			if name then table.insert(list, { name = name, level = skillLevel }) end
		end
	end)
	return list
end

-- ============================================================================
-- EXPORT ENGINE
-- ============================================================================

function TopFit:GenerateWowsimsExportString()
	local _, classToken = UnitClass("player")
	local wowsimsClass = CLASS_TO_WOWSIMS[classToken]
	if not wowsimsClass then
		TopFit:Print("Unsupported class token for WoWsims: " .. tostring(classToken))
		return nil
	end

	local raceName, raceToken = UnitRace("player")
	local wowsimsRace = RACE_TO_WOWSIMS[raceToken] or RACE_TO_WOWSIMS[raceName]
	if not wowsimsRace and (tostring(raceToken):find("Skyborne") or tostring(raceName):find("Skyborne")) then
		wowsimsRace = (UnitFactionGroup("player") == "Horde") and "Windshaper Skyborne" or "High Order Skyborne"
	end
	wowsimsRace = wowsimsRace or raceToken or raceName

	local itemsList = {}

	for _, slot in ipairs(SLOT_MAPPING) do
		local itemLink = GetInventoryItemLink("player", slot.slotID)
		if itemLink then
			local parsed = ParseItemLink(itemLink)
			if parsed then
				local itemEntry = { id = parsed.id }
				if parsed.enchant > 0 then
					itemEntry.enchant = parsed.enchant
				end
				-- Forever items can carry a random suffix ("of the Eagle"); the sim needs it to know the item's stats.
				-- (No gems: the Forever item layout is id, enchant and random_suffix only.)
				if parsed.randomSuffix ~= 0 then
					itemEntry.random_suffix = parsed.randomSuffix
				end
				table.insert(itemsList, itemEntry)
			else
				table.insert(itemsList, JSON_NULL)
			end
		else
			table.insert(itemsList, JSON_NULL)
		end
	end

	local payload = {
		version = EXPORT_VERSION,
		class = wowsimsClass,
		race = wowsimsRace,
		level = UnitLevel("player"),
		flavor = "forever",
		talents = GetTalentString(),
		-- the sim's importer maps over this array and throws if it is missing
		professions = GetProfessionList(),
		gear = {
			items = itemsList
		}
	}

	return EncodeJSON(payload)
end

function TopFit:ShowSimcExportDialog()
	local exportString = TopFit:GenerateWowsimsExportString()
	if not exportString then return end

	-- Displays in standard copy dialog frame
	if StaticPopupDialogs["TOPFIT_EXPORT"] then
		StaticPopup_Show('TOPFIT_EXPORT', "Copy this into WoWsims (Import -> Addon / Text):", nil, exportString)
	else
		TopFit:Print("WoWsims JSON Output:")
		print(exportString)
	end
end