--[[
	simc_export.lua
	Exports your currently equipped gear as a .simc profile, targeting the old (~2010,
	WotLK-era) SimulationCraft profile format used by the simc-335-1 build -- the one
	where each item is a slugified name plus precomputed raw stat totals, not an itemID
	the engine looks up in a database (that build had no WotLK item database at all; it
	expected you to download profiles from the Armory/Wowhead or hand-edit them).

	IMPORTANT ASSUMPTION: this uses the standard Blizzard GetInventoryItemLink()/GetItemInfo()
	APIs directly. If this server's core has the same broken item APIs you had to work around
	in VanillaRatingBuster (slot-text parsing + hidden scan frame), this module will need the
	same workaround -- it hasn't been verified against that yet.

	KNOWN GAPS (not exported, fill in by hand if they matter for your sim):
	  - weapon=<type>_<speed>speed_<min>min_<max>max  (needs weapon tooltip parsing)
	  - equip=<trigger>_<stat>_<amount>_<ppm|chance>_<dur>_<cd>  (proc encoding, see trinketlogic
	    discussion -- this build's equip= syntax is its own format, not something trinketlogic's
	    output maps to directly)
	  - talents=<wowarmory talent-calc URL string>, glyphs=<list>
	  - heroic=1 (no way to tell heroic vs normal item variants apart from itemID alone)

	STAT COVERAGE: this SimC build is DPS-sim only -- there is no token for resilience, defense
	rating, dodge/parry rating, mp5, health, mana, feral AP, or spell penetration anywhere in its
	example profiles. Those stats are simply dropped; there is nowhere in the format for them to go.
]]

local CLASS_TO_SIMC = {
	WARRIOR     = "warrior",
	PALADIN     = "paladin",
	HUNTER      = "hunter",
	ROGUE       = "rogue",
	PRIEST      = "priest",
	DEATHKNIGHT = "death_knight",
	SHAMAN      = "shaman",
	MAGE        = "mage",
	WARLOCK     = "warlock",
	DRUID       = "druid",
}

local RACE_TO_SIMC = {
	Human    = "human",
	Dwarf    = "dwarf",
	NightElf = "night_elf",
	Gnome    = "gnome",
	Draenei  = "draenei",
	Orc      = "orc",
	Undead   = "undead",
	Scourge  = "undead",
	Tauren   = "tauren",
	Troll    = "troll",
	BloodElf = "blood_elf",
}

-- maps TopFit's internal ITEM_MOD_* keys (the same ones used in presets.lua and import.lua)
-- to this SimC build's short stat tokens, reverse-engineered from the bundled example profiles
local STAT_TO_SIMC = {
	ITEM_MOD_STRENGTH_SHORT                 = "str",
	ITEM_MOD_AGILITY_SHORT                  = "agi",
	ITEM_MOD_STAMINA_SHORT                  = "sta",
	ITEM_MOD_INTELLECT_SHORT                = "int",
	ITEM_MOD_SPIRIT_SHORT                   = "spi",
	ITEM_MOD_ATTACK_POWER_SHORT             = "ap",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT      = "ap", -- this build folds ranged AP into the same "ap" token as melee AP
	ITEM_MOD_CRIT_RATING_SHORT              = "crit",
	ITEM_MOD_HIT_RATING_SHORT               = "hit",
	ITEM_MOD_HASTE_RATING_SHORT             = "haste",
	ITEM_MOD_EXPERTISE_RATING_SHORT         = "exp",
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arpen",
	ITEM_MOD_SPELL_POWER_SHORT              = "sp",
	ITEM_MOD_BLOCK_VALUE_SHORT              = "blockv",
	RESISTANCE0_NAME                        = "armor",
}

