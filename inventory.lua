--[[ inventory management and caching

interesting variables:
TopFit.itemsCache - item Tables, indexed by itemLink
TopFit.scoresCache - scores, indexed by itemLink and setCode

]]--

local function tinsertonce(table, data)
    local found = false
    for _, v in pairs(table) do
        if v == data then
            found = true
            break
        end
    end
    if not found then
        tinsert(table, data)
    end
end

-- gather all items from inventory and bags, save their info to cache
function TopFit:collectItems(bag)
    TopFit.characterLevel = UnitLevel("player")
    
    if bag and bag >= 0 and bag <= 4 then
        -- only check a specific bag (used on BAG_UPDATE)
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemLink(bag, slot)
            
            TopFit:UpdateCache(item)
        end
    else
        -- check bags
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local item = C_Container.GetContainerItemLink(bag, slot)
                
                TopFit:UpdateCache(item)
            end
        end
        
        -- check equipped items
        for _, invSlot in pairs(TopFit.slots) do
            local item = GetInventoryItemLink("player", invSlot)
            
            TopFit:UpdateCache(item)
        end
    end
end

-- collect item information if necessary
function TopFit:UpdateCache(item)
    if item and (not TopFit.itemsCache[item]) then
        -- check if it's equipment
        if C_Item.IsEquippableItem(item) then
            local itemTable = TopFit:GetItemInfoTable(item)
            
            if itemTable then
                -- save in cache
                TopFit.itemsCache[item] = itemTable
                
                -- calculate set scores
                TopFit:CalculateItemScore(item)
            end
        end
    end
end

-- 12.1.5's GetItemInfo can legitimately return nil on the first call for an item
-- that isn't cached yet (unlike 3.3.5a's synchronous behavior, which this addon was
-- originally written against). This tracks which itemIDs we're waiting on, so the
-- GET_ITEM_INFO_RECEIVED handler in core.lua knows what to rescan once data arrives.
-- Deliberately NOT a fallback/compat shim -- this is the correct, only way to handle
-- item data on this client, not a bridge to older behavior.
TopFit.pendingItemInfoRequests = TopFit.pendingItemInfoRequests or {}

-- re-runs GetItemInfoTable for an item once its async data has loaded, and refreshes
-- anything cached under its old (incomplete) result. Called from core.lua's
-- GET_ITEM_INFO_RECEIVED handler.
function TopFit:RescanPendingItem(itemID)
    if not itemID then return end
    -- clear any cache entries keyed off this itemID with unresolved data, then let the
    -- normal collection pass (next BAG_UPDATE, or an explicit rescan) pick it back up
    if TopFit.itemsCache then
        for cacheKey in pairs(TopFit.itemsCache) do
            if cacheKey:match("^" .. itemID .. ":") then
                TopFit.itemsCache[cacheKey] = nil
            end
        end
    end
    TopFit:collectItems()
end

