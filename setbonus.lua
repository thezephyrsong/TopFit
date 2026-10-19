-- setbonus.lua
-- Item set bonuses for the optimizer, from the generated setdata.lua (TopFit.SetData / TopFit.SetByItem).
--
-- How it fits into calculation.lua:
--  * SaveCurrentCombination calls TopFit:AddSetBonuses(cIC) on every combination it scores, so a combination
--    that happens to wear enough pieces of a set gets that set's bonus stats (score + cap totals).
--  * The main search only walks deeper than "best item per slot" when caps force it to, so it cannot find a
--    set on its own. TopFit:ApplySetBonusPass() therefore runs once on the winning combination: for every
--    set the player owns pieces of, it tries swapping those pieces in (non-weapon slots only), re-scores the
--    whole combination with the set bonus and the caps check, and keeps the best result. It repeats until
--    nothing improves, so two different sets can both end up in the result.
--  * ReduceItemList (calculation.lua) does not prune set pieces for being individually weak, since a piece's
--    value is partly the bonus it unlocks.
--
-- A set bonus counts DISTINCT item IDs (two copies of one ring are one piece). Only flat stats TopFit can score
-- are used; procs, movement and other effects are in setdata.lua's `other` lists and never scored.

local MAX_SWAP_SLOT = 15       -- slots 16+ are weapons/tabard: left exactly as the main search chose them
local MAX_CANDIDATES_PER_SLOT = 2
local MAX_EVALUATIONS = 3000   -- per pass, a hard ceiling so a huge bag can never stall the UI
local MAX_ROUNDS = 6

function TopFit:GetSetIDForItemID(itemID)
	return itemID and TopFit.SetByItem and TopFit.SetByItem[itemID] or nil
end

-- true when the item belongs to a set that has at least one scoreable bonus
function TopFit:IsScoreableSetPiece(itemTable)
	return itemTable and itemTable.itemID and TopFit.SetByItem and TopFit.SetByItem[itemTable.itemID] ~= nil
end

local function GetWeights()
	local setTable = TopFit.db and TopFit.db.profile.sets[TopFit.setCode]
	if not setTable then return {} end
	return TopFit:GetEffectiveWeights(setTable.weights or {}, setTable)
end

-- the stats of every set bonus the given { [slot] = locationTable } wears.
-- returns stats, summary ({ {setID=, name=, pieces=, bonuses={thresholds reached}} ... }) or nil when no set counts
function TopFit:GetSetBonusStats(items)
	if not TopFit.SetData or not TopFit.SetByItem then return nil end
	local counted = {}          -- setID -> { [itemID] = true }
	local any = false
	for _, locationTable in pairs(items) do
		local itemTable = locationTable and TopFit:GetCachedItem(locationTable.itemLink)
		local itemID = itemTable and itemTable.itemID
		local setID = itemID and TopFit.SetByItem[itemID]
		if setID then
			counted[setID] = counted[setID] or {}
			counted[setID][itemID] = true
			any = true
		end
	end
	if not any then return nil end

	local stats, summary = {}, {}
	for setID, ids in pairs(counted) do
		local n = 0
		for _ in pairs(ids) do n = n + 1 end
		local data = TopFit.SetData[setID]
		if data then
			local reached
			for threshold, bonus in pairs(data.bonuses) do
				if n >= threshold and bonus.stats then
					reached = reached or {}
					table.insert(reached, threshold)
					for stat, value in pairs(bonus.stats) do
						stats[stat] = (stats[stat] or 0) + value
					end
				end
			end
			if reached then
				table.sort(reached)
				table.insert(summary, { setID = setID, name = data.name, pieces = n, bonuses = reached })
			end
		end
	end
	if #summary == 0 then return nil end
	return stats, summary
end

-- add the set bonuses worn by a combination (cIC = { items, totalScore, totalStats }) to its score and totals
function TopFit:AddSetBonuses(cIC)
	local stats, summary = TopFit:GetSetBonusStats(cIC.items)
	if not stats then
		cIC.setBonuses = nil
		return
	end
	local weights = TopFit.setBonusWeights
	if not weights then
		weights = GetWeights()
		TopFit.setBonusWeights = weights
	end
	for stat, value in pairs(stats) do
		cIC.totalScore = cIC.totalScore + (weights[stat] or 0) * value
		cIC.totalStats[stat] = (cIC.totalStats[stat] or 0) + value
	end
	cIC.setBonuses = summary
end

function TopFit:AreCapsSatisfied(totalStats)
	for stat, capList in pairs(TopFit.Utopia) do
		for _, preferences in ipairs(capList) do
			if preferences.active and ((totalStats[stat] or 0) < TopFit:GetEffectiveCapValue(stat, preferences["value"])) then
				return false
			end
		end
	end
	return true
end

