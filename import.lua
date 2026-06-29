--[[
	import.lua
	Ported from TopFit 6.0v4's modules/importplugin.class.lua down to the 3.3v6 (WotLK 3.3.5a) codebase.

	Lets you import weight scales from Pawn strings, AskMrRobot-style scale dumps, or TopFit's own
	export strings, and lets you export your current set as a string to share or back up.

	Stripped relative to the retail version: Mastery, MasteryRating, Multistrike, Versatility,
	Avoidance, Amplify, Cleave, Indestructible, Leech, MovementSpeed, BonusArmor (kept folded into Armor).
	None of those stats exist on 3.3.5a items, so there is nothing for them to map to. Leaving a stat
	out of statNameToKey is harmless -- SanitizeScales() silently drops anything it doesn't recognize.

	No locale table exists in this codebase (unlike 6.0v4), so user-facing strings are hardcoded English.
]]

-- this table maps Pawn / AMR / TopFit stat names to the internal weight keys TopFit already
-- uses in presets.lua (these are Blizzard's global-string-derived ITEM_MOD_*/RESISTANCE* keys,
-- identical between this codebase and the 6.0v4 one, so the table ports over essentially unchanged)
local statNameToKey = {
	-- primary stats
	Agility           = 'ITEM_MOD_AGILITY_SHORT',
	Intellect         = 'ITEM_MOD_INTELLECT_SHORT',
	Stamina           = 'ITEM_MOD_STAMINA_SHORT',
	Strength          = 'ITEM_MOD_STRENGTH_SHORT',
	Spirit            = 'ITEM_MOD_SPIRIT_SHORT',

	-- secondary / rating stats that exist in WotLK
	CriticalStrike    = 'ITEM_MOD_CRIT_RATING_SHORT', -- AMR
	CritRating        = 'ITEM_MOD_CRIT_RATING_SHORT', -- Pawn
	Haste             = 'ITEM_MOD_HASTE_RATING_SHORT', -- AMR
	HasteRating       = 'ITEM_MOD_HASTE_RATING_SHORT', -- Pawn
	HitRating         = 'ITEM_MOD_HIT_RATING_SHORT',
	ExpertiseRating   = 'ITEM_MOD_EXPERTISE_RATING_SHORT',
	ArmorPenetration  = 'ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT',
	ResilienceRating  = 'ITEM_MOD_RESILIENCE_RATING_SHORT',
	SpellPenetration  = 'ITEM_MOD_SPELL_PENETRATION_SHORT',
	DefenseRating     = 'ITEM_MOD_DEFENSE_SKILL_RATING_SHORT',
	DodgeRating       = 'ITEM_MOD_DODGE_RATING_SHORT',
	ParryRating       = 'ITEM_MOD_PARRY_RATING_SHORT',
	BlockRating       = 'ITEM_MOD_BLOCK_RATING_SHORT',
	BlockValue        = 'ITEM_MOD_BLOCK_VALUE_SHORT',
	FeralAp           = 'ITEM_MOD_FERAL_ATTACK_POWER_SHORT',
	Hp5               = 'ITEM_MOD_HEALTH_REGENERATION_SHORT',
	Mp5               = 'ITEM_MOD_MANA_REGENERATION_SHORT',

	-- meta / "DPS-style" stats
	MeleeDps          = 'TOPFIT_MELEE_DPS',
	RangedDps         = 'TOPFIT_RANGED_DPS',
	Dps               = 'ITEM_MOD_DAMAGE_PER_SECOND_SHORT',
	Ap                = 'ITEM_MOD_ATTACK_POWER_SHORT', -- Pawn
	AttackPower       = 'ITEM_MOD_ATTACK_POWER_SHORT', -- AMR
	SpellPower        = 'ITEM_MOD_SPELL_POWER_SHORT',
	Armor             = 'RESISTANCE0_NAME',
	Health            = 'ITEM_MOD_HEALTH_SHORT',
	Mana              = 'ITEM_MOD_MANA_SHORT',

	-- resistances
	HolyResist        = 'RESISTANCE1_NAME',
	FireResist        = 'RESISTANCE2_NAME',
	NatureResist      = 'RESISTANCE3_NAME',
	FrostResist       = 'RESISTANCE4_NAME',
	ShadowResist      = 'RESISTANCE5_NAME',
	ArcaneResist      = 'RESISTANCE6_NAME',

	-- armor types
	IsCloth           = 'TOPFIT_ARMORTYPE_CLOTH',
	IsLeather         = 'TOPFIT_ARMORTYPE_LEATHER',
	IsMail            = 'TOPFIT_ARMORTYPE_MAIL',
	IsPlate           = 'TOPFIT_ARMORTYPE_PLATE',
}

