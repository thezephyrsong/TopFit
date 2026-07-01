--[[
	simc_export.lua
	Exports your currently equipped gear as a .simc profile, targeting the old (~2010,
	WotLK-era) SimulationCraft profile format used by the simc-335-1 build -- the one
	where each item is a slugified name plus precomputed raw stat totals, not an itemID
	the engine looks up in a database (that build had no WotLK item database at all; it
	expected you to download profiles from the Armory/Wowhead or hand-edit them).

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

-- Blizzard's old wowarmory.com talent-calc "cid" (class id) numbering.
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
	DRUID       = 11,
}

-- builds the wowarmory-style "tal=" digit string from your CURRENT live talent allocation
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

-- diagnostic talent tracking
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

-- maps internal ITEM_MOD_* keys to this SimC build's short stat tokens
local STAT_TO_SIMC = {
	ITEM_MOD_STRENGTH_SHORT                 = "str",
	ITEM_MOD_AGILITY_SHORT                  = "agi",
	ITEM_MOD_STAMINA_SHORT                  = "sta",
	ITEM_MOD_INTELLECT_SHORT                = "int",
	ITEM_MOD_SPIRIT_SHORT                   = "spi",
	ITEM_MOD_ATTACK_POWER_SHORT             = "ap",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT      = "ap",
	ITEM_MOD_CRIT_RATING_SHORT              = "crit",
	ITEM_MOD_HIT_RATING_SHORT               = "hit",
	ITEM_MOD_HASTE_RATING_SHORT             = "haste",
	ITEM_MOD_EXPERTISE_RATING_SHORT         = "exp",
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arpen",
	ITEM_MOD_SPELL_POWER_SHORT              = "sp",
	ITEM_MOD_BLOCK_VALUE_SHORT              = "blockv",
	RESISTANCE0_NAME                        = "armor",
}

-- TopFit.slots key -> simc field name
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

-- slots that can hold a weapon
local WEAPON_SLOTS = {
	MainHandSlot = true,
	SecondaryHandSlot = true,
	RangedSlot = true,
}

-- ============================================================================
-- EXPOSED GLOBAL MAPPERS (Enables tooltips and script validations)
-- ============================================================================

function TopFit:GetSimcWeaponType(itemLink)
	if not itemLink then return nil end
	local _, _, _, _, _, _, subType = GetItemInfo(itemLink)
	if not subType then return nil end

	subType = subType:lower()
	local isTwoHand = subType:find("two%-handed") ~= nil or subType:find("2h") ~= nil or subType:find("staff") ~= nil or subType:find("polearm") ~= nil

	if subType:find("axe") then return isTwoHand and "axe2h" or "axe" end
	if subType:find("mace") then return isTwoHand and "mace2h" or "mace" end
	if subType:find("sword") then return isTwoHand and "sword2h" or "sword" end
	if subType:find("dagger") then return "dagger" end
	if subType:find("fist") then return "fist" end
	if subType:find("polearm") then return "polearm" end
	if subType:find("staves") or subType:find("staff") then return "staff" end
	if subType:find("crossbow") then return "crossbow" end
	if subType:find("bow") then return "bow" end
	if subType:find("gun") then return "gun" end
	if subType:find("wand") then return "wand" end
	if subType:find("thrown") then return "thrown" end

	return nil
end

-- locale-tolerant "does this line mention damage" check, used to gate the min-max dmg match
-- so we don't accidentally grab an unrelated "12 - 34" style number range from another line
local DAMAGE_KEYWORDS = { "damage", "schaden", "d\195\169g\195\162ts", "da\195\177o", "danno" }
local function ContainsDamageKeyword(text)
	local lower = text:lower()
	for _, kw in ipairs(DAMAGE_KEYWORDS) do
		if lower:find(kw, 1, true) then return true end
	end
	return false
end

-- live, post-haste attack speed for whichever hand is asked for. Only meaningful for melee
-- (main hand / off hand) -- WotLK exposes this straight from the client, no tooltip needed.
-- We do NOT use this as the primary source: simc wants the weapon's BASE speed and applies
-- haste itself, so feeding it an already-hasted number would double-count haste. It's only
-- used to sanity-check (and as a last-resort fallback for) what we parsed from the tooltip.
local function GetLiveMeleeSpeed(slotName)
	if slotName == "MainHandSlot" then
		return (UnitAttackSpeed("player"))
	elseif slotName == "SecondaryHandSlot" then
		local _, off = UnitAttackSpeed("player")
		return off
	end
	return nil
end

-- Parses base weapon speed and damage range straight from the tooltip. WotLK weapons don't
-- expose these via GetItemStats -- they're plain item properties, not "bonus" stats, so the
-- tooltip is the only source. Returns speed, minDmg, maxDmg (any may be nil if unparsable).
-- Shared by the SimC export (simc weapon= line) and by inventory.lua's stat caching (letting
-- weapon speed itself be weighted, e.g. for a spec that wants a slow main hand).
function TopFit:ParseWeaponTooltip(itemLink)
	if not itemLink then return nil end

	local tt = TopFit.scanTooltip or CreateFrame("GameTooltip", "TopFitScanTooltip", nil, "GameTooltipTemplate")
	tt:SetOwner(UIParent, 'ANCHOR_NONE')
	tt:SetHyperlink(itemLink)

	local speed, minDmg, maxDmg
	local numLines = tt:NumLines() or 0

	for i = 1, numLines do
		local leftLine = _G[tt:GetName() .. "TextLeft" .. i]
		local text = leftLine and leftLine:GetText()

		-- Also look at right-aligned text components where WotLK clients often hide speed metrics
		local rightLine = _G[tt:GetName() .. "TextRight" .. i]
		local textRight = rightLine and rightLine:GetText()

		-- Combine texts safely to allow matching across layout structures
		local combinedText = (text or "") .. " " .. (textRight or "")

		if combinedText ~= " " then
			-- 1. Resilient Speed Parser: handles "Speed 2.60", "2.60 Speed", comma-decimal locales
			-- ("Tempo 2,60"), and a couple of common non-English labels. First match wins so a
			-- stray number later in the tooltip (e.g. a proc ICD) can't clobber a good read.
			if not speed then
				local speedMatch = combinedText:match("[Ss]peed%s*([%d,%.]+)")
					or combinedText:match("([%d,%.]+)%s*[Ss]peed")
					or combinedText:match("[Tt]empo%s*([%d,%.]+)")
					or combinedText:match("[Vv]itesse%s*([%d,%.]+)")
					or combinedText:match("[Gg]eschwindigkeit%s*([%d,%.]+)")
				if speedMatch then
					speed = tonumber((speedMatch:gsub(",", ".")))
				end
			end

			-- 2. Damage Boundaries Parser -- anchored to the LEFT line only (the right line can
			-- contain unrelated numbers like a level requirement) and gated on a damage keyword
			-- appearing somewhere on the same line.
			if not minDmg then
				local dmgMin, dmgMax = (text or ""):match("^%s*(%d+)%s*%-%s*(%d+)")
				if dmgMin and ContainsDamageKeyword(text or "") then
					minDmg, maxDmg = tonumber(dmgMin), tonumber(dmgMax)
				end
			end
		end
	end
	tt:Hide()

	return speed, minDmg, maxDmg
