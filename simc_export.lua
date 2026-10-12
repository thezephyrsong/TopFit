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

local function EncodeJSON(val)
	local t = type(val)
	if t == "number" or t == "boolean" then
		return tostring(val)
	elseif t == "string" then
		return string.format("%q", val)
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
				table.insert(parts, string.format("%q:%s", k, EncodeJSON(v)))
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
	WARRIOR = "Warrior",
	PALADIN = "Paladin",
	HUNTER  = "Hunter",
	ROGUE   = "Rogue",
	PRIEST  = "Priest",
	SHAMAN  = "Shaman",
	MAGE    = "Mage",
	WARLOCK = "Warlock",
	DRUID   = "Druid",
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

-- Constructs Classic-style talent string allocations
local function GetTalentString()
	local numTabs = (TopFit.GetNumTalentTabsSafe and TopFit:GetNumTalentTabsSafe()) or GetNumTalentTabs()
	if not numTabs or numTabs == 0 then return "" end

	local digits = {}
	for tab = 1, numTabs do
		local numTalents = (TopFit.GetNumTalentsSafe and TopFit:GetNumTalentsSafe(tab)) or GetNumTalents(tab)
		for i = 1, numTalents do
			local _, _, _, _, currentRank = GetTalentInfo(tab, i)
			table.insert(digits, tostring(currentRank or 0))
		end
	end
	return table.concat(digits)
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
				if parsed.gems then
					itemEntry.gems = parsed.gems
				end
				table.insert(itemsList, itemEntry)
			else
				table.insert(itemsList, {})
			end
		else
			table.insert(itemsList, {})
		end
	end

	local payload = {
		class = wowsimsClass,
		race = wowsimsRace,
		level = UnitLevel("player"),
		talents = GetTalentString(),
		equipment = {
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