local function GetInverseStat(key)
	for pawnStat, statKey in pairs(statNameToKey) do
		if statKey == key then
			return pawnStat
		end
	end
end

-- e.g. ( Pawn: v1: "SetName": Intellect=A, RangedDps=B )
local function ParsePawn(importString)
	local found, _, version, setName, weights = importString:find('^%s*%(%s*Pawn%s*:%s*v(%d+)%s*:%s*"([^"]+)"%s*:%s*(.+)%s*%)%s*$')
	if not found or not version or (setName or '') == '' or (weights or '') == '' then return end

	local scaleTable = {}
	weights:gsub('([^ =]+)=([^ ,]+)', function(stat, weight)
		scaleTable[stat] = tonumber(weight)
	end)
	return setName, scaleTable
end

-- AskMrRobot-style plain scale dump: "StatName -X.XX" per line
local function ParseAMR(importString)
	local weights = importString:trim()
	local setName
	local scaleTable = {}
	weights:gsub('([^ \n]+) -([%d.]+)', function(stat, weight)
		setName = setName or stat
		scaleTable[stat] = tonumber(weight)
	end)
	return setName, scaleTable
end

-- e.g. ( TopFit: v1: "SetName": Intellect=A, RangedDps=B : HitRating=<value>; <isSoftCap>, DefenseRating=[...] )
local function ParseTopFit(importString)
	local found, _, version, setName, remainder = importString:find('^%s*%(%s*TopFit%s*:%s*v(%d+)%s*:%s*"([^"]+)"%s*:%s*(.-)%s*%)%s*$')
	if not found or not version or (setName or '') == '' or (remainder or '') == '' then return end

	-- split the remainder into the weights section and (optionally) the caps section,
	-- using the lazy match so we stop at the FIRST standalone ':' instead of the last one
	local weights, caps = remainder:match('^(.-)%s*:%s*(.*)$')
	if not weights then
		weights, caps = remainder, ''
	end

	local scaleTable = {}
	weights:gsub('([^ =]+)=([^ ,]+)', function(stat, weight)
		scaleTable[stat] = tonumber(weight)
	end)

	local capTable = {}
	caps:gsub('([^ =]+)=([^ ,;]+)%s*;%s*([^ ,;]+)%s*', function(stat, amount, capType)
		local statKey = statNameToKey[stat]
		if statKey then
			capTable[statKey] = {
				value  = tonumber(amount),
				soft   = capType and capType:lower() == 'soft',
				active = true,
			}
		end
	end)

	return setName, scaleTable, capTable
end

-- renames <oldStat> to <newStat>; if <keep> is set, the old key is left in place too
local function RenameStat(scaleTable, oldStat, newStat, keep)
	if scaleTable[oldStat] then
		if not scaleTable[newStat] then scaleTable[newStat] = scaleTable[oldStat] end
		if not keep then scaleTable[oldStat] = nil end
	end
end

-- folds <oldStat> into <newStat>, keeping whichever value is higher
local function CombineStat(scaleTable, newStat, oldStat)
	if scaleTable[oldStat] then
		if scaleTable[newStat] and scaleTable[oldStat] and scaleTable[newStat] < scaleTable[oldStat] then
			scaleTable[newStat] = scaleTable[oldStat]
		end
		scaleTable[oldStat] = nil
	end
end