end

function TopFit:BuildWeaponField(itemLink, slotName)
	if not itemLink then return nil end

	local simcType = self:GetSimcWeaponType(itemLink)
	if not simcType then return nil end

	local speed, minDmg, maxDmg = self:ParseWeaponTooltip(itemLink)

	-- Melee sanity check: base (tooltip) speed can never be LOWER than the current live speed,
	-- since haste only ever shortens the swing timer. If it is, the tooltip parse grabbed the
	-- wrong number (e.g. matched an unrelated stat) -- distrust it rather than export garbage.
	local liveSpeed = GetLiveMeleeSpeed(slotName)
	if speed and liveSpeed and liveSpeed > 0 and speed < liveSpeed - 0.01 then
		TopFit:Print(("|cffff5555TopFit:|r weapon speed parse for %s looked wrong (tooltip read %.2f, but live speed is %.2f) -- discarding that value."):format(itemLink, speed, liveSpeed))
		speed = nil
	end

	-- Last-resort fallback for melee only: if tooltip parsing failed outright but the weapon is
	-- actually equipped right now, the live speed is a usable (if haste-inflated) stand-in --
	-- better than nothing, and flagged clearly so it gets checked by hand.
	if not speed and liveSpeed and liveSpeed > 0 then
		speed = liveSpeed
		TopFit:Print(("|cffffcc00TopFit:|r couldn't read base weapon speed for %s from its tooltip -- used the current live speed (%.2f) instead. This may include haste; verify before simming."):format(itemLink, liveSpeed))
	end

	if not speed or not minDmg or not maxDmg then
		TopFit:Print(("|cffff5555TopFit:|r could not fully read weapon speed/damage for %s from its tooltip -- weapon= line omitted, fill it in by hand."):format(itemLink))
		return nil
	end

	return ("weapon=%s_%.2fspeed_%dmin_%dmax"):format(simcType, speed, minDmg, maxDmg)
end

-- ============================================================================
-- TEXT FORMATTING HELPERS
-- ============================================================================

local function Slugify(name)
	if not name or name == "" then return "unknown_item" end
	name = name:lower()
	name = name:gsub("'", "")
	name = name:gsub("[^%w]+", "_")
	name = name:gsub("^_+", ""):gsub("_+$", "")
	if name == "" then return "unknown_item" end
	return name
