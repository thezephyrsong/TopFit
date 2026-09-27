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

local function GetItemInfoSafe(item)
	if not item then return nil end
	local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if GetInfo then
		return GetInfo(item)
	end
	return nil
end

local function GetSpellBookItemNameSafe(slotIndex, spellBank)
	if type(slotIndex) ~= "number" then return nil end
	local bank = spellBank
	if not bank or bank == "spell" or bank == BOOKTYPE_SPELL then
		bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"
	end

	if C_SpellBook and C_SpellBook.GetSpellBookItemName then
		return C_SpellBook.GetSpellBookItemName(slotIndex, bank)
	elseif GetSpellBookItemName then
		return GetSpellBookItemName(slotIndex, bank)
	end
	return nil
end

local CLASS_TO_SIMC = {
	WARRIOR     = "warrior",
	PALADIN     = "paladin",
	HUNTER      = "hunter",
	ROGUE       = "rogue",
	PRIEST      = "priest",
	SHAMAN      = "shaman",
	MAGE        = "mage",
	WARLOCK     = "warlock",
	DRUID       = "druid",
}

-- Blizzard's old wowarmory.com talent-calc "cid" (class id) numbering.
-- Death Knight, Evoker, Demon Hunter, Monk removed 2026-09-26 (Dan confirmed): none exist in
-- WoW: Forever. Same correction as CLASS_ARMOR_TYPE in calculation.lua -- these were added
-- speculatively when this class-token map was first ported and that was wrong, not premature.
local CLASS_TO_WOWARMORY_CID = {
	WARRIOR     = 1,
	PALADIN     = 2,
	HUNTER      = 3,
	ROGUE       = 4,
	PRIEST      = 5,
	SHAMAN      = 7,
	MAGE        = 8,
	WARLOCK     = 9,
	DRUID       = 11,
}

-- builds the wowarmory-style "tal=" digit string from your CURRENT live talent allocation.
local function GetWowarmoryTalentString()
	local numTabs = TopFit:GetNumTalentTabsSafe()
	if numTabs == 0 then
		return nil, TopFit.hasClassicTalentAPI and "no_talent_data" or "no_talent_api"
	end
	local digits = {}
	for tab = 1, numTabs do
		for i = 1, TopFit:GetNumTalentsSafe(tab) do
			local currentRank = TopFit:GetTalentRankSafe(tab, i)
			tinsert(digits, tostring(currentRank))
		end
	end
	return table.concat(digits)
end

-- diagnostic talent tracking
function TopFit:DebugTalentCounts()
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local ranksBySpellID, ranksByName = TopFit:GetRetailTalentRanks()
        local count = 0
        TopFit:Print("--- Retail C_ClassTalents / C_Traits Active Nodes ---")
        for spellID, rank in pairs(ranksBySpellID) do
            local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
            local name = spellInfo and spellInfo.name or ("Spell #" .. spellID)
            TopFit:Print(("  %s (ID: %d) -- rank %d"):format(name, spellID, rank))
            count = count + 1
        end
        TopFit:Print("Total active talent nodes found = " .. count)
        return
    end

    local numTabs = TopFit:GetNumTalentTabsSafe()
    if numTabs == 0 then
        TopFit:Print("No classic talent data available.")
        return
    end
    TopFit:Print("GetNumTalentTabs() = " .. tostring(numTabs))
end

local RACE_TO_SIMC = {
	Human       = "human",
	Dwarf       = "dwarf",
	NightElf    = "night_elf",
	Gnome       = "gnome",
	Draenei     = "draenei",
	Orc         = "orc",
	Undead      = "undead",
	Scourge     = "undead",
	Tauren      = "tauren",
	Troll       = "troll",
	BloodElf    = "blood_elf",
	Goblin      = "goblin",
	Pandaren    = "pandaren",
	Nightborne  = "nightborne",
	HighmountainTauren = "highmountain_tauren",
	VoidElf     = "void_elf",
	LightforgedDraenei = "lightforged_draenei",
	ZandalariTroll     = "zandalari_troll",
	KulTiran    = "kul_tiran",
	DarkIronDwarf      = "dark_iron_dwarf",
	Vulpera     = "vulpera",
	Mechagnome  = "mechagnome",
	Dracthyr    = "dracthyr",
	Earthen     = "earthen",
}

