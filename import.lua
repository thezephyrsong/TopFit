--[[
	import.lua
	Ported from TopFit 6.0v4's modules/importplugin.class.lua.

	Lets you import weight scales from Pawn strings, AskMrRobot-style scale dumps, or TopFit's own
	export strings, and lets you export your current set as a string to share or back up.

	Stripped relative to the retail version: Mastery, MasteryRating, Multistrike, Versatility,
	Avoidance, Amplify, Cleave, Indestructible, Leech, MovementSpeed, BonusArmor (kept folded into Armor).
	None of those stats exist on Forever items, so there is nothing for them to map to. Leaving a stat
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

	-- Pawn's rating-named stats, mapped 1:1 onto TopFit's percent stats (Dan, 2026-10-10: stay
	-- compatible with Pawn so imports/exports keep working with Pawn on Forever). This is Pawn's own
	-- Classic convention: it parses a "+1.0%" tooltip line straight into 1 point of the rating-named
	-- stat (CritPercent -> CritRating, Hit -> HitRating, DodgePercent -> DodgeRating, ParryPercent ->
	-- ParryRating, BlockPercent -> BlockRating, HasteClassic -> HasteRating, ExpertiseClassic ->
	-- ExpertiseRating, DefenseSkill -> DefenseRating; see Pawn's TooltipParsing.lua). So a Pawn
	-- weight is already "per 1%" and needs NO rating conversion -- TopFit.RATING_PER_PERCENT must not
	-- be applied here. Armor penetration and resilience stay unmapped: no Forever item
	-- has either. Spell* variants (SpellHitRating etc.) are left unmapped on purpose: Pawn folds them
	-- into the plain names for non-casters, and mapping two Pawn names onto one TopFit key would make
	-- the winner depend on table order.
	HitRating         = 'TOPFIT_HIT_CHANCE_ALL',
	CritRating        = 'TOPFIT_CRIT_CHANCE_ALL',
	HasteRating       = 'TOPFIT_HASTE_PERCENT',
	DodgeRating       = 'TOPFIT_DODGE_CHANCE_ALL',
	ParryRating       = 'TOPFIT_PARRY_CHANCE_ALL',
	BlockRating       = 'TOPFIT_BLOCK_CHANCE_ALL',
	ExpertiseRating   = 'TOPFIT_DODGE_PARRY_REDUCTION',
	DefenseRating     = 'TOPFIT_DEFENSE_FLAT',
	SpellPenetration  = 'ITEM_MOD_SPELL_PENETRATION_SHORT',
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
	Rap               = 'ITEM_MOD_RANGED_ATTACK_POWER_SHORT', -- Pawn -- added 2026-09-27 alongside core.lua's new stat
	-- SpellPower removed 2026-09-27, alongside removing ITEM_MOD_SPELL_POWER_SHORT from
	-- core.lua's statList (see below): Forever confirmed to not itemize a unified spell
	-- power stat at all, so Pawn's SpellDamage/Healing now map directly to TopFit's own
	-- flat stats instead of folding into a stat this client never grants.
	SpellDamage       = 'TOPFIT_SPELL_DAMAGE_FLAT',
	Healing           = 'TOPFIT_SPELL_HEALING_FLAT',
	-- per-school spell damage (Pawn's own names) -- added 2026-10-10, matching the per-school flat
	-- stats confirmed on real Forever gear (procparser.lua)
	ArcaneSpellDamage = 'TOPFIT_ARCANE_DAMAGE_FLAT',
	FireSpellDamage   = 'TOPFIT_FIRE_DAMAGE_FLAT',
	FrostSpellDamage  = 'TOPFIT_FROST_DAMAGE_FLAT',
	HolySpellDamage   = 'TOPFIT_HOLY_DAMAGE_FLAT',
	NatureSpellDamage = 'TOPFIT_NATURE_DAMAGE_FLAT',
	ShadowSpellDamage = 'TOPFIT_SHADOW_DAMAGE_FLAT',
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
	-- "...Resistance" spelling used by WowSims-style exports (same stats as the "...Resist" names)
	HolyResistance    = 'RESISTANCE1_NAME',
	FireResistance    = 'RESISTANCE2_NAME',
	NatureResistance  = 'RESISTANCE3_NAME',
	FrostResistance   = 'RESISTANCE4_NAME',
	ShadowResistance  = 'RESISTANCE5_NAME',
	ArcaneResistance  = 'RESISTANCE6_NAME',

	-- armor types
	IsCloth           = 'TOPFIT_ARMORTYPE_CLOTH',
	IsLeather         = 'TOPFIT_ARMORTYPE_LEATHER',
	IsMail            = 'TOPFIT_ARMORTYPE_MAIL',
	IsPlate           = 'TOPFIT_ARMORTYPE_PLATE',

	-- WoW: Forever / pre-rating itemization pseudo-stats (see procparser.lua's
	-- ParsePermanentStatLine and core.lua's TopFit.statList for where these come from).
	-- Pawn's own stat table (checked against a real 2.13.16 install) has no percent-chance
	-- hit/crit/dodge-parry keys to map from -- its rating-era stat table doesn't model them
	-- -- so these only round-trip through TopFit's own export format, not Pawn's, until/
	-- unless Pawn adds equivalents. Included here (rather than a separate table) so a
	-- Pawn-format import that happens to contain one of these names for some other reason
	-- doesn't silently misinterpret it.
	TopfitHitChanceAll      = 'TOPFIT_HIT_CHANCE_ALL',
	TopfitCritChanceAll     = 'TOPFIT_CRIT_CHANCE_ALL',
	TopfitCritChanceMelee   = 'TOPFIT_CRIT_CHANCE_MELEE',
	TopfitCritChanceRanged  = 'TOPFIT_CRIT_CHANCE_RANGED',
	TopfitCritChanceSpell   = 'TOPFIT_CRIT_CHANCE_SPELL',
	TopfitDodgeParryReduction = 'TOPFIT_DODGE_PARRY_REDUCTION',
	TopfitDefenseFlat       = 'TOPFIT_DEFENSE_FLAT',
}

-- Several names can map to one key (Pawn's HitRating and TopFit's own TopfitHitChanceAll both mean
-- TOPFIT_HIT_CHANCE_ALL). On export prefer Pawn's name so the string stays importable by Pawn, and
-- break ties alphabetically so the result never depends on table iteration order.
local function GetInverseStat(key)
	local best
	for pawnStat, statKey in pairs(statNameToKey) do
		if statKey == key then
			local isTopfitName = pawnStat:sub(1, 6) == "Topfit"
			local bestIsTopfit = best and best:sub(1, 6) == "Topfit"
			if not best
				or (bestIsTopfit and not isTopfitName)
				or (bestIsTopfit == isTopfitName and pawnStat < best) then
				best = pawnStat
			end
		end
	end
	return best
end

-- e.g. ( Pawn: v1: "SetName": Intellect=A, RangedDps=B )
local function ParsePawn(importString)
	local found, _, version, setName, weights = importString:find('^%s*%(%s*Pawn%s*:%s*v(%d+)%s*:%s*"([^"]+)"%s*:%s*(.+)%s*%)%s*$')
	if not found or not version or (setName or '') == '' or (weights or '') == '' then return end

	local scaleTable = {}
	weights:gsub('([^ =,]+)=([^ ,]+)', function(stat, weight)
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
	weights:gsub('([^ =,]+)=([^ ,]+)', function(stat, weight)
		scaleTable[stat] = tonumber(weight)
	end)

	local capTable = {}
	caps:gsub('([^ =,;]+)=([^ ,;]+)%s*;%s*([^ ,;]+)%s*', function(stat, amount, capType)
		local statKey = statNameToKey[stat]
		if statKey then
			capTable[statKey] = capTable[statKey] or {}
			tinsert(capTable[statKey], {
				value  = tonumber(amount),
				soft   = capType and capType:lower() == 'soft',
				active = true,
			})
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
	-- Resilience->ResilienceRating rename removed 2026-09-27 -- ResilienceRating is no
	-- longer in statNameToKey above, so this rename would just relabel a value that then
	-- gets dropped anyway (see that table's comment for why).
	RenameStat(scaleTable, "MeleeDPS", "MeleeDps")
	RenameStat(scaleTable, "RangedDPS", "RangedDps")

	-- RESOLVED 2026-09-27: the old SpellPower fold that used to live here is gone -- Forever
	-- is confirmed to have no unified spell power stat, so SpellDamage/Healing now map
	-- directly (see statNameToKey above) instead of folding into one that doesn't exist.

	-- HitRating/CritRating/HasteRating folds removed 2026-09-27 (see the Spell* note above); all three
	-- destinations are gone now (see statNameToKey above), so folding their Spell*
	-- counterparts into them would just combine values on their way to being dropped.

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

-- Which existing set should a (re-)imported weight string update? A set with the same name wins (importing
-- "Hunter" again means that set); otherwise the set that is currently selected, i.e. the one being used.
local function FindSetToUpdate(importName)
	local sets = TopFit.db.profile.sets
	local wanted = importName and importName:lower()
	if wanted then
		for code, set in pairs(sets) do
			if set.name and set.name:lower() == wanted then return code end
		end
	end
	local selected = TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet
	if selected and sets[selected] then return selected end
end

-- Replaces the weights of an existing set with freshly imported ones. A re-import is a complete new weight
-- vector, so stats the import doesn't mention drop out -- except the per-set bonus weights ("SET: <name>"), which
-- are added by hand in the weights tab and never appear in an external string. Caps are only touched when the
-- import carries some (a Pawn / AskMrRobot string has none). The set's name, forced items and its
-- weightsAssumeFullTalents setting stay as they were.
function TopFit:UpdateSetWeights(setCode, weights, caps)
	local set = self.db.profile.sets[setCode]
	if not set then return false end

	local newWeights = {}
	for stat, value in pairs(weights) do newWeights[stat] = value end
	for stat, value in pairs(set.weights or {}) do
		if type(stat) == "string" and stat:find("^SET: ") and newWeights[stat] == nil then
			newWeights[stat] = value
		end
	end
	set.weights = newWeights
	if caps and next(caps) then set.caps = caps end

	self:CalculateScores()
	if self.eventHandler then self.eventHandler:Fire("OnSetChanged", setCode) end
	return true
end

local function CreateImportedSet(name, weights, caps)
	TopFit:AddSet({ name = name, weights = weights, caps = caps or {} })
	TopFit:Print(string.format("Imported set \"%s\".", name))
end

-- imports a Pawn/AMR/TopFit string: updates the set being used (or the one with the same name) after asking,
-- or creates a new set
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

	local weights = SanitizeScales(setScores)
	local targetCode = FindSetToUpdate(setName)
	if not targetCode then
		CreateImportedSet(setName, weights, caps)   -- nothing to update (first set, or none selected)
		return
	end

	StaticPopup_Show('TOPFIT_IMPORT_UPDATE', TopFit.db.profile.sets[targetCode].name, setName,
		{ importName = setName, weights = weights, caps = caps, targetCode = targetCode })
end

StaticPopupDialogs['TOPFIT_IMPORT_UPDATE'] = {
	-- %s #1 = the set that would be updated, %s #2 = the name inside the imported string (plain %s, no positional
	-- arguments, so it formats the same everywhere)
	text = 'Replace the weights of your set "%s" with the imported weights for "%s", or create a new set?',
	button1 = 'Update set',
	button2 = CANCEL,
	button3 = 'New set',
	OnAccept = function(self, data)
		data = data or self.data
		if not data then return end
		local set = TopFit.db.profile.sets[data.targetCode]
		if set and TopFit:UpdateSetWeights(data.targetCode, data.weights, data.caps) then
			TopFit:Print(string.format("Updated the weights of \"%s\" from the import.", set.name))
		else
			TopFit:Print("That set no longer exists; nothing was updated.")
		end
	end,
	OnAlt = function(self, data)
		data = data or self.data
		if data then CreateImportedSet(data.importName, data.weights, data.caps) end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

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
	for stat, capList in pairs(set.caps) do
		local statName = GetInverseStat(stat)
		if statName then
			for _, data in ipairs(capList) do
				if data.active then
					caps = (caps and caps .. ', ' or '') .. statName .. '=' .. data.value .. '; ' .. (data.soft and 'Soft' or 'Hard')
				end
			end
		end
	end
	if caps then stats = (stats or '') .. ' : ' .. caps end

	return (' ( TopFit: v1: "%s": %s ) '):format(set.name, stats or '')
end

-- EditBox (capital E) confirmed 2026-09-27 via an in-game crash: this client's StaticPopup
-- frames use PascalCase field names (EditBox, not the old lowercase editBox this codebase used
-- to reference), part of the same UI modernization as the Settings namespace / BackdropTemplate
-- requirement found elsewhere in this project.
StaticPopupDialogs['TOPFIT_IMPORT'] = {
	text = 'Paste a Pawn, AskMrRobot, or TopFit string below. You can then update the set you are using with its weights, or import it as a new set:',
	button1 = 'Import',
	button2 = CANCEL,
	OnAccept = function(self)
		local text = self.EditBox:GetText()
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
		self.EditBox:SetText(data or '')
		self.EditBox:HighlightText()
		self.EditBox:SetFocus()
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