-- find out all we need to know about an item. and maybe even more
-- this does not return information which might change, only things you can get from the item link
function TopFit:GetItemInfoTable(item)
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(item)
    if not itemLink then
        -- not cached yet -- request the data and remember to retry once it arrives,
        -- rather than silently dropping this item from scoring until the next reload
        local itemID = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
        if itemID then
            C_Item.RequestLoadItemDataByID(itemID)
            TopFit.pendingItemInfoRequests[itemID] = true
        end
        return nil
    end

    -- Extract IDs for unique cache key
    local itemID = string.match(itemLink, "item:(%d+)")
    local enchantID = string.match(itemLink, "item:%d+:(%d+)") or "0"
    local g1, g2, g3, g4 = string.match(itemLink, "item:%d+:%d+:(%d+):(%d+):(%d+):(%d+)")
    local cacheKey = string.format("%s:%s:%s:%s:%s:%s", itemID or "0", enchantID, g1 or "0", g2 or "0", g3 or "0", g4 or "0")

    -- 1. SavedVariables Cache Lookup
    TopFit.db = TopFit.db or {}
    TopFit.db.global = TopFit.db.global or {}
    TopFit.db.global.itemCache = TopFit.db.global.itemCache or {}

    if TopFit.db.global.itemCache[cacheKey] then
        return TopFit.db.global.itemCache[cacheKey]
    end

    itemID = tonumber(itemID)
    enchantID = tonumber(enchantID)

    -- 2. Base Item Stats (from API)
    local itemBonus = GetItemStats(itemLink) or {}

    -- 2b. Permanent flat/percent "Equip:" stats not covered by GetItemStats() at all on
    -- WoW: Forever's pre-rating itemization model (hit/crit %, dodge-parry reduction %,
    -- flat weapon skill, flat defense, flat spell healing/damage) -- see procparser.lua.
    -- Merged in as TOPFIT_* keys alongside the normal ITEM_MOD_* keys from GetItemStats().
    if TopFit.ScanItemPermanentPercentStats then
        local permanentStats = TopFit:ScanItemPermanentPercentStats(itemLink)
        for statKey, amount in pairs(permanentStats) do
            itemBonus[statKey] = amount
        end
    end

    if TopFit.GetSimcWeaponType and TopFit:GetSimcWeaponType(itemLink) then
        local weaponSpeed = TopFit.ParseWeaponTooltip and TopFit:ParseWeaponTooltip(itemLink)
        if weaponSpeed and weaponSpeed > 0 then
            itemBonus["TOPFIT_WEAPON_SPEED"] = weaponSpeed
        end
    end

    -- Helper to parse stat lines safely
    local function ParseStatLine(lineText, targetTable)
        if not lineText or lineText == "" then return end
        local cleanLine = string.gsub(lineText, "%(.-%)", "") -- Strip parenthesized rating calculations

        -- Handle "+X All Stats" (Enchanted / Nightmare Tear, Prismatic Sphere)
        local allStatsVal = string.match(cleanLine, "%+?(%d+)%s+[Aa]ll%s+[Ss]tats")
        if allStatsVal then
            local val = tonumber(allStatsVal) or 0
            targetTable["ITEM_MOD_STRENGTH_SHORT"] = (targetTable["ITEM_MOD_STRENGTH_SHORT"] or 0) + val
            targetTable["ITEM_MOD_AGILITY_SHORT"] = (targetTable["ITEM_MOD_AGILITY_SHORT"] or 0) + val
            targetTable["ITEM_MOD_STAMINA_SHORT"] = (targetTable["ITEM_MOD_STAMINA_SHORT"] or 0) + val
            targetTable["ITEM_MOD_INTELLECT_SHORT"] = (targetTable["ITEM_MOD_INTELLECT_SHORT"] or 0) + val
            targetTable["ITEM_MOD_SPIRIT_SHORT"] = (targetTable["ITEM_MOD_SPIRIT_SHORT"] or 0) + val
        end

        -- Handle standard stats
        for _, sTable in pairs(TopFit.statList) do
            for _, statCode in pairs(sTable) do
                local statName = _G[statCode]
                if statName and statName ~= "" and string.find(cleanLine, statName) then
                    local pat1 = "%+?(%d+)%s*" .. statName
                    local pat2 = statName .. "%s*%+?(%d+)"
                    local val = tonumber(string.match(cleanLine, pat1) or string.match(cleanLine, pat2)) or 0
                    if val > 0 then
                        targetTable[statCode] = (targetTable[statCode] or 0) + val
                    end
                end
            end
        end

        -- Check Meta Gem % Critical Damage
        if string.find(cleanLine, "Critical Damage") then
            local critDmgVal = tonumber(string.match(cleanLine, "(%d+)%%")) or 0
            if critDmgVal > 0 then
                targetTable["ITEM_MOD_CRIT_DAMAGE_BONUS_SHORT"] = (targetTable["ITEM_MOD_CRIT_DAMAGE_BONUS_SHORT"] or 0) + critDmgVal
            end
        end
    end

    -- 3. SCAN SOCKETED GEMS IN ISOLATION (Only inspects the gem's own tooltip link)
    local gemBonus = {}
    local gems = {}
    local filledSocketColors = {}

    for i = 1, 4 do
        local gemName, gemLink = C_Item.GetItemGem(item, i)
        if gemLink or gemName then
            local activeGemLink = gemLink or gemName
            gems[i] = activeGemLink

            TopFit.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            TopFit.scanTooltip:SetHyperlink(activeGemLink)

            local gemColor = nil
            for lineIdx = 1, TopFit.scanTooltip:NumLines() do
                local leftLine = _G["TFScanTooltipTextLeft" .. lineIdx]
                local lineText = leftLine and leftLine:GetText()
                if lineText and lineText ~= "" then
                    -- Parse stats directly off the gem's isolated tooltip ONLY
                    ParseStatLine(lineText, gemBonus)

                    -- Detect gem socket color
                    if string.find(lineText, "Red") or string.find(lineText, "Rubidium") then
                        gemColor = "RED"
                    elseif string.find(lineText, "Yellow") or string.find(lineText, "Amber") then
                        gemColor = "YELLOW"
                    elseif string.find(lineText, "Blue") or string.find(lineText, "Sapphire") then
                        gemColor = "BLUE"
                    elseif string.find(lineText, "Meta") then
                        gemColor = "META"
                    end
                end
            end
            TopFit.scanTooltip:Hide()
            filledSocketColors[i] = gemColor or "PRISMATIC"
        end
    end

    -- 4. SCAN MAIN ITEM TOOLTIP (Only for Active Socket Bonus, Empty Sockets & Enchants)
    local enchantBonus = {}
    local emptySocketColors = {}
    local socketBonusInfo = nil

    TopFit.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    TopFit.scanTooltip:SetHyperlink(itemLink)
    local numLines = TopFit.scanTooltip:NumLines()

    local socketBonusString = _G["ITEM_SOCKET_BONUS"] or "Socket Bonus: %s"
    socketBonusString = string.gsub(socketBonusString, "%%s", "(.*)")

    local socketColorPatterns = {
        RED = _G["EMPTY_SOCKET_RED"],
        YELLOW = _G["EMPTY_SOCKET_YELLOW"],
        BLUE = _G["EMPTY_SOCKET_BLUE"],
        META = _G["EMPTY_SOCKET_META"],
        PRISMATIC = _G["EMPTY_SOCKET_PRISMATIC"],
    }

    for i = 1, numLines do
        local leftLine = _G["TFScanTooltipTextLeft" .. i]
        local lineText = leftLine and leftLine:GetText()

        if lineText and lineText ~= "" then
            local r, g, b = 1, 1, 1
            if leftLine.GetTextColor then
                r, g, b = leftLine:GetTextColor()
            end

            -- A. Active Socket Bonus
            if string.find(lineText, socketBonusString) then
                local isActive = (r < 0.1) -- Green text indicates active bonus
                local bonusText = string.gsub(lineText, "^" .. socketBonusString .. "$", "%1")
                if isActive then
                    ParseStatLine(bonusText, gemBonus)
                elseif #emptySocketColors > 0 then
                    for _, sTable in pairs(TopFit.statList) do
                        for _, statCode in pairs(sTable) do
                            if _G[statCode] and string.find(bonusText, _G[statCode]) then
                                local pat1 = "%+?(%d+)%s*" .. _G[statCode]
                                local pat2 = _G[statCode] .. "%s*%+?(%d+)"
                                local val = tonumber(string.match(bonusText, pat1) or string.match(bonusText, pat2)) or 0
                                if val > 0 then
                                    socketBonusInfo = { stat = statCode, value = val }
                                end
                            end
                        end
                    end
                end

            -- B. Empty Sockets
            else
                for color, pattern in pairs(socketColorPatterns) do
                    if pattern and lineText == pattern then
                        table.insert(emptySocketColors, color)
                        break
                    end
                end

                -- C. Active Enchants (Green text, excluding Equip, Use, Set, and Socket Bonus)
                if r < 0.1 and g > 0.9 and b < 0.1 then
                    if not string.find(lineText, "Equip:") and not string.find(lineText, "Use:") and not string.find(lineText, "Set:") and not string.find(lineText, "Socket Bonus") then
                        ParseStatLine(lineText, enchantBonus)
                    end
                end
            end
        end
    end
    TopFit.scanTooltip:Hide()

    if #filledSocketColors > 0 then
        socketBonusInfo = nil
    end

    -- 5. Set Name Scanning
    TopFit.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    TopFit.scanTooltip:SetHyperlink(itemLink)
    local setName = nil
    for i = 1, TopFit.scanTooltip:NumLines() do
        local leftLine = _G["TFScanTooltipTextLeft" .. i]
        local leftLineText = leftLine and leftLine:GetText()
        if leftLineText and string.find(leftLineText, "(.*)%s%([0-9]+/[0-9+]%)") then
            setName = select(3, string.find(leftLineText, "(.*)%s%([0-9]+/[0-9+]%)"))
            break
        end
    end
    TopFit.scanTooltip:Hide()

    if setName then
        itemBonus["SET: " .. setName] = 1
    end

    -- 6. Mana Regen Consolidation
    itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((itemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    itemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0 then itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end

    gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((gemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    gemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0 then gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end

    enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((enchantBonus["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    enchantBonus["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0 then enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end

    -- 7. Total Bonus Aggregation
    local totalBonus = {}
    for _, bonusTable in pairs({ itemBonus, gemBonus, enchantBonus }) do
        for stat, value in pairs(bonusTable) do
            totalBonus[stat] = (totalBonus[stat] or 0) + value
        end
    end

    local procInfo = TopFit.ParseItemProc and TopFit:ParseItemProc(itemLink)
    local hasUnscoredProc = false
    if procInfo then
        local effectiveValue = TopFit.GetProcEffectiveValue and TopFit:GetProcEffectiveValue(procInfo)
        if effectiveValue then
            totalBonus[procInfo.statKey] = (totalBonus[procInfo.statKey] or 0) + effectiveValue
        else
            hasUnscoredProc = true
        end
    end

    local result = {
        ["itemLink"] = itemLink,
        ["itemID"] = itemID,
        ["itemQuality"] = itemQuality,
        ["itemMinLevel"] = itemMinLevel,
        ["itemEquipLoc"] = itemEquipLoc,
        ["itemSubType"] = itemSubType,
        ["itemBonus"] = itemBonus,
        ["gems"] = gems,
        ["enchantBonus"] = enchantBonus,
        ["gemBonus"] = gemBonus,
        ["emptySocketColors"] = emptySocketColors,
        ["socketBonusInfo"] = socketBonusInfo,
        ["equipLocationsByType"] = TopFit:GetEquipLocationsByInvType(itemEquipLoc),
        ["totalBonus"] = totalBonus,
        ["procInfo"] = procInfo,
        ["hasUnscoredProc"] = hasUnscoredProc,
    }

    TopFit.db.global.itemCache[cacheKey] = result

    return result
end
-- calculate an item's score relative to a given set
function TopFit:CalculateItemScore(itemLink)
    local itemTable = TopFit:GetCachedItem(itemLink)
    if not itemTable then return end
    
    for setCode, setTable in pairs(TopFit.db.profile.sets) do
        local set = setTable.weights
        local caps = setTable.caps
        
        -- calculate item score
        local itemScore = 0
        local capsModifier = 0
        -- iterate given weights
        for stat, statValue in pairs(set) do
            if itemTable.totalBonus[stat] then
                -- check for hard cap on this stat
                if ((not caps) or (not caps[stat]) or (not TopFit:HasActiveHardCap(caps[stat]))) then
                    itemScore = itemScore + statValue * itemTable.totalBonus[stat]
                else
                    -- part of hard cap, score calculated extra
                    capsModifier = capsModifier + statValue * itemTable.totalBonus[stat]
                end
            end
        end
        
        -- also calculate raw item score
        local rawScore = 0
        local rawModifier = 0
        -- iterate given weights
        for stat, statValue in pairs(set) do
            if itemTable.itemBonus[stat] then
                -- check for hard cap on this stat
                if ((not caps) or (not caps[stat]) or (not TopFit:HasActiveHardCap(caps[stat]))) then
                    rawScore = rawScore + statValue * itemTable.itemBonus[stat]
                else
                    -- part of hard cap, score calculated extra
                    rawModifier = rawModifier + statValue * itemTable.totalBonus[stat]
                end
            end
        end
        
        -- credit empty sockets with the value of the best gem that could go in them (plus the
        -- item's socket bonus, if filling them would unlock it) -- otherwise an ungemmed item
        -- scores as if its sockets are worthless, when in practice they'd be filled immediately
        local potentialGemScore = TopFit:GetPotentialGemScore(itemTable, set, caps)
        itemScore = itemScore + potentialGemScore
        
        if not TopFit.scoresCache[itemLink] then
            TopFit.scoresCache[itemLink] = {}
        end
        
        --TODO: could be rewritten slightly to save some tables
        TopFit.scoresCache[itemLink][setCode] = {
            itemScore = itemScore,
            itemScoreWithoutCaps = itemScore + capsModifier,
            rawScore = rawScore,
            rawScoreWithoutCaps = rawScore + rawModifier,
        }
    end
end

-- calculate item scores
function TopFit:CalculateScores()
    -- iterate all cached items and recalculate their scores
    for itemLink, _ in pairs(TopFit.itemsCache) do
        TopFit:CalculateItemScore(itemLink)
    end
end

-- used by tooltip to decide which item slots to compare to
function TopFit:GetEquipLocationsByInvType(itemEquipLoc)
    if itemEquipLoc == "INVTYPE_2HWEAPON" then
        --TODO: check weapon type
        return {16}
    elseif itemEquipLoc == "INVTYPE_BODY" then
        return {4}
    elseif itemEquipLoc == "INVTYPE_CHEST" or itemEquipLoc == "INVTYPE_ROBE" then
        return {5}
    elseif itemEquipLoc == "INVTYPE_CLOAK" then
        return {15}
    elseif itemEquipLoc == "INVTYPE_FEET" then
        return {8}
    elseif itemEquipLoc == "INVTYPE_FINGER" then
        return {11, 12}
    elseif itemEquipLoc == "INVTYPE_HAND" then
        return {10}
    elseif itemEquipLoc == "INVTYPE_HEAD" then
        return {1}
    elseif itemEquipLoc == "INVTYPE_HOLDABLE" or itemEquipLoc == "INVTYPE_SHIELD" then
        return {17}
    elseif itemEquipLoc == "INVTYPE_LEGS" then
        return {7}
    elseif itemEquipLoc == "INVTYPE_NECK" then
        return {2}
    elseif itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" or itemEquipLoc == "INVTYPE_RELIC" or itemEquipLoc == "INVTYPE_THROWN" then
        return {18}
    elseif itemEquipLoc == "INVTYPE_SHOULDER" then
        return {3}
    elseif itemEquipLoc == "INVTYPE_TABARD" then
        return {19}
    elseif itemEquipLoc == "INVTYPE_TRINKET" then
        return {13, 14}
    elseif itemEquipLoc == "INVTYPE_WAIST" then
        return {6}
    elseif itemEquipLoc == "INVTYPE_WEAPON" then
        return {16, 17}
    elseif itemEquipLoc == "INVTYPE_WEAPONMAINHAND" then
        return {16}
    elseif itemEquipLoc == "INVTYPE_WEAPONOFFHAND" then
        return {17}
    elseif itemEquipLoc == "INVTYPE_WRIST" then
        return {9}
    end
    -- default / invalid location
    return {}
end



-- returns all equippable items, limited by slot, if given
function TopFit:GetEquippableItems(requestedSlotID)
    local itemListBySlot = {}
    local availableSlots = {}

    -- find available item ids for each slot
    for slotName, slotID in pairs(TopFit.slots) do
        itemListBySlot[slotID] = {}
        slotAvailableItems = GetInventoryItemsForSlot(slotID)
        if (slotAvailableItems) then
            for availableLocation, availableItemID in pairs(slotAvailableItems) do
                if (not availableSlots[availableItemID]) then
                    availableSlots[availableItemID] = { slotID }
                else
                    tinsertonce(availableSlots[availableItemID], slotID)
                end
            end
        end
        
        -- special handling for plate heirlooms
        if (TopFit.heirloomInfo.isPlateWearer and (slotID == 3 or slotID == 5) and UnitLevel("player") < 40) then
            for i = 1, #(TopFit.heirloomInfo.plateHeirlooms[slotID]) do
                if (not availableSlots[TopFit.heirloomInfo.plateHeirlooms[slotID][i]]) then
                    availableSlots[TopFit.heirloomInfo.plateHeirlooms[slotID][i]] = { slotID }
                else
                    tinsertonce(availableSlots[TopFit.heirloomInfo.plateHeirlooms[slotID][i]], slotID)
                end
            end
        end
        
        -- special handling for mail heirlooms
        if (TopFit.heirloomInfo.isMailWearer and (slotID == 3 or slotID == 5) and UnitLevel("player") < 40) then
            for i = 1, #(TopFit.heirloomInfo.mailHeirlooms[slotID]) do
                if (not availableSlots[TopFit.heirloomInfo.mailHeirlooms[slotID][i]]) then
                    availableSlots[TopFit.heirloomInfo.mailHeirlooms[slotID][i]] = { slotID }
                else
                    tinsertonce(availableSlots[TopFit.heirloomInfo.mailHeirlooms[slotID][i]], slotID)
                end
            end
        end
    end
    
    -- check player's bags
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            if itemLink then
                local itemID = string.gsub(itemLink, ".*|Hitem:([0-9]*):.*", "%1")
                itemID = tonumber(itemID)
                
                if (availableSlots[itemID]) then
                    -- check if item is BoE
                    local isBoE = false
                    TopFit.scanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
                    TopFit.scanTooltip:SetBagItem(bag, slot)
                    local numLines = TopFit.scanTooltip:NumLines()
                    for i = 1, numLines do
                        local leftLine = getglobal("TFScanTooltip".."TextLeft"..i)
                        local leftLineText = leftLine:GetText()
                        
                        if string.find(leftLineText, _G["ITEM_BIND_ON_EQUIP"]) then
                            isBoE = true
                            break
                        end
                    end
                    
                    for _, slotID in pairs(availableSlots[itemID]) do
                        tinsert(itemListBySlot[slotID], {
                            itemLink = itemLink,
                            isBoE = isBoE,
                            bag = bag,
                            slot = slot
                        })
                    end
                end
            end
        end
    end
    
    -- check player's inventory
    for _, invSlot in pairs(TopFit.slots) do
        local itemLink = GetInventoryItemLink("player", invSlot)
        if itemLink then
            local itemID = string.gsub(itemLink, ".*|Hitem:([0-9]*):.*", "%1")
            itemID = tonumber(itemID)
            
            if (availableSlots[itemID]) then
                for _, slotID in pairs(availableSlots[itemID]) do
                    tinsert(itemListBySlot[slotID], {
                        itemLink = itemLink,
                        isBoE = false, -- it is already equipped
                        slot = invSlot
                    })
                end
            end
        end
    end
    
    -- add virtual items
    if (TopFit.setCode and TopFit.db.profile.sets[TopFit.setCode].virtualItems and not TopFit.db.profile.sets[TopFit.setCode].skipVirtualItems) then
        for _, itemLink in pairs(TopFit.db.profile.sets[TopFit.setCode].virtualItems) do
            local item = TopFit:GetCachedItem(itemLink)
            local equipSlots = TopFit:GetEquipLocationsByInvType(item.itemEquipLoc)
            for _, slotID in pairs(equipSlots) do
                tinsert(itemListBySlot[slotID], {
                    itemLink = itemLink,
                    isBoE = false, -- if it's in virtual items, we want to include it
                    isVirtual = true
                })
            end
        end
    end
    
    if (requestedSlotID) then
        return itemListBySlot[requestedSlotID]
    else
        return itemListBySlot
    end
end

function TopFit:GetItemScore(itemLink, setCode, dontUseCaps, useRawItem)
    if not TopFit.scoresCache[itemLink] or not TopFit.scoresCache[itemLink][setCode] then return 0 end
    
    if dontUseCaps then
        if useRawItem then
            return TopFit.scoresCache[itemLink][setCode].rawScoreWithoutCaps
        else
            return TopFit.scoresCache[itemLink][setCode].itemScoreWithoutCaps
        end
    else
        if useRawItem then
            return TopFit.scoresCache[itemLink][setCode].rawScore
        else
            return TopFit.scoresCache[itemLink][setCode].itemScore
        end
    end
end

-- gets an item's info from the cache
function TopFit:GetCachedItem(itemLink)
    if not itemLink then return nil end
    TopFit:UpdateCache(itemLink)
    
    return TopFit.itemsCache[itemLink]
end
