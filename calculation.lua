-- maps a class's English (non-localized) token to the armor material it's meant to wear.
-- used by the "Force Armor Type" per-set option to keep e.g. a Paladin from being recommended
-- a leather/cloth piece purely because it scores higher on raw weights than the available plate.
-- Death Knight, Evoker, Demon Hunter, and Monk intentionally absent -- confirmed 2026-09-26
-- (Dan): none of these four exist as playable classes in WoW: Forever at all. They'd been
-- added here speculatively when the class token maps elsewhere in the codebase were first
-- ported; that was wrong, not just premature, so removed rather than left as harmless-but-
-- incorrect entries a future reader might mistake for confirmation these classes exist.
local CLASS_ARMOR_TYPE = {
	WARRIOR     = "Plate",
	PALADIN     = "Plate",
	HUNTER      = "Mail",
	SHAMAN      = "Mail",
	ROGUE       = "Leather",
	DRUID       = "Leather",
	PRIEST      = "Cloth",
	MAGE        = "Cloth",
	WARLOCK     = "Cloth",
}

-- returns "Cloth"/"Leather"/"Mail"/"Plate" for the player's class, or nil if unknown
function TopFit:GetClassArmorType()
	local _, classToken = UnitClass("player")
	return CLASS_ARMOR_TYPE[classToken]
end

function TopFit:StartCalculations()
	-- generate table of set codes
	TopFit.workSetList = {}
	for setCode, _ in pairs(self.db.profile.sets) do
		tinsert(TopFit.workSetList, setCode)
	end
	
	TopFit:CalculateSets()
end

function TopFit:AbortCalculations()
	if TopFit.isBlocked then
		TopFit.abortCalculation = true
	end
end

function TopFit:CalculateSets(silent)
	if (not TopFit.isBlocked) then
		if not silent and InterfaceOptionsFrame then
			HideUIPanel(InterfaceOptionsFrame)
		end
		TopFit.silentCalculation = silent
		local setCode = tremove(TopFit.workSetList)
		while setCode and not self.db.profile.sets[setCode] and #(TopFit.workSetList) > 0 do
			setCode = tremove(TopFit.workSetList)
		end
		
		if setCode and self.db.profile.sets[setCode] then
			TopFit.setCode = setCode -- globally save the current set that is being calculated
			
			TopFit:Debug("Calculating items for "..setCode)
			
			-- set as working to prevent any further calls from "interfering"
			TopFit.isBlocked = true
			
			TopFit.Utopia = TopFit.db.profile.sets[setCode].caps or {}
			TopFit.ignoreCapsForCalculation = false
			
			-- do the actual work
			TopFit:collectItems()
			TopFit:CalculateRecommendations()
		end
	end
end

--start calculation for setName
function TopFit:CalculateRecommendations()
	local setName = self.db.profile.sets[TopFit.setCode].name
	TopFit.itemRecommendations = {}
	TopFit.currentItemCombination = {}
	TopFit.itemCombinations = {}
	TopFit.currentSetName = setName
	
	-- determine if the player can dualwield
	TopFit.playerCanDualWield = false
	TopFit.playerCanTitansGrip = false
	
	local playerClass = select(2, UnitClass("player"))
	-- Death Knight/Demon Hunter/Monk removed from this check 2026-09-26 (Dan confirmed): none
	-- exist in WoW: Forever. See CLASS_ARMOR_TYPE's comment above for the same correction.
	if playerClass == "ROGUE"
		or ((playerClass == "WARRIOR" or playerClass == "HUNTER") and UnitLevel("player") > 20) then
		TopFit.playerCanDualWield = true
	end
	
	if (TopFit.db.profile.sets[TopFit.setCode].simulateDualWield) then
		TopFit.playerCanDualWield = true
	end
	
	-- "Force Two-Handed": always recommend a 2H mainhand and leave the offhand empty,
	-- overriding whatever the class/spec would otherwise allow
	TopFit.playerForceTwoHanded = false
	if (TopFit.db.profile.sets[TopFit.setCode].forceTwoHanded) then
		TopFit.playerForceTwoHanded = true
	end
	
	-- rating granted directly by talents
	TopFit.talentBonusStats = TopFit:GetTalentRatingBonuses()
	
	TopFit:InitSemiRecursiveCalculations()
end

