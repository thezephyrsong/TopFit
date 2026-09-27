--[[
	procparser.lua
	Scans an item's tooltip for "Use:" and "Equip:" proc effects, extracts the stat, amount,
	buff duration, and (when stated) cooldown, and turns that into an effective-average stat
	value TopFit's existing weight-based scoring can use directly.

	WHY THIS EXISTS:
	  1. In-game scoring: a trinket with "Equip: Chance on hit to grant 1000 attack power for
	     10 sec" currently scores ONLY on its flat passive stats -- the proc is invisible to
	     TopFit's math. This folds a conservative estimate of the proc's value into the item's
	     totalBonus so your weights actually account for it.
	  2. SimC export: feeds the parsed numbers into simc_export.lua's equip=/use= field.

	HONEST LIMITS (please read before trusting the numbers):
	  - Click-to-use trinkets (Use: ... (X Cooldown)) are scored reliably: amount * duration/cooldown
	    is a correct expected-value uptime estimate IF the player uses it on cooldown.
	  - Passive on-equip "chance on hit/cast" procs are the hard case. WotLK-era tooltips
	    essentially never state the actual proc chance or internal cooldown as parseable text --
	    that information was historically reverse-engineered by the community (PPM testing),
	    not exposed by the client. Without it, true uptime cannot be derived from the tooltip.
	    When no cooldown/chance is found in the text, this module does NOT fabricate a number:
	    it stores the raw parsed stat/amount/duration as itemTable.procInfo and sets
	    itemTable.hasUnscoredProc = true, but contributes NOTHING to totalBonus. This is checked
	    in testing -- it would be worse to silently invent a precise-looking number that's
	    actually a guess than to leave it out and flag it.
	  - If you want an unscored proc counted, the cleanest path is TopFit's existing "virtual
	    items" plugin: add the proc's stat/amount there with your own uptime assumption.

	SIMC EXPORT CAVEAT (see simc_export.lua): this engine's equip= format also encodes a
	*trigger event* (onattackhit / onspellcast / onspelldamage / onspelltickdamage / etc.)
	which cannot be reliably inferred from tooltip text -- two procs that read identically in
	the tooltip can fire on different events. The exporter emits a best-guess comment, not an
	authoritative equip= line, for exactly this reason.

	2026-07-09: added detection for weapon "Chance on hit:" procs (Dragonstrike, Lionheart
	Executioner, The Night Blade, etc.) -- these use a distinct tooltip prefix instead of
	"Equip:" and were previously invisible to this scanner entirely. Tagged with the same
	trigger = "equip" label as ordinary equip procs since they share the same simc_proc_data.lua
	section and downstream export handling. Also fixed a case-sensitivity bug in
	ParseStatAndAmount: proc *sentences* use natural lowercase phrasing ("...your haste rating
	by 127...") while the stat name table holds the title-case short-form display string ("Haste
	Rating"), so matching previously failed silently for every such line, not just weapon procs.
]]

-- locale-safe trigger-line prefixes, identical technique to the existing socket-bonus scan
local USE_PREFIX = _G["ITEM_SPELL_TRIGGER_ONUSE"]     -- "Use:" in enUS
local EQUIP_PREFIX = _G["ITEM_SPELL_TRIGGER_ONEQUIP"] -- "Equip:" in enUS
local CHANCE_PREFIX = _G["ITEM_SPELL_TRIGGER_ONPROC"] -- "Chance on hit:" in enUS -- weapon "chance on hit" procs
                                                       -- (Dragonstrike, Lionheart Executioner, etc.) use this distinct
                                                       -- prefix instead of "Equip:" and were previously invisible to
                                                       -- this scanner entirely. Confirmed in-game 2026-07-09.

-- builds a flat {statKey -> localized stat name} lookup from TopFit's existing statList,
-- reused as-is from the same table the socket-bonus scanner already relies on
local function GetStatNameTable()
	local statNames = {}
	for _, sTable in pairs(TopFit.statList) do
		for _, statKey in pairs(sTable) do
			local name = _G[statKey]
			if name then
				statNames[statKey] = name
			end
		end
	end
	return statNames
end

-- tries to find "<number> <cooldown>" text, e.g. "2 Min Cooldown", "45 Sec Cooldown".
-- returns the cooldown in seconds, or nil if no such phrase is present.
local function ParseCooldownSeconds(text)
	local mins = text:match("(%d+)%s*Min[^%a]*Cooldown")
	local secs = text:match("(%d+)%s*Sec[^%a]*Cooldown")
	if mins or secs then
		return (tonumber(mins) or 0) * 60 + (tonumber(secs) or 0)
	end
	return nil
end

-- tries to find "for <number> sec" duration text. Returns seconds, or nil.
local function ParseDurationSeconds(text)
	local secs = text:match("for%s+(%d+)%s*sec")
	if secs then return tonumber(secs) end
	-- some effects phrase it as "<number> sec" without "for", try a looser fallback
	secs = text:match("(%d+)%s*sec")
	if secs then return tonumber(secs) end
	return nil
end

-- given a line of tooltip text, finds which known stat it refers to and the number tied to it.
-- WoW's Use:/Equip: sentence text is NOT consistently ordered -- some effects read
-- "grants 1000 Attack Power" (number then stat) and others "Increases Attack Power by 1200"
-- (stat then number), so both orderings are tried for every known stat name.
-- NOTE: proc *sentences* ("Increases your haste rating by 127...") use natural lowercase
-- phrasing, while the stat name table holds the title-case short-form display string ("Haste
-- Rating", as used in "+15 Haste Rating" stat lines). Matching is done case-insensitively so
-- one doesn't silently fail against the other -- confirmed via real tooltip text 2026-07-09
-- (Dragonstrike's "haste rating" line did not match "Haste Rating" case-sensitively).
local function ParseStatAndAmount(text, statNames)
	local lowerText = text:lower()
	for statKey, statName in pairs(statNames) do
		local escapedName = statName:gsub("%%", "%%%%"):lower()

		-- order 1: "<number> <statName>" (e.g. "grants 1000 Attack Power")
		local amount = lowerText:match("([%d,]+)%s*" .. escapedName)
		-- order 2: "<statName> ... <number>" with only "by "/"to " words allowed between
		-- (e.g. "Increases Attack Power by 1200", "Attack Power by 1,200")
		if not amount then
			amount = lowerText:match(escapedName .. "%s*[%a]*%s*[%a]*%s*([%d,]+)")
		end

		if amount then
			amount = tonumber((amount:gsub(",", "")))
			if amount then
				return statKey, amount
			end
		end
	end
	return nil
end

-- Decodes one of simc's compact proc-effect strings (see simc_proc_data.lua's header for the
-- grammar) into a structured table: { trigger, stat, amount, procChance, procPPM, duration,
-- cooldown, maxStack, tick, reverse }. Any field absent from the string is left nil. Returns an
-- empty table (not nil) for unparseable/marker strings like "custom" (DK runeforges) so callers
-- can treat "found nothing useful" uniformly rather than needing a separate nil check.
function TopFit:DecodeSimcEffectString(str)
	if not str or str == "" then return {} end

	local tokens = {}
	for tok in str:gmatch("[^_]+") do
		tinsert(tokens, tok)
	end
	if #tokens == 0 then return {} end

	local result = {}
	local idx = 1

	-- Trigger type (e.g. "OnAttackHit") -- absent for get_use_encoding's simple activated
	-- trinkets, which have no proc trigger at all (player activates them directly).
	if tokens[1]:match("^On%u") then
		result.trigger = tokens[1]
		idx = 2
	end

	-- Amount + Stat/School is always the next token, e.g. "612ArPen", "8SP", "1880Arcane"
	if tokens[idx] then
		local amount, stat = tokens[idx]:match("^([%d%.]+)(%a+)$")
		if amount then
			result.amount = tonumber(amount)
			result.stat = stat
			idx = idx + 1
		end
	end

	-- Remaining tokens (chance%, PPM, Stack, Dur, Cd, Tick, reverse) can appear in varying
	-- order across entries, so match each token independently instead of assuming positions.
	for i = idx, #tokens do
		local tok = tokens[i]
		if tok == "reverse" then
			result.reverse = true
		else
			local pct = tok:match("^([%d%.]+)%%$")
			if pct then
				result.procChance = tonumber(pct)
			else
				local num, suffix = tok:match("^([%d%.]+)(%a+)$")
				if num and suffix then
					num = tonumber(num)
					if suffix == "PPM" then result.procPPM = num
					elseif suffix == "Stack" then result.maxStack = num
					elseif suffix == "Dur" then result.duration = num
					elseif suffix == "Cd" then result.cooldown = num
					elseif suffix == "Tick" then result.tick = num
					end
				end
			end
		end
	end

	return result
end

-- Looks up itemLink's name against simc's extracted proc database (simc_proc_data.lua),
-- preferring the "normal" variant over "heroic" since we don't independently know which
-- quality tier a given Triumvirate item corresponds to. Returns a decoded table, or nil if
-- there's no entry under this trigger's section for this item name.
function TopFit:LookupSimcProcData(itemLink, section)
	if not itemLink or not TopFit.SimcProcData or not TopFit.SimcProcData[section] then return nil end
	local name = C_Item.GetItemInfo(itemLink)
	if not name then return nil end

	local entry = TopFit.SimcProcData[section][TopFit:Slugify(name)]
	if not entry then return nil end

	local raw = entry.normal or entry.heroic
	if not raw then return nil end
	return TopFit:DecodeSimcEffectString(raw)
end

-- ============================================================================
-- Flat/percent "Equip:" passive stats (pre-WotLK-rating itemization model)
--
-- WoW: Forever's confirmed itemization (from real item tooltips, and from
-- WoW: Forever's own talent text -- e.g. Shaman's Thundering Strikes/Tidal
-- Focus use these exact same templates) expresses hit/crit/dodge-parry-
-- reduction/weapon-skill/spell-power as plain on-equip spell text, NOT as
-- GetItemStats() ITEM_MOD_* rating stats. These bonuses are invisible to
-- inventory.lua's GetItemStats() call entirely. This section extracts them
-- from tooltip text into TopFit's own namespaced stat keys (matching the
-- existing TOPFIT_WEAPON_SPEED convention in inventory.lua).
--
-- Templates confirmed from live Season of Discovery/Classic item and talent
-- text (Forever wording not yet confirmed independently -- verify against
-- real Forever tooltips once beta is up, per REWRITE_PLAN_12_1_5.md):
--   "Improves your chance to hit with all spells and attacks by N%."
--   "Improves your chance to get a critical strike with all spells and
--    attacks by N%." / "...with melee attacks by N%." / "...with spells
--    by N%." (melee/ranged/spell variants seen as separate lines too)
--   "Reduces the chance for your attacks to be dodged or parried by N%."
--   "Reduces chance to be dodged or parried by N%." (shorter variant seen
--    in the WoW: Forever Items & Gear panel specifically)
--   "Increased Defense +N." / "Increased Swords +N." (flat, per weapon type)
--   "Increases healing done by up to X and damage done by up to Y for all
--    magical spells and effects." (one line, two stats)
-- ============================================================================