end

local function SlugifyGlyphName(name)
	if not name then return nil end
	name = name:gsub("^[Gg]lyph%s+of%s+", "")
	return Slugify(name)
end

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

local RANGED_TYPE_TO_AMMO_SUBTYPE = {
	bow = "Arrow",
	crossbow = "Arrow",
	gun = "Bullet",
}

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

local function BonusTableToSimcBlob(bonusTable)
	if not bonusTable then return nil end
	local parts = {}
	for stat, value in pairs(bonusTable) do
		local token = STAT_TO_SIMC[stat]
		if token and value and value ~= 0 then
			tinsert(parts, tostring(math.floor(value + 0.5)) .. token)
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "_")
end

-- ============================================================================
-- MAIN SIMC EXPORT ENGINE
-- ============================================================================

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
		
		-- Dynamic Slot Mapping Fallback Engine
		local slotID = TopFit.slots and TopFit.slots[slotName]
		if not slotID then
			if slotName == "MainHandSlot" then slotID = 16
			elseif slotName == "SecondaryHandSlot" then slotID = 17
			elseif slotName == "RangedSlot" then slotID = 18
			end
		end

		local itemLink = slotID and GetInventoryItemLink("player", slotID)

		if itemLink then
			local itemTable = TopFit.GetCachedItem and TopFit:GetCachedItem(itemLink)
			local itemName = GetItemInfo(itemLink) or "Unknown Item"
			local slug = Slugify(itemName)
			local fieldParts = { simcField .. "=" .. slug }

			local statsBlob = itemTable and BonusTableToSimcBlob(itemTable.itemBonus)
			if statsBlob then tinsert(fieldParts, "stats=" .. statsBlob) end

			local gemsBlob = itemTable and BonusTableToSimcBlob(itemTable.gemBonus)
			if gemsBlob then tinsert(fieldParts, "gems=" .. gemsBlob) end

			local enchantBlob = itemTable and BonusTableToSimcBlob(itemTable.enchantBonus)
			if enchantBlob then tinsert(fieldParts, "enchant=" .. enchantBlob) end

			-- Process Weapons configuration payload strings securely
			if WEAPON_SLOTS[slotName] then
				local weaponField = self:BuildWeaponField(itemLink, slotName)
				if weaponField then tinsert(fieldParts, weaponField) end
			end

			if slotName == "RangedSlot" then
				local weaponType = self:GetSimcWeaponType(itemLink)
				if weaponType then
					local ammoDps = GetBestAmmoDps(weaponType)
					if ammoDps then
						tinsert(fieldParts, ("ammo_dps=%.2f"):format(ammoDps))
					end
				end
			end

			tinsert(lines, table.concat(fieldParts, ","))

			local procInfo = itemTable and itemTable.procInfo
			if procInfo then
				if procInfo.trigger == "use" and procInfo.cooldown then
					tinsert(useItemActions, "actions+=/use_item,name=" .. slug)
				else
					local statName = STAT_TO_SIMC[procInfo.statKey] or procInfo.statKey
					local desc = ("%s (%s): +%s %s"):format(itemName, procInfo.trigger, procInfo.amount, statName)
					if procInfo.duration then desc = desc .. (" for %ds"):format(procInfo.duration) end
					if procInfo.cooldown then desc = desc .. (", %ds cooldown"):format(procInfo.cooldown) end
					tinsert(procComments, "#    " .. desc .. " -- proc chance/trigger unknown, verify and encode manually")
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
		local slotID = 16
		if slotName == "SecondaryHandSlot" then slotID = 17
		elseif slotName == "RangedSlot" then slotID = 18 end
		
		local itemLink = GetInventoryItemLink("player", slotID)
		if not itemLink then
			TopFit:Print(slotName .. ": empty")
		else
			local itemName, _, _, _, _, _, subType = GetItemInfo(itemLink)
			local simcType = self:GetSimcWeaponType(itemLink)
			local liveSpeed = GetLiveMeleeSpeed(slotName)
			TopFit:Print(("%s: %s | subType=%s | simcType=%s%s"):format(
				slotName, tostring(itemName), tostring(subType), tostring(simcType),
				liveSpeed and (" | live speed=%.2f"):format(liveSpeed) or ""
			))
			if simcType then
				local field = self:BuildWeaponField(itemLink, slotName)
				TopFit:Print("  Generated Row Fragment: " .. tostring(field))
			end
		end
	end
end

function TopFit:ShowSimcExportDialog()
	local exportString = TopFit:GenerateSimcExportString()
	if not exportString then return end
	StaticPopup_Show('TOPFIT_EXPORT', "Copy this into a .simc file (Ctrl+C):", nil, exportString)
end