-- Detects race based on UnitRace or known racial spells in the player's spellbook
local function GetExportRace()
	local _, raceToken = UnitRace("player")
	if raceToken and RACE_TO_SIMC[raceToken] then
		return RACE_TO_SIMC[raceToken]
	end

	local RACIAL_TO_SIMC = {
		["Blood Fury"] = "orc",
		["Berserking"] = "troll",
		["War Stomp"] = "tauren",
		["Will of the Forsaken"] = "undead",
		["Arcane Torrent"] = "blood_elf",
		["Gift of the Naaru"] = "draenei",
		["Every Man for Himself"] = "human",
		["Stoneform"] = "dwarf",
		["Escape Artist"] = "gnome",
		["Shadowmeld"] = "night_elf",
	}

	local spellBank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "spell"
	local i = 1
	while i <= 500 do
		local spellName = GetSpellBookItemNameSafe(i, spellBank)
		if not spellName then break end
		if RACIAL_TO_SIMC[spellName] then
			return RACIAL_TO_SIMC[spellName]
		end
		i = i + 1
	end

	return (raceToken and raceToken:lower()) or "orc"
end

-- maps internal ITEM_MOD_* keys to this SimC build's short stat tokens
local STAT_TO_SIMC = {
	ITEM_MOD_STRENGTH_SHORT               = "str",
	ITEM_MOD_AGILITY_SHORT                = "agi",
	ITEM_MOD_STAMINA_SHORT                = "sta",
	ITEM_MOD_INTELLECT_SHORT              = "int",
	ITEM_MOD_SPIRIT_SHORT                 = "spi",
	ITEM_MOD_ATTACK_POWER_SHORT           = "ap",
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT    = "ap",
	ITEM_MOD_CRIT_RATING_SHORT            = "crit",
	ITEM_MOD_HIT_RATING_SHORT             = "hit",
	ITEM_MOD_HASTE_RATING_SHORT           = "haste",
	ITEM_MOD_EXPERTISE_RATING_SHORT       = "exp",
	ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arpen",
	ITEM_MOD_SPELL_POWER_SHORT            = "sp",
	ITEM_MOD_BLOCK_VALUE_SHORT            = "blockv",
	RESISTANCE0_NAME                      = "armor",
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
	local _, _, _, _, _, _, subType = GetItemInfoSafe(itemLink)
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

local DAMAGE_KEYWORDS = { "damage", "schaden", "d\195\169g\195\162ts", "da\195\177o", "danno" }
local function ContainsDamageKeyword(text)
	local lower = text:lower()
	for _, kw in ipairs(DAMAGE_KEYWORDS) do
		if lower:find(kw, 1, true) then return true end
	end
	return false
end

local function GetLiveMeleeSpeed(slotName)
	if slotName == "MainHandSlot" then
		return (UnitAttackSpeed("player"))
	elseif slotName == "SecondaryHandSlot" then
		local _, off = UnitAttackSpeed("player")
		return off
	end
	return nil
end

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

		local rightLine = _G[tt:GetName() .. "TextRight" .. i]
		local textRight = rightLine and rightLine:GetText()

		local combinedText = (text or "") .. " " .. (textRight or "")

		if combinedText ~= " " then
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

	local liveSpeed = GetLiveMeleeSpeed(slotName)
	if speed and liveSpeed and liveSpeed > 0 and speed < liveSpeed - 0.01 then
		TopFit:Print(("|cffff5555TopFit:|r weapon speed parse for %s looked wrong (tooltip read %.2f, but live speed is %.2f) -- discarding that value."):format(itemLink, speed, liveSpeed))
		speed = nil
	end

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

function TopFit:Slugify(name)
	if not name or name == "" then return "unknown_item" end
	name = name:lower()
	name = name:gsub("'", "")
	name = name:gsub("[^%w]+", "_")
	name = name:gsub("^_+", ""):gsub("_+$", "")
	if name == "" then return "unknown_item" end
	return name
end
local function Slugify(name) return TopFit:Slugify(name) end

-- CONFIRMED 2026-09-26 (Dan): Forever has no Inscription at all, so there are no glyphs to
-- export -- this isn't an API uncertainty being guarded against anymore, it's a game-design
-- fact. The old glyph-scanning implementation (and its SlugifyGlyphName helper) has been
-- removed entirely rather than left as dead code; this stub exists only so the call site below
-- doesn't need its own separate removal.
local function GetGlyphsString()
	return nil
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
		local leftLine = _G["TFScanTooltipTextLeft" .. i]
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
		local numSlots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, numSlots do
			local itemLink = C_Container.GetContainerItemLink(bag, slot)
			if itemLink then
				local subType = select(7, GetItemInfoSafe(itemLink))
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

-- CONFIRMED 2026-09-26 (Dan): Forever has no Jewelcrafting, so no item will ever have a meta
-- gem (or any gem) socketed. Simplified to a stub rather than left as a loop that can never
-- find anything -- unlike inventory.lua's gem scan, this function is self-contained with a
-- single call site, so it was safe to actually clean up rather than just comment.
local function GetMetaGemSlug(itemLink)
	return nil
end

local function BuildGemsBlob(itemTable)
	if not itemTable then return nil end
	local parts = {}

	if itemTable.itemLink then
		local metaSlug = GetMetaGemSlug(itemTable.itemLink)
		if metaSlug then
			table.insert(parts, metaSlug)
		end
	end

	if itemTable.gemBonus then
		for stat, value in pairs(itemTable.gemBonus) do
			if stat ~= "ITEM_MOD_CRIT_DAMAGE_BONUS_SHORT" then
				local token = STAT_TO_SIMC[stat]
				if token and value and value ~= 0 then
					table.insert(parts, tostring(math.floor(value + 0.5)) .. token)
				end
			end
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

	local simcRace = GetExportRace()

	local lines = {}
	tinsert(lines, simcClass .. "=" .. (UnitName("player") or "Unknown"))
	tinsert(lines, "origin=\"Exported from TopFit\"")
	tinsert(lines, "level=" .. UnitLevel("player"))
	if simcRace then
		tinsert(lines, "race=" .. simcRace)
	end

	local cid = CLASS_TO_WOWARMORY_CID[classToken]
	local talString, talError = GetWowarmoryTalentString()
	if talError == "no_talent_data" then
		TopFit:Print("Could not read talent data for the export -- open your Talent panel (default key: N) once this session, then try exporting again.")
	elseif cid and talString and talString ~= "" then
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
			local itemName = GetItemInfoSafe(itemLink) or "Unknown Item"
			local slug = Slugify(itemName)
			local fieldParts = { simcField .. "=" .. slug }

			local statsBlob = itemTable and BonusTableToSimcBlob(itemTable.itemBonus)
			if statsBlob then tinsert(fieldParts, "stats=" .. statsBlob) end

			local gemsBlob = itemTable and BuildGemsBlob(itemTable)
			if gemsBlob then tinsert(fieldParts, "gems=" .. gemsBlob) end

			local enchantBlob = itemTable and BonusTableToSimcBlob(itemTable.enchantBonus)
			if enchantBlob then tinsert(fieldParts, "enchant=" .. enchantBlob) end

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
	tinsert(lines, "#    heroic=1 flags")
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
			local itemName, _, _, _, _, _, subType = GetItemInfoSafe(itemLink)
			local simcType = self:GetSimcWeaponType(itemLink)
			local liveSpeed = GetLiveMeleeSpeed(slotName)
			TopFit:Print(("%s: %s | subType=%s | simcType=%s%s"):format(
				slotName, tostring(itemName), tostring(subType), tostring(simcType),
				liveSpeed and (" | live speed=%.2f"):format(liveSpeed) or ""
			))
			if simcType then
				local field = self:BuildWeaponField(itemLink, slotName)
				TopFit:Print("   Generated Row Fragment: " .. tostring(field))
			end
		end
	end
end

function TopFit:ShowSimcExportDialog()
	local exportString = TopFit:GenerateSimcExportString()
	if not exportString then return end
	StaticPopup_Show('TOPFIT_EXPORT', "Copy this into a .simc file (Ctrl+C):", nil, exportString)
end