TopFit.PermanentPercentStatPatterns =
{
	-- combined hit
	{ pattern = "improves your chance to hit with all spells and attacks by ([%d%.]+)%%",
	  statKey = "TOPFIT_HIT_CHANCE_ALL" },
	-- combined crit
	{ pattern = "improves your chance to get a critical strike with all spells and attacks by ([%d%.]+)%%",
	  statKey = "TOPFIT_CRIT_CHANCE_ALL" },
	-- split crit variants (melee/ranged/spell as separate lines)
	{ pattern = "improves your chance to get a critical strike with melee attacks by ([%d%.]+)%%",
	  statKey = "TOPFIT_CRIT_CHANCE_MELEE" },
	{ pattern = "improves your chance to get a critical strike with ranged attacks by ([%d%.]+)%%",
	  statKey = "TOPFIT_CRIT_CHANCE_RANGED" },
	{ pattern = "improves your chance to get a critical strike with spells by ([%d%.]+)%%",
	  statKey = "TOPFIT_CRIT_CHANCE_SPELL" },
	-- dodge/parry reduction -- tolerate both the longer Classic/SoD wording and the
	-- shorter wording seen in the WoW: Forever Items & Gear panel
	{ pattern = "reduces the chance for your attacks to be dodged or parried by ([%d%.]+)%%",
	  statKey = "TOPFIT_DODGE_PARRY_REDUCTION" },
	{ pattern = "reduces chance to be dodged or parried by ([%d%.]+)%%",
	  statKey = "TOPFIT_DODGE_PARRY_REDUCTION" },
	-- parry / block chance -- added 2026-09-26, phrasing inferred by consistency with the
	-- confirmed beta-client talent text ("Increases your Parry chance by N%.", Warrior's
	-- Deflection/Shield Specialization) and the established Equip: phrasing family above, NOT
	-- yet confirmed against a real item tooltip. Flag and correct if actual gear text differs.
	{ pattern = "increases your parry chance by ([%d%.]+)%%",
	  statKey = "TOPFIT_PARRY_CHANCE_ALL" },
	{ pattern = "increases your chance to block by ([%d%.]+)%%",
	  statKey = "TOPFIT_BLOCK_CHANCE_ALL" },
	-- dodge chance, spell hit chance, "physical" (all-attacks-no-spell) crit -- added 2026-09-26
	-- from the same full class talent data pass. Same caveat as parry/block above: phrasing
	-- inferred by consistency with confirmed talent text, not yet seen on a real item tooltip.
	{ pattern = "increases your chance to dodge by ([%d%.]+)%%",
	  statKey = "TOPFIT_DODGE_CHANCE_ALL" },
	{ pattern = "improves your chance to hit with %a+ spells by ([%d%.]+)%%",
	  statKey = "TOPFIT_HIT_CHANCE_SPELL" },
	{ pattern = "improves your chance to get a critical strike with all attacks by ([%d%.]+)%%",
	  statKey = "TOPFIT_CRIT_CHANCE_PHYSICAL" },
	-- dual-stat spell healing/damage line -- two captures, handled specially below
	{ pattern = "increases healing done by up to (%d+) and damage done by up to (%d+) for all magical spells and effects",
	  dualStatKeys = { "TOPFIT_SPELL_HEALING_FLAT", "TOPFIT_SPELL_DAMAGE_FLAT" } },
}