-- cleans up known Pawn quirks and converts stat names into TopFit's internal weight keys
local function SanitizeScales(scaleTable)
	------------------ Pawn-specific quirks --------------------
	RenameStat(scaleTable, "Resilience", "ResilienceRating")
	RenameStat(scaleTable, "MeleeDPS", "MeleeDps")
	RenameStat(scaleTable, "RangedDPS", "RangedDps")

	-- combine +healing and +damage into spell power
	CombineStat(scaleTable, "SpellPower", "SpellDamage")
	CombineStat(scaleTable, "SpellPower", "Healing")

	-- fold melee/ranged/spell hit, crit, haste into the unified ratings TopFit uses for everyone
	CombineStat(scaleTable, "HitRating", "SpellHitRating")
	CombineStat(scaleTable, "CritRating", "SpellCritRating")
	CombineStat(scaleTable, "HasteRating", "SpellHasteRating")

	-- turn "resist all" into individual resistances
	RenameStat(scaleTable, "AllResist", "FireResist", true)
	RenameStat(scaleTable, "AllResist", "ShadowResist", true)
	RenameStat(scaleTable, "AllResist", "HolyResist", true)
	RenameStat(scaleTable, "AllResist", "NatureResist", true)
	RenameStat(scaleTable, "AllResist", "ArcaneResist", true)
	RenameStat(scaleTable, "AllResist", "FrostResist")

	CombineStat(scaleTable, "Armor", "BonusArmor")
	CombineStat(scaleTable, "Armor", "BaseArmor")

	local returnTable = {}
	for stat, score in pairs(scaleTable) do
		if statNameToKey[stat] then
			returnTable[statNameToKey[stat]] = score
		end
	end

	return returnTable
end

-- imports a Pawn/AMR/TopFit string and creates a new set from it
function TopFit:ImportString(importString)
	local setName, setScores, caps = ParsePawn(importString)
	if not setName then
		setName, setScores, caps = ParseTopFit(importString)
	end
	if not setName then
		setName, setScores = ParseAMR(importString)
	end
	if not setName then
		TopFit:Print("Could not parse the import string. Make sure it's a Pawn, AskMrRobot, or TopFit export string.")
		return nil
	end

	TopFit:AddSet({
		name = setName,
		weights = SanitizeScales(setScores),
		caps = caps or {},
	})
	TopFit:Print(string.format("Imported set \"%s\".", setName))
end

-- exports the currently selected set as a TopFit string (or a Pawn string if pawnFormat is true)
function TopFit:GenerateExportString(pawnFormat)
	local setCode = TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet
	if not setCode or not TopFit.db.profile.sets[setCode] then
		return nil
	end
	local set = TopFit.db.profile.sets[setCode]

	local stats
	for stat, value in pairs(set.weights) do
		local statName = GetInverseStat(stat)
		if statName then
			stats = (stats and stats .. ', ' or '') .. statName .. '=' .. value
		end
	end

	if pawnFormat then
		return (' ( Pawn: v1: "%s": %s ) '):format(set.name, stats or '')
	end

	local caps
	for stat, data in pairs(set.caps) do
		local statName = GetInverseStat(stat)
		if statName and data.active then
			caps = (caps and caps .. ', ' or '') .. statName .. '=' .. data.value .. '; ' .. (data.soft and 'Soft' or 'Hard')
		end
	end
	if caps then stats = (stats or '') .. ' : ' .. caps end

	return (' ( TopFit: v1: "%s": %s ) '):format(set.name, stats or '')
end

StaticPopupDialogs['TOPFIT_IMPORT'] = {
	text = 'Paste a Pawn, AskMrRobot, or TopFit string below to import it as a new set:',
	button1 = 'Import',
	button2 = CANCEL,
	OnAccept = function(self)
		local text = self.editBox:GetText()
		if text and text:trim() ~= '' then
			TopFit:ImportString(text)
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local popup = self:GetParent()
		StaticPopupDialogs['TOPFIT_IMPORT'].OnAccept(popup)
		popup:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	hasEditBox = true,
	editBoxWidth = 260,
}

StaticPopupDialogs['TOPFIT_EXPORT'] = {
	text = '%s',
	button1 = CLOSE,
	OnShow = function(self, data)
		self.editBox:SetText(data or '')
		self.editBox:HighlightText()
		self.editBox:SetFocus()
	end,
	EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	hasEditBox = true,
	editBoxWidth = 260,
}

-- shows the import popup
function TopFit:ShowImportDialog()
	StaticPopup_Show('TOPFIT_IMPORT')
end

-- shows the export popup for the currently selected set
function TopFit:ShowExportDialog(pawnFormat)
	local exportString = TopFit:GenerateExportString(pawnFormat)
	if not exportString then
		TopFit:Print("No set selected to export.")
		return
	end
	StaticPopup_Show('TOPFIT_EXPORT', "Copy this string (Ctrl+C):", nil, exportString)
end
