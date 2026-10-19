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

local RACE_TO_WOWSIMS = {
	Human    = "Human",
	Dwarf    = "Dwarf",
	NightElf = "NightElf",
	Gnome    = "Gnome",
	Draenei  = "Draenei",
	Orc      = "Orc",
	Undead   = "Undead",
	Tauren   = "Tauren",
	Troll    = "Troll",
	BloodElf = "BloodElf",
}

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

-- Builds the Forever talent string: one segment per tab joined by "-", each segment one rank
-- digit per node ordered by row (tier) then column -- the same order the sim's talent JSONs use
-- (newTalentsConfig enforces it). GetTalentInfo's index order is not guaranteed to match, so
-- sort on the tier/column the API reports (return values 3 and 4) instead of trusting the index.
local function GetTalentString()
	local numTabs = (TopFit.GetNumTalentTabsSafe and TopFit:GetNumTalentTabsSafe()) or GetNumTalentTabs()
	if not numTabs or numTabs == 0 then return "" end

	local segments = {}
	for tab = 1, numTabs do
		local numTalents = (TopFit.GetNumTalentsSafe and TopFit:GetNumTalentsSafe(tab)) or GetNumTalents(tab)
		local nodes = {}
		for i = 1, numTalents do
			local name, _, tier, column, currentRank = GetTalentInfo(tab, i)
			-- some indices come back empty on this client; skip them (the official exporter does too)
			if name and tier and column then
				table.insert(nodes, { tier = tier, column = column, rank = currentRank or 0, index = i })
			end
		end
		table.sort(nodes, function(a, b)
			if a.tier ~= b.tier then return a.tier < b.tier end
			if a.column ~= b.column then return a.column < b.column end
			return a.index < b.index
		end)
		local digits = {}
		for _, n in ipairs(nodes) do
			table.insert(digits, tostring(n.rank))
		end
		table.insert(segments, table.concat(digits))
	end
	return table.concat(segments, "-")
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

	local _, raceToken = UnitRace("player")
	local wowsimsRace = RACE_TO_WOWSIMS[raceToken] or raceToken

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
		class = wowsimsClass,
		race = wowsimsRace,
		level = UnitLevel("player"),
		talents = GetTalentString(),
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