-- Given a set's own weights table, returns an EFFECTIVE weights table that also credits
-- stat-conversion talents configured in talentbonuses.lua's TopFit.talentStatConversions (e.g.
-- Hunter/Enhancement Shaman's Intellect->Attack Power talents). Returns the ORIGINAL table
-- unmodified -- never a copy -- whenever there's nothing to add, so this is cheap for the (most
-- common) case of a class/weight-set combination with no active conversions to apply; only
-- allocates a new table when it actually has something to add to it, and never mutates the
-- caller's real saved weights table even then.
--
-- Caps: deliberately NOT caps-aware on its own -- it just adds to the FROM stat's effective
-- weight, and the caller (inventory.lua's CalculateItemScore) applies its own existing cap check
-- against that same FROM stat afterward, same as it already does for every other weighted stat.
-- This means a conversion's value is gated by whether the FROM stat (e.g. Intellect) itself is
-- capped, not whether the TO stat (e.g. Attack Power) is -- a deliberate simplification for this
-- first implementation, not confirmed to be the most correct behavior in every case.
--
-- Performance note: resolves live talent ranks via TopFit:GetRetailTalentRanks() internally,
-- same as GetTalentRatingBonuses below, but unlike that function (called once per calculation
-- pass) this is called once per set PER ITEM from CalculateItemScore, so it does more live API
-- traversal in total. Not optimized further here since most classes (everything except Hunter/
-- Shaman/Paladin/Priest, which are the only ones with any talentStatConversions entries at all)
-- hit the free fast-path below and never reach that call. Worth revisiting if scoring a large
-- bag/bank on one of those four classes turns out to be slow in practice.
function TopFit:GetEffectiveWeights(weights)
	local playerClass = select(2, UnitClass("player"))
	local entries = TopFit.talentStatConversions and TopFit.talentStatConversions[playerClass]
	if not entries or #entries == 0 then
		return weights
	end
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then
		return weights
	end

	local ranksBySpellID, ranksByName = TopFit:GetRetailTalentRanks()
	if not next(ranksBySpellID) and not next(ranksByName) then
		return weights
	end

	local effective = nil -- allocated lazily, only once we know there's something to add
	for _, entry in ipairs(entries) do
		local rank = (entry.spellID and ranksBySpellID[entry.spellID]) or (entry.name and ranksByName[entry.name]) or 0
		if rank > 0 then
			local percent
			if entry.ranks then
				percent = entry.ranks[rank]
			elseif entry.percentPerRank then
				percent = entry.percentPerRank * rank
			end
			local toWeight = percent and weights[entry.toStat]
			if percent and percent > 0 and toWeight and toWeight ~= 0 then
				if not effective then
					effective = {}
					for stat, value in pairs(weights) do effective[stat] = value end
				end
				effective[entry.fromStat] = (effective[entry.fromStat] or 0) + (percent / 100) * toWeight
			end
		end
	end

	return effective or weights
end

-- Sums the percent stat bonuses granted by talents configured in talentbonuses.lua.
-- Forever's talents are read via TopFit:GetRetailTalentRanks() (core.lua) -- the modern
-- C_ClassTalents/C_Traits node system, addressed by spellID/name, not (tab, index). See
-- talentbonuses.lua's own header for why the old tab/index + rating-conversion approach (still
-- visible in git history) doesn't apply here at all anymore, not just because Triumvirate's
-- cancelled but because the underlying mechanism itself is different on this client.
function TopFit:GetTalentRatingBonuses()
	local bonuses = {}
	local playerClass = select(2, UnitClass("player"))
	local entries = TopFit.talentRatingBonuses and TopFit.talentRatingBonuses[playerClass]
	if not entries or #entries == 0 then
		return bonuses
	end
	
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then
		if not TopFit.warnedAboutMissingTalentData then
			TopFit:Debug("Talent-granted stat bonuses skipped -- this client doesn't expose C_ClassTalents/C_Traits.")
			TopFit.warnedAboutMissingTalentData = true
		end
		return bonuses
	end
	
	local ranksBySpellID, ranksByName = TopFit:GetRetailTalentRanks()
	if not next(ranksBySpellID) and not next(ranksByName) then
		if not TopFit.warnedAboutMissingTalentData then
			TopFit:Print("Talent-granted stat bonuses can't be read yet -- your active talent config may not be loaded. Try opening your Talent panel once this session, then recalculate.")
			TopFit.warnedAboutMissingTalentData = true
		end
		return bonuses
	end
	
	for _, entry in ipairs(entries) do
		-- spellID checked first (more stable across locale/rewording than name), falling back
		-- to name if no spellID is given on this entry or it isn't found this way
		local rank = (entry.spellID and ranksBySpellID[entry.spellID]) or (entry.name and ranksByName[entry.name]) or 0
		if rank > 0 and entry.percentPerPoint then
			local amount = entry.percentPerPoint * rank
			bonuses[entry.stat] = (bonuses[entry.stat] or 0) + amount
		end
	end
	
	return bonuses
end

function TopFit:HasActiveHardCap(capList)
	if not capList then return false end
	for _, capEntry in ipairs(capList) do
		if capEntry.active and not capEntry.soft then
			return true
		end
	end
	return false