-- TopFit.slots key -> simc field name, in the same order real exported profiles use
local SLOT_ORDER = {
	{ "HeadSlot",          "head" },
	{ "NeckSlot",          "neck" },
	{ "ShoulderSlot",      "shoulders" },
	{ "ChestSlot",         "chest" },
	{ "WaistSlot",         "waist" },
	{ "LegsSlot",          "legs" },
	{ "FeetSlot",          "feet" },
	{ "WristSlot",         "wrists" },
	{ "HandsSlot",         "hands" },
	{ "Finger0Slot",       "finger1" },
	{ "Finger1Slot",       "finger2" },
	{ "Trinket0Slot",      "trinket1" },
	{ "Trinket1Slot",      "trinket2" },
	{ "BackSlot",          "back" },
	{ "MainHandSlot",      "main_hand" },
	{ "SecondaryHandSlot", "off_hand" },
	{ "RangedSlot",        "ranged" },
}

-- turns an item name into a SimC-style slug: lowercase, non-alphanumerics -> underscores
local function Slugify(name)
	if not name or name == "" then return "unknown_item" end
	name = name:lower()
	name = name:gsub("'", "")
	name = name:gsub("[^%w]+", "_")
	name = name:gsub("^_+", ""):gsub("_+$", "")
	if name == "" then return "unknown_item" end
	return name
end

-- turns a {ITEM_MOD_KEY = value} bonus table into a SimC "123agi_456sta"-style blob.
-- returns nil if nothing in it translates (caller should omit the field entirely)
local function BonusTableToSimcBlob(bonusTable)
	if not bonusTable then return nil end
	local parts = {}
	for stat, value in pairs(bonusTable) do
		local token = STAT_TO_SIMC[stat]
		if token and value and value ~= 0 then
			-- values are always whole numbers in every example profile; round rather than
			-- emit a fractional token like "212.0ap" which the parser may choke on
			tinsert(parts, tostring(math.floor(value + 0.5)) .. token)
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "_")
end

-- builds the full .simc text for the player's currently equipped gear
function TopFit:GenerateSimcExportString()
	local _, classToken = UnitClass("player")
	local simcClass = CLASS_TO_SIMC[classToken]
	if not simcClass then
		TopFit:Print("Don't know the SimC class token for " .. tostring(classToken) .. ".")
		return nil
	end

	local _, raceToken = UnitRace("player")
	local simcRace = RACE_TO_SIMC[raceToken]

	local lines = {}
	tinsert(lines, simcClass .. "=" .. (UnitName("player") or "Unknown"))
	tinsert(lines, "origin=\"Exported from TopFit\"")
	tinsert(lines, "level=" .. UnitLevel("player"))
	if simcRace then
		tinsert(lines, "race=" .. simcRace)
	end
	tinsert(lines, "")

	for _, slotInfo in ipairs(SLOT_ORDER) do
		local slotName, simcField = slotInfo[1], slotInfo[2]
		local slotID = TopFit.slots[slotName]
		local itemLink = slotID and GetInventoryItemLink("player", slotID)

		if itemLink then
			local itemTable = TopFit:GetCachedItem(itemLink)
			local itemName = GetItemInfo(itemLink)
			local fieldParts = { simcField .. "=" .. Slugify(itemName) }

			local statsBlob = itemTable and BonusTableToSimcBlob(itemTable.itemBonus)
			if statsBlob then tinsert(fieldParts, "stats=" .. statsBlob) end

			local gemsBlob = itemTable and BonusTableToSimcBlob(itemTable.gemBonus)
			if gemsBlob then tinsert(fieldParts, "gems=" .. gemsBlob) end

			local enchantBlob = itemTable and BonusTableToSimcBlob(itemTable.enchantBonus)
			if enchantBlob then tinsert(fieldParts, "enchant=" .. enchantBlob) end

			tinsert(lines, table.concat(fieldParts, ","))
		end
	end

	tinsert(lines, "")
	tinsert(lines, "# NOT exported -- fill in by hand if they matter:")
	tinsert(lines, "#   weapon dps/speed (weapon=...), trinket/weapon procs (equip=...)")
	tinsert(lines, "#   talents=, glyphs=, heroic=1 flags")

	return table.concat(lines, "\n")
end

function TopFit:ShowSimcExportDialog()
	local exportString = TopFit:GenerateSimcExportString()
	if not exportString then return end
	StaticPopup_Show('TOPFIT_EXPORT', "Copy this into a .simc file (Ctrl+C):", nil, exportString)
end
