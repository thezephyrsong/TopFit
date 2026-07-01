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

-- diagnostic: prints exactly what GetNumTalentTabs()/GetNumTalents() report per tab, plus
-- each talent's name and max rank, so a count mismatch against the in-game UI can be pinned
-- down precisely instead of guessed at.
function TopFit:DebugTalentCounts()
	local numTabs = GetNumTalentTabs()
	TopFit:Print("GetNumTalentTabs() = " .. tostring(numTabs))
	local total = 0
	for tab = 1, numTabs do
		local tabName = select(1, GetTalentTabInfo(tab))
		local numTalents = GetNumTalents(tab)
		total = total + numTalents
		TopFit:Print(("Tab %d (%s): GetNumTalents() = %d"):format(tab, tostring(tabName), numTalents))
		for i = 1, numTalents do
			local name, _, _, _, currentRank, maxRank = GetTalentInfo(tab, i)
			TopFit:Print(("  [%d] %s -- rank %d/%d"):format(i, tostring(name), currentRank or 0, maxRank or 0))
		end
	end
	TopFit:Print("Total talent slots across all tabs = " .. total)
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
-- maps a weapon's itemSubType (the string GetItemInfo() already returns directly -- e.g.
-- "Daggers", "One-Handed Swords", "Two-Handed Maces" -- this IS the localized display text,
-- no lookup table needed to get it) to a SimC weapon type token.
-- NOTE: this matches against the English text. If this server runs a non-English client,
-- these substrings won't match and weapon= will simply be omitted -- same caveat already
-- noted for the Force Armor Type filter elsewhere in this addon.
local function GetSimcWeaponType(itemLink)
	local subType = select(7, GetItemInfo(itemLink))
	if not subType then return nil end

	local isTwoHand = subType:find("Two%-Handed") ~= nil

	if subType:find("Axe") then return isTwoHand and "axe2h" or "axe" end
	if subType:find("Mace") then return isTwoHand and "mace2h" or "mace" end
	if subType:find("Sword") then return isTwoHand and "sword2h" or "sword" end
	if subType:find("Dagger") then return "dagger" end
	if subType:find("Fist") then return "fist" end
	if subType:find("Polearm") then return "polearm" end
	if subType:find("Staves") or subType:find("Staff") then return "staff" end
	if subType:find("Crossbow") then return "crossbow" end
	if subType:find("Bow") then return "bow" end
	if subType:find("Gun") then return "gun" end
	if subType:find("Wand") then return "wand" end
	if subType:find("Thrown") then return "thrown" end

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
local function BuildWeaponField(itemLink)
	local simcType = GetSimcWeaponType(itemLink)
	if not simcType then return nil end

	local speed, minDmg, maxDmg = GetWeaponSpeedAndDamage(itemLink)
	if not (speed and minDmg and maxDmg) then return nil end

	-- Correct formatting string using underscores to separate properties
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

-- "Glyph of Arcane Blast" -> "arcane_blast", matching the bundled example profiles' format
local function SlugifyGlyphName(name)
	if not name then return nil end
	name = name:gsub("^[Gg]lyph%s+of%s+", "")
	return Slugify(name)
end

-- reads your currently active glyphs (major + minor) via the live glyph API and returns a
-- "/"-separated slug string, or nil if no glyphs are socketed
local function GetGlyphsString()
	local numSockets = GetNumGlyphSockets and GetNumGlyphSockets()
	if not numSockets or numSockets == 0 then return nil end

	local slugs = {}
	for socket = 1, numSockets do
		local enabled, _, glyphSpellID = GetGlyphSocketInfo(socket)
		if enabled and glyphSpellID and glyphSpellID > 0 then
			local glyphName = GetSpellInfo(glyphSpellID)
			local slug = SlugifyGlyphName(glyphName)
			if slug then tinsert(slugs, slug) end
		end
	end

	if #slugs == 0 then return nil end
	return table.concat(slugs, "/")
end

-- the ammo subType a ranged weapon needs, keyed by GetSimcWeaponType()'s token for it
local RANGED_TYPE_TO_AMMO_SUBTYPE = {
	bow = "Arrow",
	crossbow = "Arrow",
	gun = "Bullet",
}