end

function TopFit:GetBestGemScore(allowedColors, weights, caps)
	local bestScore = 0
	if not TopFit.gemIDs then return bestScore end
	
	for gemID, gemData in pairs(TopFit.gemIDs) do
		local fits = false
		for _, gemColor in ipairs(gemData.colors) do
			for _, allowed in ipairs(allowedColors) do
				if gemColor == allowed then
					fits = true
					break
				end
			end
			if fits then break end
		end
		if fits then
			local score = 0
			for stat, value in pairs(gemData.stats) do
				local statValue = weights[stat]
				if statValue and ((not caps) or (not caps[stat]) or (not TopFit:HasActiveHardCap(caps[stat]))) then
					score = score + statValue * value
				end
			end
			if score > bestScore then
				bestScore = score
			end
		end
	end
	return bestScore
end

function TopFit:GetPotentialGemScore(itemTable, weights, caps)
	if not itemTable or not itemTable.emptySocketColors or #itemTable.emptySocketColors == 0 then
		return 0
	end
	
	local total = 0
	for _, color in ipairs(itemTable.emptySocketColors) do
		total = total + TopFit:GetBestGemScore({color}, weights, caps)
	end
	
	if itemTable.socketBonusInfo then
		local bonusStat = itemTable.socketBonusInfo.stat
		local bonusValue = itemTable.socketBonusInfo.value
		if weights[bonusStat] and ((not caps) or (not caps[bonusStat]) or (not TopFit:HasActiveHardCap(caps[bonusStat]))) then
			total = total + weights[bonusStat] * bonusValue
		end
	end
	
	return total
end

function TopFit:IsStatCapped(capList)
	if not capList then return false end
	for _, capEntry in ipairs(capList) do
		if capEntry.active then
			return true
		end
	end
	return false
end

function TopFit:GetEffectiveCapValue(stat, nominalValue)
	local talentBonus = (TopFit.talentBonusStats and TopFit.talentBonusStats[stat]) or 0
	return tonumber(nominalValue or 0) - talentBonus
end

function TopFit:InitSemiRecursiveCalculations()
	-- save equippable items
	TopFit.itemListBySlot = TopFit:GetEquippableItems()
	TopFit:ReduceItemList()
	
	TopFit.slotCounters = {}
	TopFit.currentSlotCounter = 0
	TopFit.operationsPerFrame = 500
	TopFit.combinationCount = 0
	TopFit.bestCombination = nil
	TopFit.maxScore = nil
	TopFit.firstCombination = true
	
	TopFit.capHeuristics = {}
	TopFit.maxRestStat = {}
	TopFit.currentCapValues = {}
	
	-- create maximum values for each cap and item slot
	for statCode, capList in pairs(TopFit.Utopia) do
		if TopFit:IsStatCapped(capList) then
			TopFit.capHeuristics[statCode] = {}
			TopFit.maxRestStat[statCode] = {}
			for _, slotID in pairs(TopFit.slots) do
				if (TopFit.itemListBySlot[slotID]) then
					local maxStat = nil
					for _, locationTable in pairs(TopFit.itemListBySlot[slotID]) do
						local itemTable = TopFit:GetCachedItem(locationTable.itemLink)
						if itemTable then
							local thisStat = itemTable.totalBonus[statCode] or 0
							if ((thisStat > 0) and ((maxStat == nil) or (thisStat > maxStat))) then
								maxStat = thisStat
							end
						end
					end
					
					TopFit.capHeuristics[statCode][slotID] = maxStat
				end
			end
			
			for i = 0, 20 do
				TopFit.maxRestStat[statCode][i] = 0
				if (TopFit.capHeuristics[statCode][i]) then
					for j = 0, i do
						TopFit.maxRestStat[statCode][j] = TopFit.maxRestStat[statCode][j] + TopFit.capHeuristics[statCode][i]
					end
				end
			end
		end
	end
	
	TopFit.calculationsFrame:SetScript("OnUpdate", TopFit.SemiRecursiveCalculation)
	
	-- show progress frame
	if not TopFit.silentCalculation then
		TopFit:CreateProgressFrame()
	elseif not TopFit.ProgressFrame then
		TopFit:CreateProgressFrame()
		TopFit.ProgressFrame:Hide()
	end
	if TopFit.ProgressFrame then
		TopFit.ProgressFrame:SetSelectedSet(TopFit.setCode)
		TopFit.ProgressFrame:SetSetName(TopFit.currentSetName)
		TopFit.ProgressFrame:ResetProgress()
	end
end

