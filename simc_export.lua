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
	  - glyphs=<list>
	  - heroic=1 (no way to tell heroic vs normal item variants apart from itemID alone)
	  - ammo_dps=<value> for Hunters (ammo's flat ranged-damage bonus isn't parsed yet)

	PROC EFFECTS (Use:/Equip:): handled by procparser.lua. Click-to-use trinkets with a stated
	cooldown are emitted as a real "actions+=/use_item,name=<slug>" line -- this is the format
	the bundled example profiles actually use for those, and it's correct regardless of whether
	the engine recognizes the specific item (it just won't simulate an effect it doesn't know,
	which is true for any custom-server item either way; this module can't change that).
	Passive on-equip "chance on hit/cast" procs are emitted ONLY as a "# possible proc:" comment
	with the parsed stat/amount/duration, never as a real equip= line -- this engine's equip=
	syntax also encodes a *trigger event* (onattackhit / onspellcast / onspelldamage / etc.)
	that cannot be reliably determined from tooltip text, since differently-triggered procs can
	read identically. Fabricating a guessed trigger would produce a profile that looks precise
	but may simulate the wrong condition; the comment is there for you to encode by hand once
	you know (or test) what actually triggers it.

	TALENTS: exported as talents=http://www.wowarmory.com/talent-calc.xml?cid=X&tal=NNNN...,
	read directly from your live talent allocation via GetTalentInfo(). This is the format
	the engine's local parser expects (the wowarmory.com site itself has been dead for years --
	this isn't a live request). Note this is NOT the same encoding as Wowhead's current
	talent-calc URLs (e.g. wowhead.com/wotlk/talent-calc/...), which use a different scheme
	entirely and aren't convertible to/from this one.

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

-- Blizzard's old wowarmory.com talent-calc "cid" (class id) numbering. This engine parses
-- talents=http://www.wowarmory.com/talent-calc.xml?cid=X&tal=NNNN... as a plain string --
-- the site itself has been dead for over a decade, so this is NOT a live web request, it's
-- just the string format the engine's local parser recognizes. Wowhead's modern talent-calc
-- URLs use a completely different encoding and are not interchangeable with this one.
local CLASS_TO_WOWARMORY_CID = {
	WARRIOR     = 1,
	PALADIN     = 2,
	HUNTER      = 3,
	ROGUE       = 4,
	PRIEST      = 5,
	DEATHKNIGHT = 6,
	SHAMAN      = 7,
	MAGE        = 8,
	WARLOCK     = 9,
	DRUID       = 11, -- 10 is skipped in this numbering
}

-- builds the wowarmory-style "tal=" digit string from your CURRENT live talent allocation:
-- one digit (0-5) per talent, tab 1 then tab 2 then tab 3, in the same order the in-game
-- talent UI lists them -- which is also the order GetTalentInfo returns them in.
local function GetWowarmoryTalentString()
	local digits = {}
	for tab = 1, GetNumTalentTabs() do
		for i = 1, GetNumTalents(tab) do
			local currentRank = select(5, GetTalentInfo(tab, i)) or 0
			tinsert(digits, tostring(currentRank))
		end
	end
	return table.concat(digits)
end

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

-- maps GetAuctionItemSubClasses(1) [Weapon category] index -> SimC weapon type token, reverse-
-- engineered from the bundled example profiles (axe2h/mace2h/sword2h for 2H variants; polearms
-- and staves have no "2h" variant since every polearm/staff is already 2H). Indices 12 (Misc)
-- and 17 (Fishing Poles) have no SimC token and are intentionally omitted.
-- Uses the same locale-safe technique as TopFit:IsOnehandedWeapon() elsewhere in this codebase:
-- compare against the locally-translated string fetched by stable index, never hardcode English.
local WEAPON_SUBCLASS_INDEX_TO_SIMC = {
	[1]  = "axe",      -- One-Handed Axes
	[2]  = "axe2h",    -- Two-Handed Axes
	[3]  = "bow",      -- Bows
	[4]  = "gun",      -- Guns
	[5]  = "mace",     -- One-Handed Maces
	[6]  = "mace2h",   -- Two-Handed Maces
	[7]  = "polearm",  -- Polearms
	[8]  = "sword",    -- One-Handed Swords
	[9]  = "sword2h",  -- Two-Handed Swords
	[10] = "staff",    -- Staves
	[11] = "fist",     -- Fist Weapons
	[13] = "dagger",   -- Daggers
	[14] = "thrown",   -- Thrown
	[15] = "crossbow", -- Crossbows
	[16] = "wand",     -- Wands
}

-- returns the SimC weapon type token for an item link, or nil if it isn't a weapon at all
-- (shields, held-in-offhand items, idols/totems/librams/sigils all correctly fall through to nil)
local function GetSimcWeaponType(itemLink)
	local subclass = select(7, GetItemInfo(itemLink))
	if not subclass then return nil end
	for index, simcToken in pairs(WEAPON_SUBCLASS_INDEX_TO_SIMC) do
		if subclass == select(index, GetAuctionItemSubClasses(1)) then
			return simcToken
		end
	end
	return nil
end

-- scans a weapon's tooltip for its speed and damage range. There is no clean Lua API for this
-- on arbitrary items in this client era, so -- consistent with how this codebase already handles
-- socket bonuses and BoE detection -- this reads the tooltip text directly.
-- NOTE: the tooltip only ever displays whole-number damage (the client rounds it for display),
-- so these values will be slightly less precise than a database-sourced export like Wowhead's;
-- that's an inherent limitation of reading it off the tooltip rather than a bug.
-- NOTE: relies on the English tooltip words "Speed" and "Damage", consistent with the same
-- English-client assumption already made for the Force Armor Type filter.
local function GetWeaponSpeedAndDamage(itemLink)
	TopFit.scanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	TopFit.scanTooltip:SetHyperlink(itemLink)
	local numLines = TopFit.scanTooltip:NumLines()

	local speed, minDmg, maxDmg
	for i = 1, numLines do
		local leftLine = getglobal("TFScanTooltip" .. "TextLeft" .. i)
		local leftLineText = leftLine:GetText()
		if leftLineText then
			local dmgMin, dmgMax = leftLineText:match("^(%d+)%s*%-%s*(%d+)%s+Damage")
			if dmgMin then
				minDmg, maxDmg = tonumber(dmgMin), tonumber(dmgMax)
			end
			local speedMatch = leftLineText:match("Speed%s+([%d%.]+)")
			if speedMatch then
				speed = tonumber(speedMatch)
			end
		end
	end
	TopFit.scanTooltip:Hide()

	return speed, minDmg, maxDmg
end

-- builds the "weapon=type_X.XXspeed_MINmin_MAXmax" field, or nil if this isn't a weapon
-- or the tooltip scan came back incomplete
local function BuildWeaponField(itemLink)
	local simcType = GetSimcWeaponType(itemLink)
	if not simcType then return nil end

	local speed, minDmg, maxDmg = GetWeaponSpeedAndDamage(itemLink)
	if not (speed and minDmg and maxDmg) then return nil end

	return ("weapon=%s_%.2fspeed_%dmin_%dmax"):format(simcType, speed, minDmg, maxDmg)
end

-- slots that can hold a weapon (as opposed to e.g. off-hand shields/held-items, which
-- BuildWeaponField already filters out naturally via GetSimcWeaponType returning nil for them)
local WEAPON_SLOTS = {
	MainHandSlot = true,
	SecondaryHandSlot = true,
	RangedSlot = true,
}
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

	local cid = CLASS_TO_WOWARMORY_CID[classToken]
	local talString = GetWowarmoryTalentString()
	if cid and talString and talString ~= "" then
		tinsert(lines, "talents=http://www.wowarmory.com/talent-calc.xml?cid=" .. cid .. "&tal=" .. talString)
	end

	tinsert(lines, "")

	local useItemActions = {}
	local procComments = {}

	for _, slotInfo in ipairs(SLOT_ORDER) do
		local slotName, simcField = slotInfo[1], slotInfo[2]
		local slotID = TopFit.slots[slotName]
		local itemLink = slotID and GetInventoryItemLink("player", slotID)

		if itemLink then
			local itemTable = TopFit:GetCachedItem(itemLink)
			local itemName = GetItemInfo(itemLink)
			local slug = Slugify(itemName)
			local fieldParts = { simcField .. "=" .. slug }

			local statsBlob = itemTable and BonusTableToSimcBlob(itemTable.itemBonus)
			if statsBlob then tinsert(fieldParts, "stats=" .. statsBlob) end

			local gemsBlob = itemTable and BonusTableToSimcBlob(itemTable.gemBonus)
			if gemsBlob then tinsert(fieldParts, "gems=" .. gemsBlob) end

			local enchantBlob = itemTable and BonusTableToSimcBlob(itemTable.enchantBonus)
			if enchantBlob then tinsert(fieldParts, "enchant=" .. enchantBlob) end

			if WEAPON_SLOTS[slotName] then
				local weaponField = BuildWeaponField(itemLink)
				if weaponField then tinsert(fieldParts, weaponField) end
			end

			tinsert(lines, table.concat(fieldParts, ","))

			-- Use:/Equip: procs. Use-effects with a real stated cooldown become an actual
			-- action list entry the engine can act on (matches the bundled example profiles'
			-- own format for this exact case). Equip-effects -- and any proc whose cooldown
			-- couldn't be determined -- become a comment only; see header for why.
			local procInfo = itemTable and itemTable.procInfo
			if procInfo then
				if procInfo.trigger == "use" and procInfo.cooldown then
					tinsert(useItemActions, "actions+=/use_item,name=" .. slug)
				else
					local statName = STAT_TO_SIMC[procInfo.statKey] or procInfo.statKey
					local desc = ("%s (%s): +%s %s"):format(itemName, procInfo.trigger, procInfo.amount, statName)
					if procInfo.duration then desc = desc .. (" for %ds"):format(procInfo.duration) end
					if procInfo.cooldown then desc = desc .. (", %ds cooldown"):format(procInfo.cooldown) end
					tinsert(procComments, "#   " .. desc .. " -- proc chance/trigger unknown, verify and encode manually")
				end
			end
		end
	end

	if #useItemActions > 0 then
		tinsert(lines, "")
		for _, action in ipairs(useItemActions) do
			tinsert(lines, action)
		end
	end

	tinsert(lines, "")
	tinsert(lines, "# NOT exported -- fill in by hand if they matter:")
	tinsert(lines, "#   glyphs=, heroic=1 flags, ammo_dps= (Hunters)")
	if #procComments > 0 then
		tinsert(lines, "# Possible procs found (could not auto-encode, see simc_export.lua header):")
		for _, comment in ipairs(procComments) do
			tinsert(lines, comment)
		end
	end

	return table.concat(lines, "\n")
end

function TopFit:ShowSimcExportDialog()
	local exportString = TopFit:GenerateSimcExportString()
	if not exportString then return end
	StaticPopup_Show('TOPFIT_EXPORT', "Copy this into a .simc file (Ctrl+C):", nil, exportString)
end