-- flat "Increased <WeaponType/Defense> +N" lines -- no % sign, no "chance" word, so these
-- were never at risk of the proc misclassification, but still invisible to GetItemStats()
local FLAT_INCREASED_PATTERN = "^increased (%a+) %+(%d+)%.?$"

-- given one line of tooltip text, returns a table of {statKey = amount, ...} for every
-- known permanent flat/percent stat pattern it matches, or nil if none matched. A single
-- line can match more than one entry only for the dual-stat healing/damage template.
function TopFit:ParsePermanentStatLine(text)
	if not text then return nil end
	local lower = text:lower()

	for _, entry in ipairs(TopFit.PermanentPercentStatPatterns) do
		if entry.dualStatKeys then
			local a, b = lower:match(entry.pattern)
			if a and b then
				return { [entry.dualStatKeys[1]] = tonumber(a), [entry.dualStatKeys[2]] = tonumber(b) }
			end
		else
			local amount = lower:match(entry.pattern)
			if amount then
				return { [entry.statKey] = tonumber(amount) }
			end
		end
	end

	local weaponOrDefense, flatAmount = lower:match(FLAT_INCREASED_PATTERN)
	if weaponOrDefense and flatAmount then
		local statKey
		if weaponOrDefense == "defense" then
			statKey = "TOPFIT_DEFENSE_FLAT"
		else
			statKey = "TOPFIT_WEAPON_SKILL_" .. weaponOrDefense:upper()
		end
		return { [statKey] = tonumber(flatAmount) }
	end

	return nil