function TopFit:ReduceItemList()
	-- remove all non-forced items from item list
	local forcedTable = (self.db and self.db.profile and self.db.profile.sets[TopFit.setCode] and self.db.profile.sets[TopFit.setCode].forced) or {}
	for slotID, forceID in pairs(forcedTable) do
		if TopFit.itemListBySlot[slotID] then
			for i = #(TopFit.itemListBySlot[slotID]), 1, -1 do
				local itemTable = TopFit:GetCachedItem(TopFit.itemListBySlot[slotID][i].itemLink)
				if not itemTable or (itemTable.itemID ~= forceID) then
					tremove(TopFit.itemListBySlot[slotID], i)
				end
			end
		end
	end
	
	-- "Force Two-Handed" filter
	if TopFit.playerForceTwoHanded then
		if TopFit.itemListBySlot[16] and not forcedTable[16] then
			for i = #(TopFit.itemListBySlot[16]), 1, -1 do
				local itemTable = TopFit:GetCachedItem(TopFit.itemListBySlot[16][i].itemLink)
				if not itemTable or itemTable.itemEquipLoc ~= "INVTYPE_2HWEAPON" then
					tremove(TopFit.itemListBySlot[16], i)
				end
			end
		end
		if TopFit.itemListBySlot[17] and not forcedTable[17] then
			for i = #(TopFit.itemListBySlot[17]), 1, -1 do
				tremove(TopFit.itemListBySlot[17], i)
			end
		end
	end
	
	-- remove all items with score <= 0 that are neither forced nor contribute to caps
	for slotID, itemList in pairs(TopFit.itemListBySlot) do
		if #itemList >= 1 then
			for i = #itemList, 1, -1 do
				if (TopFit:GetItemScore(itemList[i].itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) <= 0) then
					if not forcedTable[slotID] then
						local hasCap = false
						for statCode, capList in pairs(TopFit.Utopia) do
							if TopFit:IsStatCapped(capList) then
								local itemTable = TopFit:GetCachedItem(itemList[i].itemLink)
								if itemTable and (itemTable.totalBonus[statCode] or -1) > 0 then
									hasCap = true
									break
								end
							end
						end
						
						if not hasCap then
							tremove(itemList, i)
						end
					end
				end
			end
		end
	end
	
	-- remove BoE items
	for slotID, itemList in pairs(TopFit.itemListBySlot) do
		if #itemList > 0 then
			for i = #itemList, 1, -1 do
				if itemList[i].isBoE then
					tremove(itemList, i)
				end
			end
		end
	end

	-- remove items of the wrong armor material, if "Force Armor Type" is enabled
	if self.db.profile.sets[TopFit.setCode].forceArmorType then
		local classArmorType = TopFit:GetClassArmorType()
		if classArmorType then
			for slotID, itemList in pairs(TopFit.itemListBySlot) do
				if #itemList > 0 and not forcedTable[slotID] then
					for i = #itemList, 1, -1 do
						local itemTable = TopFit:GetCachedItem(itemList[i].itemLink)
						local subType = itemTable and itemTable.itemSubType
						if subType == "Cloth" or subType == "Leather" or subType == "Mail" or subType == "Plate" then
							if subType ~= classArmorType then
								tremove(itemList, i)
							end
						end
					end
				end
			end
		end
	end

	-- reduce item list: remove items strictly worse in both score and caps
	for slotID, itemList in pairs(TopFit.itemListBySlot) do
		if #itemList > 1 then
			for i = #itemList, 1, -1 do
				local itemTable = TopFit:GetCachedItem(itemList[i].itemLink)
				if not itemTable then
					tremove(itemList, i)
				else
					local betterItemExists = 0
					local numBetterItemsNeeded = 1
					
					if (slotID == 17) or (slotID == 12) or (slotID == 14) or (slotID == 13) or (slotID == 11) or (slotID == 9) then
						numBetterItemsNeeded = 2
					end
					
					for j = 1, #itemList do
						if i ~= j then
							local compareTable = TopFit:GetCachedItem(itemList[j].itemLink)
							if compareTable and
								(TopFit:GetItemScore(itemTable.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) < TopFit:GetItemScore(compareTable.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation)) and
								(itemTable.itemEquipLoc == compareTable.itemEquipLoc) then
								
								local allStats = true
								for statCode, capList in pairs(TopFit.Utopia) do
									if TopFit:IsStatCapped(capList) then
										if (itemTable.totalBonus[statCode] or 0) > (compareTable.totalBonus[statCode] or 0) then
											allStats = false
											break
										end
									end
								end
								
								if allStats then
									betterItemExists = betterItemExists + 1
									if (betterItemExists >= numBetterItemsNeeded) then
										break
									end
								end
							end
						end
					end
					
					if betterItemExists >= numBetterItemsNeeded then
						tremove(itemList, i)
					end
				end
			end
		end
	end
end