-- full score of a { [slot] = locationTable } selection: items, assumed enchants, set bonuses, caps check.
-- Mirrors what SaveCurrentCombination adds up.
function TopFit:ScoreSelection(items)
	local setCode = TopFit.setCode
	local cIC = { items = items, totalScore = 0, totalStats = {} }
	for slot = 1, 20 do
		local locationTable = items[slot]
		local itemTable = locationTable and TopFit:GetCachedItem(locationTable.itemLink)
		if itemTable then
			cIC.totalScore = cIC.totalScore + (TopFit:GetItemScore(itemTable.itemLink, setCode, TopFit.ignoreCapsForCalculation) or 0)
			for stat, value in pairs(itemTable.totalBonus) do
				cIC.totalStats[stat] = (cIC.totalStats[stat] or 0) + value
			end
			local enchantInfo = TopFit.GetEnchantForItem and TopFit:GetEnchantForItem(setCode, slot, itemTable)
			if enchantInfo then
				cIC.totalScore = cIC.totalScore + enchantInfo.score
				cIC.enchants = cIC.enchants or {}
				cIC.enchants[slot] = enchantInfo.entry
				for stat, value in pairs(enchantInfo.stats) do
					cIC.totalStats[stat] = (cIC.totalStats[stat] or 0) + value
				end
			end
		end
	end
	TopFit:AddSetBonuses(cIC)
	return cIC, TopFit:AreCapsSatisfied(cIC.totalStats)
end

local function LocationKey(locationTable)
	return tostring(locationTable.itemLink) .. "|" .. tostring(locationTable.bag) .. "|" .. tostring(locationTable.slot)
end

-- candidate set pieces per set: { [setID] = { [slot] = { locationTable, ... } } } (best item score first)
local function CollectCandidates()
	local bySet = {}
	for slot = 1, MAX_SWAP_SLOT do
		for _, locationTable in ipairs(TopFit.itemListBySlot[slot] or {}) do
			local itemTable = TopFit:GetCachedItem(locationTable.itemLink)
			local setID = itemTable and itemTable.itemID and TopFit.SetByItem[itemTable.itemID]
			if setID then
				bySet[setID] = bySet[setID] or {}
				bySet[setID][slot] = bySet[setID][slot] or {}
				table.insert(bySet[setID][slot], locationTable)
			end
		end
	end
	for _, slots in pairs(bySet) do
		for _, list in pairs(slots) do
			table.sort(list, function(a, b)
				return (TopFit:GetItemScore(a.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
					> (TopFit:GetItemScore(b.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) or 0)
			end)
			for i = #list, MAX_CANDIDATES_PER_SLOT + 1, -1 do list[i] = nil end
		end
	end
	return bySet
end

-- Try to improve TopFit.bestCombination with set bonuses. Safe to call with no best combination or no data.
function TopFit:ApplySetBonusPass()
	local best = TopFit.bestCombination
	if not best or not TopFit.SetData or not TopFit.SetByItem or not TopFit.itemListBySlot then return end

	TopFit.setBonusWeights = GetWeights()
	local candidates = CollectCandidates()
	if not next(candidates) then return end

	local current = TopFit:ScoreSelection(best.items)
	local currentScore = current.totalScore
	local evaluations = 0

	for round = 1, MAX_ROUNDS do
		local roundBest, roundBestScore = nil, currentScore + 1e-6

		for setID, slotLists in pairs(candidates) do
			local data = TopFit.SetData[setID]
			local slots = {}
			for slot in pairs(slotLists) do table.insert(slots, slot) end
			table.sort(slots)

			-- smallest piece count that earns anything; no point trying sets we can't reach
			local minThreshold
			for threshold, bonus in pairs(data.bonuses) do
				if bonus.stats and (not minThreshold or threshold < minThreshold) then minThreshold = threshold end
			end

			if minThreshold and #slots >= minThreshold then
				local trial = {}
				for slot, locationTable in pairs(current.items) do trial[slot] = locationTable end
				local used = {}

				local function search(index)
					if evaluations >= MAX_EVALUATIONS then return end
					if index > #slots then
						evaluations = evaluations + 1
						local scored, satisfied = TopFit:ScoreSelection(trial)
						if satisfied and scored.totalScore > roundBestScore then
							local copy = {}
							for slot, locationTable in pairs(trial) do copy[slot] = locationTable end
							scored.items = copy
							roundBest, roundBestScore = scored, scored.totalScore
						end
						return
					end
					local slot = slots[index]
					local original = trial[slot]
					-- 1) keep whatever the current combination wears in this slot
					search(index + 1)
					-- 2) or put one of this set's pieces there
					for _, locationTable in ipairs(slotLists[slot]) do
						local key = LocationKey(locationTable)
						if not used[key] and not (original and LocationKey(original) == key) then
							-- an item that is already worn in another slot of the trial can't be worn twice
							local clash = false
							for otherSlot, worn in pairs(trial) do
								if otherSlot ~= slot and LocationKey(worn) == key then clash = true break end
							end
							if not clash then
								used[key] = true
								trial[slot] = locationTable
								search(index + 1)
								trial[slot] = original
								used[key] = nil
							end
						end
					end
				end
				search(1)
			end
		end

		if roundBest then
			current, currentScore = roundBest, roundBest.totalScore
		else
			break
		end
	end

	-- only replace when it genuinely scores higher than what the main search found
	local baseline = TopFit:ScoreSelection(best.items)
	if currentScore > baseline.totalScore + 1e-6 then
		TopFit.bestCombination = current
		TopFit.maxScore = current.totalScore
		TopFit:Debug("Set bonus pass improved the combination: " .. tostring(baseline.totalScore) .. " -> " .. tostring(currentScore))
	end
end
