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
local EXPORT_VERSION = "v3.2.4"

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
	local itemID, enchantID, g1, g2, g3, g4 = itemLink:match(
		"item:(%d+):(%d*):(%d*):(%d*):(%d*):(%d*)"
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
	}
end

-- Builds the Forever talent string: one segment per tab joined by "-", each segment one rank digit per node,
-- ordered by tab, then row, then column -- the same order the sim's talent JSONs use (newTalentsConfig enforces it).
--
-- Forever stores talents as trait trees (C_Traits): one tree per class, three tabs side by side by node posX,
-- rows by posY. Beta client data (build 70425):
--   tab 1 posX 1020-2820, tab 2 posX 5020-6820, tab 3 posX 9080-10880; the grid steps by 600; posY 2130-5730.
-- So the string is built from node POSITIONS, not from any API's index order. The classic 3-tab API
-- (GetTalentInfo) is only a fallback, and is checked when called -- not once at load, which is what made
-- the export come out as "" on this client.
local TALENT_TAB_BANDS = { { 1000, 3000 }, { 5000, 7000 }, { 9000, 11000 } }   -- posX range of tab 1, 2, 3
local TALENT_ROW_RANGE = { 2100, 5800 }                                          -- posY range of the grid
local TALENT_TREE_BY_CLASS = {                                                   -- tree IDs, used if the config doesn't list them
	WARRIOR = 1117, PALADIN = 1100, HUNTER = 1091, ROGUE = 1111, PRIEST = 1114,
	SHAMAN = 1082, MAGE = 1112, WARLOCK = 1116, DRUID = 1089,
}

local function TalentTabForX(x)
	for tab, band in ipairs(TALENT_TAB_BANDS) do
		if x >= band[1] and x <= band[2] then return tab end
	end
end

-- -> { [tab] = { {x=, y=, rank=}, ... } }, number of nodes read   (nil when the trait API isn't usable)
local function ReadTraitTalentNodes()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
		return nil
	end
	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID then return nil end

	local treeIDs
	local configInfo = C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
	if configInfo and configInfo.treeIDs and #configInfo.treeIDs > 0 then
		treeIDs = configInfo.treeIDs
	else
		local _, classToken = UnitClass("player")
		treeIDs = TALENT_TREE_BY_CLASS[classToken] and { TALENT_TREE_BY_CLASS[classToken] } or {}
	end

	local tabs, count = { {}, {}, {} }, 0
	for _, treeID in ipairs(treeIDs) do
		for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
			local info = C_Traits.GetNodeInfo(configID, nodeID)
			local x, y = info and info.posX, info and info.posY
			local tab = x and y and TalentTabForX(x)
			if tab and y >= TALENT_ROW_RANGE[1] and y <= TALENT_ROW_RANGE[2] then
				table.insert(tabs[tab], { x = x, y = y, rank = info.activeRank or info.currentRank or 0 })
				count = count + 1
			end
		end
	end
	if count == 0 then return nil end
	return tabs, count
end

-- classic 3-tab API, sorted on the tier/column it reports; empty indices are skipped like the official exporter
local function ReadClassicTalentNodes()
	if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" or type(GetNumTalents) ~= "function" then
		return nil
	end
	local numTabs = GetNumTalentTabs() or 0
	if numTabs == 0 then return nil end
	local tabs, count = {}, 0
	for tab = 1, numTabs do
		tabs[tab] = {}
		for i = 1, (GetNumTalents(tab) or 0) do
			local name, _, tier, column, rank = GetTalentInfo(tab, i)
			if name and tier and column then
				table.insert(tabs[tab], { x = column, y = tier, rank = rank or 0 })
				count = count + 1
			end
		end
	end
	if count == 0 then return nil end
	return tabs, count
end

local lastTalentSource, lastTalentCounts

local function GetTalentString()
	local tabs, source = ReadTraitTalentNodes(), "traits"
	if not tabs then tabs, source = ReadClassicTalentNodes(), "classic" end
	if not tabs then
		lastTalentSource, lastTalentCounts = nil, nil
		return ""
	end

	local segments, counts = {}, {}
	for tab = 1, #tabs do
		local nodes = tabs[tab]
		table.sort(nodes, function(a, b)          -- row (posY / tier), then column (posX / column)
			if a.y ~= b.y then return a.y < b.y end
			return a.x < b.x
		end)
		local digits = {}
		for _, n in ipairs(nodes) do table.insert(digits, tostring(n.rank)) end
		segments[tab] = table.concat(digits)
		counts[tab] = #nodes
	end
	lastTalentSource, lastTalentCounts = source, counts
	return table.concat(segments, "-")
end

-- /run TopFit:DebugTalents()  -- shows which API the export used, the node count per tab and the resulting string
function TopFit:DebugTalents()
	local str = GetTalentString()
	if lastTalentSource then
		TopFit:Print(("talents via %s API, nodes per tab: %s -> %s"):format(
			lastTalentSource, table.concat(lastTalentCounts, "/"), str))
	else
		TopFit:Print("talents could not be read: neither the trait API (C_Traits) nor GetTalentInfo returned any nodes."
			.. " The export will have an empty talents string.")
	end
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
				-- no gems: the official exporter's Forever item layout is id + enchant only
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
		talents = GetTalentString(),
		-- the importer maps over this array and throws if it is missing; TopFit doesn't read professions
		professions = {},
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