end

-- scans itemLink's full tooltip for every permanent flat/percent stat line (see above) and
-- returns a merged {statKey = amount, ...} table (empty table, not nil, if none found -- so
-- callers can merge it into an item's stat table unconditionally). Unlike ParseItemProc,
-- this is not limited to a single matched line: an item can have both a percent stat
-- (e.g. "Increased chance to hit") AND a flat one (e.g. "Increased Defense +21") as separate
-- Equip: lines, and both need to be captured.
function TopFit:ScanItemPermanentPercentStats(itemLink)
	local result = {}
	if not itemLink then return result end

	TopFit.scanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	TopFit.scanTooltip:SetHyperlink(itemLink)
	local numLines = TopFit.scanTooltip:NumLines()

	for i = 1, numLines do
		local leftLine = getglobal("TFScanTooltip" .. "TextLeft" .. i)
		local leftLineText = leftLine and leftLine:GetText()
		if leftLineText then
			local matched = TopFit:ParsePermanentStatLine(leftLineText)
			if matched then
				for statKey, amount in pairs(matched) do
					result[statKey] = amount
				end
			end
		end
	end
	TopFit.scanTooltip:Hide()

	return result
end

-- distinguishes an actual chance/triggered effect line from an ordinary flat, always-on
-- "Equip: +N Stat" passive bonus. Both use the identical "Equip:" tooltip prefix in WoW's UI,
-- but only a genuine proc/triggered effect will either say "chance" (the overwhelming majority
-- of phrasing: "have a chance to...", "Chance on hit:...") or state a buff duration ("for N
-- sec") -- a flat passive stat is permanent while worn and does neither. Without this filter,
-- literally every item with a secondary-stat Equip: line (the majority of rare+ gear) gets
-- misidentified as having an unparsed proc. Found 2026-07-11 after the case-sensitivity fix
-- made stat/amount extraction succeed on these flat lines too, which had been silently masking
-- this pre-existing ambiguity.
--
-- UPDATED 2026-09-16: the "chance" heuristic alone is wrong for WoW: Forever/pre-rating
-- itemization -- permanent stats like "Improves your chance to hit..." and "Reduces chance
-- to be dodged or parried..." use the word "chance" in ordinary phrasing while being just as
-- permanent as a flat "+N Stat" line. Check against the known permanent-stat templates
-- (see ParsePermanentStatLine above) BEFORE falling back to the generic "chance" check, so
-- these don't get misrouted into the proc path and silently scored as zero.
local function LooksLikeTriggeredEffect(text)
	if TopFit:ParsePermanentStatLine(text) then return false end
	local lower = text:lower()
	if lower:find("chance") then return true end
	if text:match("for%s+%d+%s*sec") then return true end
	return false
end

-- scans itemLink's tooltip for a Use:/Equip: proc line and parses it.
-- returns a table: { trigger = "use"/"equip", statKey, amount, duration, cooldown (or nil) }
-- or nil if no parseable proc effect was found
function TopFit:ParseItemProc(itemLink)
	if not itemLink or not USE_PREFIX or not EQUIP_PREFIX then return nil end

	TopFit.scanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	TopFit.scanTooltip:SetHyperlink(itemLink)
	local numLines = TopFit.scanTooltip:NumLines()

	local effectLine, trigger
	for i = 1, numLines do
		local leftLine = getglobal("TFScanTooltip" .. "TextLeft" .. i)
		local leftLineText = leftLine and leftLine:GetText()
		if leftLineText then
			if leftLineText:find(USE_PREFIX, 1, true) then
				effectLine, trigger = leftLineText, "use"
				break
			elseif leftLineText:find(EQUIP_PREFIX, 1, true) and LooksLikeTriggeredEffect(leftLineText) then
				effectLine, trigger = leftLineText, "equip"
				-- keep scanning -- prefer a "Use:" line if one shows up later, since some
				-- items have both and Use: is the more reliably-scoreable of the two
			elseif CHANCE_PREFIX and leftLineText:find(CHANCE_PREFIX, 1, true) then
				-- weapon "chance on hit" procs (Dragonstrike, Lionheart Executioner, The Night
				-- Blade, etc.) use this prefix instead of "Equip:". Mechanically these are the
				-- same category as an equip-triggered proc -- same simc_proc_data.lua section,
				-- same downstream export handling -- so they're tagged "equip" here too rather
				-- than introducing a third trigger label that every consumer would need to know
				-- about. Same non-breaking scan priority as the Equip: branch above. No
				-- LooksLikeTriggeredEffect filter needed here -- this prefix IS the "chance"
				-- word already, and flat stats are never phrased this way to begin with.
				effectLine, trigger = leftLineText, "equip"
			end
		end
	end
	TopFit.scanTooltip:Hide()

	if not effectLine then return nil end

	local cooldown = ParseCooldownSeconds(effectLine)
	local duration = ParseDurationSeconds(effectLine)
	local statKey, amount = ParseStatAndAmount(effectLine, GetStatNameTable())

	if not (statKey and amount) then return nil end

	-- Fill gaps (never overrides) using simc's extracted proc database: WotLK tooltips very
	-- often omit the internal cooldown and/or duration entirely for "Chance on hit"-style
	-- equip procs, which is exactly the missing piece that made these unscoreable before.
	-- Item NAMES are known to match Triumvirate's items; the AMOUNT may not (retuned for the
	-- level-60 cap), so amount always comes from the tooltip parse above, never from here.
	local preciseTrigger, procChance, procPPM
	local simcData = TopFit:LookupSimcProcData(itemLink, trigger == "use" and "use" or "equip")
	if simcData then
		cooldown = cooldown or simcData.cooldown
		duration = duration or simcData.duration
		preciseTrigger = simcData.trigger
		procChance = simcData.procChance
		procPPM = simcData.procPPM
	end

	return {
		trigger = trigger,
		preciseTrigger = preciseTrigger, -- e.g. "OnAttackHit", when known from simc's data
		procChance = procChance,         -- percent chance per trigger event, when known
		procPPM = procPPM,               -- procs-per-minute, when known (alternate to procChance)
		statKey = statKey,
		amount = amount,
		duration = duration,
		cooldown = cooldown,
	}
end

-- computes an effective-average stat value from a parsed proc, or nil if there isn't enough
-- information to do so responsibly (see header comment -- this never guesses an unstated
-- proc chance or internal cooldown)
function TopFit:GetProcEffectiveValue(procInfo)
	if not procInfo or not procInfo.duration or not procInfo.cooldown or procInfo.cooldown <= 0 then
		return nil
	end
	local uptime = procInfo.duration / procInfo.cooldown
	if uptime > 1 then uptime = 1 end
	return procInfo.amount * uptime
end