-- scans an ammo item's tooltip for its "(X.X damage per second)" bonus
local function GetAmmoDps(itemLink)
	TopFit.scanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	TopFit.scanTooltip:SetHyperlink(itemLink)
	local numLines = TopFit.scanTooltip:NumLines()

	local dps
	for i = 1, numLines do
		local leftLine = getglobal("TFScanTooltip" .. "TextLeft" .. i)
		local leftLineText = leftLine and leftLine:GetText()
		if leftLineText then
			local match = leftLineText:lower():match("%(([%d%.]+)%s*damage per second%)")
			if match then dps = tonumber(match) end
		end
	end
	TopFit.scanTooltip:Hide()
	return dps
end

-- scans all bags for the highest-DPS ammo matching the given ranged weapon type
-- (bow/crossbow want Arrows, gun wants Bullets), independent of what's actually loaded.
-- "Best available" rather than "currently equipped" per your request -- ammo is cheap and
-- commonly swapped right before a sim/raid anyway, so the highest one you're carrying is a
-- more useful number than whatever happens to be loaded at export time.
local function GetBestAmmoDps(rangedSimcType)
	local neededSubType = RANGED_TYPE_TO_AMMO_SUBTYPE[rangedSimcType]
	if not neededSubType then return nil end

	local bestDps
	for bag = 0, 4 do
		local numSlots = GetContainerNumSlots(bag)
		for slot = 1, numSlots do
			local itemLink = GetContainerItemLink(bag, slot)
			if itemLink then
				local subType = select(7, GetItemInfo(itemLink))
				if subType == neededSubType then
					local dps = GetAmmoDps(itemLink)
					if dps and (not bestDps or dps > bestDps) then
						bestDps = dps
					end
				end
			end
		end
	end
	return bestDps
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

	local glyphsString = GetGlyphsString()
	if glyphsString then
		tinsert(lines, "glyphs=" .. glyphsString)
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

			local weaponType
			if WEAPON_SLOTS[slotName] then
				weaponType = GetSimcWeaponType(itemLink)
				local weaponField = BuildWeaponField(itemLink)
				if weaponField then tinsert(fieldParts, weaponField) end
			end

			if slotName == "RangedSlot" and weaponType then
				local ammoDps = GetBestAmmoDps(weaponType)
				if ammoDps then
					tinsert(fieldParts, ("ammo_dps=%.2f"):format(ammoDps))
				end
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
	tinsert(lines, "#   heroic=1 flags")
	if #procComments > 0 then
		tinsert(lines, "# Possible procs found (could not auto-encode, see simc_export.lua header):")
		for _, comment in ipairs(procComments) do
			tinsert(lines, comment)
		end
	end

	return table.concat(lines, "\n")
end

function TopFit:DebugWeaponSlots()
	local weaponSlotNames = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }
	for _, slotName in ipairs(weaponSlotNames) do
		local slotID = TopFit.slots[slotName]
		local itemLink = slotID and GetInventoryItemLink("player", slotID)
		if not itemLink then
			TopFit:Print(slotName .. ": empty")
		else
			local itemName, _, _, _, _, _, subType = GetItemInfo(itemLink)
			local simcType = GetSimcWeaponType(itemLink)
			TopFit:Print(("%s: %s | subType=%s | simcType=%s"):format(
				slotName, tostring(itemName), tostring(subType), tostring(simcType)
			))
			if simcType then
				local speed, minDmg, maxDmg = GetWeaponSpeedAndDamage(itemLink)
				TopFit:Print(("  tooltip scan: speed=%s min=%s max=%s"):format(
					tostring(speed), tostring(minDmg), tostring(maxDmg)
				))
			end
		end
	end
end

function TopFit:ShowSimcExportDialog()
	local exportString = TopFit:GenerateSimcExportString()
	if not exportString then return end
	StaticPopup_Show('TOPFIT_EXPORT', "Copy this into a .simc file (Ctrl+C):", nil, exportString)
end