function TopFit:SemiRecursiveCalculation()
	local operation
	local done = false
	for operation = 1, TopFit.operationsPerFrame do
		if (not done) and (not TopFit.abortCalculation) then
			local currentSlot = 19
			local increased = false
			while (not increased) and (currentSlot > 0) do
				while (TopFit.slotCounters[currentSlot] == nil or TopFit.slotCounters[currentSlot] == #(TopFit.itemListBySlot[currentSlot] or {})) and (currentSlot > 0) do
					TopFit.slotCounters[currentSlot] = nil
					currentSlot = currentSlot - 1
				end
				
				if (currentSlot > 0) then
					TopFit.slotCounters[currentSlot] = TopFit.slotCounters[currentSlot] + 1
					if (not TopFit:IsDuplicateItem(currentSlot)) and (TopFit:IsOffhandValid(currentSlot)) then
						increased = true
					end
				else
					if TopFit.firstCombination then
						TopFit.firstCombination = false
					else
						done = true
						TopFit.calculationsFrame:SetScript("OnUpdate", nil)
						operation = TopFit.operationsPerFrame
						
						TopFit:SaveCurrentCombination()
						
						if (TopFit.bestCombination) then
							for slotID, locationTable in pairs(TopFit.bestCombination.items) do
								TopFit.itemRecommendations[slotID] = {
									locationTable = locationTable,
								}
							end
							TopFit:EquipRecommendedItems()
						else
							if not TopFit.silentCalculation then
								TopFit:Print("Caps could not be reached, calculating again without caps.")
							end
							TopFit.Utopia = {}
							TopFit.ignoreCapsForCalculation = true
							TopFit:CalculateRecommendations(TopFit.currentSetName)
							return
						end
					end
				end
			end
			
			if not done then
				while (not TopFit:IsCapsReached(currentSlot)) and (not TopFit:IsCapsUnreachable(currentSlot)) and (currentSlot < 19) do
					currentSlot = currentSlot + 1
					if #(TopFit.itemListBySlot[currentSlot] or {}) > 0 then
						TopFit.slotCounters[currentSlot] = 1
						while TopFit:IsDuplicateItem(currentSlot) or (not TopFit:IsOffhandValid(currentSlot)) do
							TopFit.slotCounters[currentSlot] = TopFit.slotCounters[currentSlot] + 1
						end
						if TopFit.slotCounters[currentSlot] > #(TopFit.itemListBySlot[currentSlot]) then
							TopFit.slotCounters[currentSlot] = 0
						end
					else
						TopFit.slotCounters[currentSlot] = 0
					end
				end
				
				if TopFit:IsCapsReached(currentSlot) then
					TopFit:SaveCurrentCombination()
				end
			end
		end
	end
	
	-- update progress
	if not done then
		local progress = 0
		local impact = 1
		local slot
		for slot = 1, 20 do
			if TopFit.itemListBySlot[slot] then
				local numItemsInSlot = #(TopFit.itemListBySlot[slot]) or 1
				local selectedItem = (TopFit.slotCounters[slot] == 0) and (#(TopFit.itemListBySlot[slot]) or 1) or (TopFit.slotCounters[slot] or 1)
				if numItemsInSlot == 0 then numItemsInSlot = 1 end
				if selectedItem == 0 then selectedItem = 1 end
				
				impact = impact / numItemsInSlot
				progress = progress + impact * (selectedItem - 1)
			end
		end
		
		if TopFit.ProgressFrame then
			TopFit.ProgressFrame:SetProgress(progress)
		end
	else
		if TopFit.ProgressFrame then
			TopFit.ProgressFrame:SetProgress(1)
		end
	end
	
	if TopFit.bestCombination and TopFit.ProgressFrame then
		TopFit.ProgressFrame:SetCurrentCombination(TopFit.bestCombination)
	end
	
	if TopFit.abortCalculation then
		TopFit.calculationsFrame:SetScript("OnUpdate", nil)
		TopFit.abortCalculation = nil
		TopFit.isBlocked = false
		if TopFit.ProgressFrame then
			TopFit.ProgressFrame:StoppedCalculation()
		end
	end
	
	TopFit:Debug("Current combination count: "..TopFit.combinationCount)
end

function TopFit:IsCapsReached(currentSlot)
	local currentValues = {}
	for i = 1, currentSlot do
		if TopFit.slotCounters[i] ~= nil and TopFit.slotCounters[i] > 0 and TopFit.itemListBySlot[i] then
			for stat, capList in pairs(TopFit.Utopia) do
				if TopFit:IsStatCapped(capList) then
					local itemEntry = TopFit.itemListBySlot[i][TopFit.slotCounters[i]]
					local itemTable = itemEntry and TopFit:GetCachedItem(itemEntry.itemLink)
					if itemTable then
						currentValues[stat] = (currentValues[stat] or 0) + (itemTable.totalBonus[stat] or 0)
					end
				end
			end
		end
	end
	
	for stat, capList in pairs(TopFit.Utopia) do
		for _, preferences in ipairs(capList) do
			if preferences.active and (currentValues[stat] or 0) < TopFit:GetEffectiveCapValue(stat, preferences.value) then
				return false
			end
		end
	end
	return true
end

function TopFit:IsCapsUnreachable(currentSlot)
	local currentValues = {}
	local restValues = {}
	for stat, capList in pairs(TopFit.Utopia) do
		if TopFit:IsStatCapped(capList) then
			for i = 1, currentSlot do
				if TopFit.slotCounters[i] ~= nil and TopFit.slotCounters[i] > 0 and TopFit.itemListBySlot[i] then
					local itemEntry = TopFit.itemListBySlot[i][TopFit.slotCounters[i]]
					local itemTable = itemEntry and TopFit:GetCachedItem(itemEntry.itemLink)
					if itemTable then
						currentValues[stat] = (currentValues[stat] or 0) + (itemTable.totalBonus[stat] or 0)
					end
				end
			end
			
			for i = currentSlot + 1, 19 do
				restValues[stat] = (restValues[stat] or 0) + (TopFit.capHeuristics and TopFit.capHeuristics[stat] and TopFit.capHeuristics[stat][i] or 0)
			end
			
			for _, preferences in ipairs(capList) do
				if preferences.active and (currentValues[stat] or 0) + (restValues[stat] or 0) < TopFit:GetEffectiveCapValue(stat, preferences.value) then
					TopFit:Debug("|cffff0000Caps unreachable - "..stat.." reached "..(currentValues[stat] or 0).." + "..(restValues[stat] or 0).." / "..preferences.value)
					return true
				end
			end
		end
	end
	return false
end

function TopFit:IsDuplicateItem(currentSlot)
	for i = 1, currentSlot - 1 do
		if TopFit.slotCounters[i] and TopFit.slotCounters[i] > 0 and TopFit.itemListBySlot[i] then
			local lTable1 = TopFit.itemListBySlot[i][TopFit.slotCounters[i]]
			local lTable2 = TopFit.itemListBySlot[currentSlot] and TopFit.itemListBySlot[currentSlot][TopFit.slotCounters[currentSlot]]
			if lTable1 and lTable2 and lTable1.itemLink == lTable2.itemLink and lTable1.bag == lTable2.bag and lTable1.slot == lTable2.slot then
				return true
			end
		end
	end
	return false
end

function TopFit:IsOffhandValid(currentSlot)
	if currentSlot == 17 then -- offhand slot
		if (TopFit.slotCounters[17] ~= nil) and (TopFit.slotCounters[17] > 0) and (TopFit.slotCounters[17] <= #(TopFit.itemListBySlot[17] or {})) then
			if (TopFit.slotCounters[16] == nil or TopFit.slotCounters[16] == 0) or
				(TopFit:IsOnehandedWeapon(TopFit.itemListBySlot[16][TopFit.slotCounters[16]].itemLink)) then
				
				local itemTable = TopFit:GetCachedItem(TopFit.itemListBySlot[17][TopFit.slotCounters[17]].itemLink)
				if not itemTable then return false end
				
				if (not TopFit.playerCanDualWield) then
					if itemTable.itemEquipLoc and string.find(itemTable.itemEquipLoc, "WEAPON") then
						return false
					end
				else -- player can dualwield
					if (not TopFit:IsOnehandedWeapon(itemTable.itemLink or itemTable.itemID)) then
						return false
					end
				end
			else
				-- 2H Mainhand equipped, no offhand allowed
				return false
			end
		end
	end
	return true
end

function TopFit:SaveCurrentCombination()
	TopFit.combinationCount = TopFit.combinationCount + 1
	
	local cIC = {
		items = {},
		totalScore = 0,
		totalStats = {},
	}
	
	local itemsAlreadyChosen = {}
	
	for i = 1, 20 do
		local itemTable, locationTable = nil, nil
		
		if TopFit.slotCounters[i] ~= nil and TopFit.slotCounters[i] > 0 and TopFit.itemListBySlot[i] then
			locationTable = TopFit.itemListBySlot[i][TopFit.slotCounters[i]]
			itemTable = locationTable and TopFit:GetCachedItem(locationTable.itemLink)
		else
			locationTable = TopFit:CalculateBestInSlot(itemsAlreadyChosen, false, i)
			if locationTable then
				itemTable = TopFit:GetCachedItem(locationTable.itemLink)
			end
			
			if (itemTable) then
				if (i == 16) then
					if TopFit.slotCounters[17] then
						locationTable = TopFit:CalculateBestInSlot(itemsAlreadyChosen, false, i, TopFit.setCode, function(lTable) return TopFit:IsOnehandedWeapon(lTable.itemLink) end)
						if locationTable then
							itemTable = TopFit:GetCachedItem(locationTable.itemLink)
						end
					else
						if not TopFit:IsOnehandedWeapon(itemTable.itemLink or itemTable.itemID) then
							local bestMainScore, bestOffScore = 0, 0
							local bestOff = nil
							local bestMain = TopFit:CalculateBestInSlot(itemsAlreadyChosen, false, i, TopFit.setCode, function(lTable) return TopFit:IsOnehandedWeapon(lTable.itemLink) end)
							if bestMain ~= nil then
								bestMainScore = (TopFit:GetItemScore(bestMain.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
							end
							if (TopFit.playerCanDualWield) then
								bestOff = TopFit:CalculateBestInSlot(TopFit:JoinTables(itemsAlreadyChosen, {bestMain}), false, i + 1, TopFit.setCode, function(lTable) return TopFit:IsOnehandedWeapon(lTable.itemLink) end)
							else
								bestOff = TopFit:CalculateBestInSlot(TopFit:JoinTables(itemsAlreadyChosen, {bestMain}), false, i + 1, TopFit.setCode, function(lTable) local it = TopFit:GetCachedItem(lTable.itemLink); if not it or (it.itemEquipLoc and string.find(it.itemEquipLoc, "WEAPON")) then return false else return true end end)
							end
							if bestOff ~= nil then
								bestOffScore = (TopFit:GetItemScore(bestOff.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
							end
							
							local bestMainScore2, bestOffScore2 = 0, 0
							local bestMain2 = nil
							local bestOff2 = nil
							if (TopFit.playerCanDualWield) then
								bestOff2 = TopFit:CalculateBestInSlot(itemsAlreadyChosen, false, i + 1, TopFit.setCode, function(lTable) return TopFit:IsOnehandedWeapon(lTable.itemLink) end)
							else
								bestOff2 = TopFit:CalculateBestInSlot(itemsAlreadyChosen, false, i + 1, TopFit.setCode, function(lTable) local it = TopFit:GetCachedItem(lTable.itemLink); if not it or (it.itemEquipLoc and string.find(it.itemEquipLoc, "WEAPON")) then return false else return true end end)
							end
							if bestOff2 ~= nil then
								bestOffScore2 = (TopFit:GetItemScore(bestOff2.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
							end
							
							bestMain2 = TopFit:CalculateBestInSlot(TopFit:JoinTables(itemsAlreadyChosen, {bestOff2}), false, i, TopFit.setCode, function(lTable) return TopFit:IsOnehandedWeapon(lTable.itemLink) end)
							if bestMain2 ~= nil then
								bestMainScore2 = (TopFit:GetItemScore(bestMain2.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
							end
							
							local maxScore = (TopFit:GetItemScore(itemTable.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
							if (maxScore < (bestMainScore + bestOffScore)) then
								locationTable = bestMain
								if locationTable then
									itemTable = TopFit:GetCachedItem(locationTable.itemLink)
								end
								maxScore = bestMainScore + bestOffScore
							end
							if (maxScore < (bestMainScore2 + bestOffScore2)) then
								locationTable = bestMain2
								if locationTable then
									itemTable = TopFit:GetCachedItem(locationTable.itemLink)
								end
							end
						end
					end
				elseif (i == 17) then
					if (not cIC.items[i - 1]) or (TopFit:IsOnehandedWeapon(cIC.items[i - 1].itemLink)) then
						if TopFit.playerCanDualWield then
							locationTable = TopFit:CalculateBestInSlot(itemsAlreadyChosen, false, i, TopFit.setCode, function(lTable) return TopFit:IsOnehandedWeapon(lTable.itemLink) end)
							if locationTable then
								itemTable = TopFit:GetCachedItem(locationTable.itemLink)
							end
						else
							locationTable = TopFit:CalculateBestInSlot(itemsAlreadyChosen, false, i, TopFit.setCode, function(lTable) local it = TopFit:GetCachedItem(lTable.itemLink); if not it or (it.itemEquipLoc and string.find(it.itemEquipLoc, "WEAPON")) then return false else return true end end)
							if locationTable then
								itemTable = TopFit:GetCachedItem(locationTable.itemLink)
							end
						end
					else
						locationTable = nil
						itemTable = nil
					end
				end
			end
		end
		
		if locationTable and itemTable then
			tinsert(itemsAlreadyChosen, locationTable)
			cIC.items[i] = locationTable
			cIC.totalScore = cIC.totalScore + (TopFit:GetItemScore(itemTable.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
			
			for stat, value in pairs(itemTable.totalBonus) do
				cIC.totalStats[stat] = (cIC.totalStats[stat] or 0) + value
			end
		end
	end
	
	local satisfied = true
	for stat, capList in pairs(TopFit.Utopia) do
		for _, preferences in ipairs(capList) do
			if preferences.active and ((cIC.totalStats[stat] or 0) < TopFit:GetEffectiveCapValue(stat, preferences["value"])) then
				satisfied = false
			end
		end
	end
	
	if ((satisfied) and ((TopFit.maxScore == nil) or (TopFit.maxScore < cIC.totalScore))) then
		TopFit.maxScore = cIC.totalScore
		TopFit.bestCombination = cIC
		
		TopFit.debugSlotCounters = {}
		for i = 1, 20 do
			TopFit.debugSlotCounters[i] = TopFit.slotCounters[i]
		end
	end
end

function TopFit:CalculateBestInSlot(itemsAlreadyChosen, insert, sID, setCode, assertion)
	if not setCode then setCode = TopFit.setCode end

	local bis = {}
	local itemListBySlot = TopFit.itemListBySlot or TopFit:GetEquippableItems()
	for slotID, itemsTable in pairs(itemListBySlot) do
		if ((not sID) or (sID == slotID)) then
			bis[slotID] = {}
			local maxScore = nil
			
			for _, locationTable in pairs(itemsTable) do
				local itemTable = TopFit:GetCachedItem(locationTable.itemLink)
				
				if (itemTable and ((maxScore == nil) or (maxScore < TopFit:GetItemScore(itemTable.itemLink, setCode, TopFit.ignoreCapsForCalculation)))
					and (itemTable.itemMinLevel <= TopFit.characterLevel or locationTable.isVirtual))
					and (not assertion or assertion(locationTable)) then
					
					local found = false
					if (itemsAlreadyChosen) then
						for _, lTable in pairs(itemsAlreadyChosen) do
							if ((not lTable.bag and not lTable.slot) or ((lTable.bag == locationTable.bag) and (lTable.slot == locationTable.slot))) and (lTable.itemLink == locationTable.itemLink) then
								found = true
							end
						end
					end
					
					if not found then
						bis[slotID].locationTable = locationTable
						maxScore = TopFit:GetItemScore(itemTable.itemLink, setCode, TopFit.ignoreCapsForCalculation)
					end
				end
			end
			
			if (not bis[slotID].locationTable) then
				bis[slotID] = nil
			else
				if (itemsAlreadyChosen and insert) then
					tinsert(itemsAlreadyChosen, bis[slotID].locationTable)
				end
			end
		end
	end
	
	if (not sID) then
		return bis
	else
		if (bis[sID]) then
			return bis[sID].locationTable
		else
			return nil
		end
	end
end

function TopFit:IsOnehandedWeapon(item)
	if not item then return true end

	local equipSlot, itemSubType
	if TopFit and TopFit.GetCachedItem then
		local itemTable = TopFit:GetCachedItem(item)
		if itemTable then
			equipSlot = itemTable.itemEquipLoc
			itemSubType = itemTable.itemSubType
		end
	end

	if not equipSlot then
		local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		if GetInfo then
			local _, _, _, _, _, _, subType, _, loc = GetInfo(item)
			equipSlot = loc
			itemSubType = subType
		end
	end

	if not equipSlot then
		local id = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
		if id and C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(id)
			if TopFit.pendingItemInfoRequests then
				TopFit.pendingItemInfoRequests[id] = true
			end
		end
		return true
	end

	if equipSlot == "INVTYPE_2HWEAPON" or equipSlot == "INVTYPE_RANGED" or equipSlot == "INVTYPE_RANGEDRIGHT" then
			if equipSlot == "INVTYPE_2HWEAPON" or equipSlot == "INVTYPE_RANGED" or equipSlot == "INVTYPE_RANGEDRIGHT" then
				-- New class-specific exclusions for specialized ranged weapon types
				local class = select(2, UnitClass("player"))
				local isRanged = equipSlot == "INVTYPE_RANGED"
				
				-- Apply class restrictions for ranged weapons
				if isRanged then
					local isExcluded = false
					-- Druid exclusion (Idol)
					if (class == "DRUID") then isExcluded = true end
					-- Shaman exclusion (Totem)
					if (class == "SHAMAN") then isExcluded = true end
					-- Paladin exclusion (Library)
					if (class == "PALADIN") then isExcluded = true end
					
					if isExcluded then
						return false
					end
				end

				if TopFit.playerCanTitansGrip and equipSlot == "INVTYPE_2HWEAPON" then
					if itemSubType then
						local sub = itemSubType:lower()
						if sub:find("polearm") or sub:find("staff") or sub:find("staves") or sub:find("fishing") then
							return false
						end
					end
					return true
				else
					return false
				end
			end
	end

	return true
end