--[[ inventory management and caching

interesting variables:
TopFit.itemsCache - item Tables, indexed by itemLink
TopFit.scoresCache - scores, indexed by itemLink and setCode

]]--

-- Ensure TopFit.slots is initialized
TopFit.slots = TopFit.slots or {
    HeadSlot = 1,
    NeckSlot = 2,
    ShoulderSlot = 3,
    ShirtSlot = 4,
    ChestSlot = 5,
    WaistSlot = 6,
    LegsSlot = 7,
    FeetSlot = 8,
    WristSlot = 9,
    HandsSlot = 10,
    Finger0Slot = 11,
    Finger1Slot = 12,
    Trinket0Slot = 13,
    Trinket1Slot = 14,
    BackSlot = 15,
    MainHandSlot = 16,
    SecondaryHandSlot = 17,
    RangedSlot = 18,
    TabardSlot = 19,
}

local function tinsertonce(tbl, data)
    local found = false
    for _, v in pairs(tbl) do
        if v == data then
            found = true
            break
        end
    end
    if not found then
        tinsert(tbl, data)
    end
end

-- gather all items from inventory and bags, save their info to cache
function TopFit:collectItems(bag)
    TopFit.characterLevel = UnitLevel("player")
    
    local maxBags = (NUM_BAG_SLOTS or 4) + (NUM_REAGENT_BAG_SLOTS or 0)
    if bag and bag >= 0 and bag <= maxBags then
        -- only check a specific bag (used on BAG_UPDATE)
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local item = C_Container.GetContainerItemLink(bag, slot)
            if item then
                TopFit:UpdateCache(item)
            end
        end
    else
        -- check all bags
        for bagID = 0, maxBags do
            local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
            for slot = 1, numSlots do
                local item = C_Container.GetContainerItemLink(bagID, slot)
                if item then
                    TopFit:UpdateCache(item)
                end
            end
        end
        
        -- check equipped items
        for _, invSlot in pairs(TopFit.slots) do
            local item = GetInventoryItemLink("player", invSlot)
            if item then
                TopFit:UpdateCache(item)
            end
        end
    end
end

-- collect item information if necessary
function TopFit:UpdateCache(item)
    if item and (not TopFit.itemsCache[item]) then
        local isEquippable = (C_Item and C_Item.IsEquippableItem and C_Item.IsEquippableItem(item))
            or (IsEquippableItem and IsEquippableItem(item))
            
        if isEquippable then
            local itemTable = TopFit:GetItemInfoTable(item)
            if itemTable then
                TopFit.itemsCache[item] = itemTable
                TopFit:CalculateItemScore(item)
            end
        end
    end
end

TopFit.pendingItemInfoRequests = TopFit.pendingItemInfoRequests or {}

-- re-runs GetItemInfoTable for an item once its async data has loaded
function TopFit:RescanPendingItem(itemID)
    if not itemID then return end
    local strID = tostring(itemID)
    if TopFit.itemsCache then
        for link in pairs(TopFit.itemsCache) do
            if link:find("item:" .. strID .. ":") or link:find("item:" .. strID .. "|") then
                TopFit.itemsCache[link] = nil
            end
        end
    end
    TopFit:collectItems()
end

-- find out all we need to know about an item
function TopFit:GetItemInfoTable(item)
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetInfo(item)
    if not itemLink then
        local itemID = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
        if itemID and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
            TopFit.pendingItemInfoRequests[itemID] = true
        end
        return nil
    end

    -- Universal Item Link Cache Key (Matches full link specifiers across Retail & Classic)
    local cacheKey = string.match(itemLink, "item:([%d:-]+)") or tostring(item)

    -- SavedVariables Cache Lookup
    if TopFit.db and TopFit.db.global and TopFit.db.global.itemCache then
        if TopFit.db.global.itemCache[cacheKey] then
            return TopFit.db.global.itemCache[cacheKey]
        end
    end

    local itemID = tonumber(string.match(itemLink, "item:(%d+)")) or 0

    -- Base Item Stats
    local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    local itemBonus = (GetStats and GetStats(itemLink)) or {}

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
        local cleanLine = string.gsub(lineText, "%(.-%)", "")

        local allStatsVal = string.match(cleanLine, "%+?(%d+)%s+[Aa]ll%s+[Ss]tats")
        if allStatsVal then
            local val = tonumber(allStatsVal) or 0
            targetTable["ITEM_MOD_STRENGTH_SHORT"] = (targetTable["ITEM_MOD_STRENGTH_SHORT"] or 0) + val
            targetTable["ITEM_MOD_AGILITY_SHORT"] = (targetTable["ITEM_MOD_AGILITY_SHORT"] or 0) + val
            targetTable["ITEM_MOD_STAMINA_SHORT"] = (targetTable["ITEM_MOD_STAMINA_SHORT"] or 0) + val
            targetTable["ITEM_MOD_INTELLECT_SHORT"] = (targetTable["ITEM_MOD_INTELLECT_SHORT"] or 0) + val
            targetTable["ITEM_MOD_SPIRIT_SHORT"] = (targetTable["ITEM_MOD_SPIRIT_SHORT"] or 0) + val
        end

        for _, sTable in pairs(TopFit.statList or {}) do
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

        if string.find(cleanLine, "Critical Damage") then
            local critDmgVal = tonumber(string.match(cleanLine, "(%d+)%%")) or 0
            if critDmgVal > 0 then
                targetTable["ITEM_MOD_CRIT_DAMAGE_BONUS_SHORT"] = (targetTable["ITEM_MOD_CRIT_DAMAGE_BONUS_SHORT"] or 0) + critDmgVal
            end
        end
    end

    -- Scan socketed gems
    -- CONFIRMED 2026-09-26 (Dan): Forever has no Jewelcrafting, so no item will ever have a gem
    -- socketed -- this loop is safely inert (C_Item.GetItemGem always returns nil, so gemBonus/
    -- gems/filledSocketColors stay empty) but left in place rather than removed, since several
    -- other places in this file consume those tables and tracing every one of them to confirm
    -- an empty table is always equivalent to "never ran" wasn't worth the risk for what's
    -- already a correctly-inert code path. Safe to remove properly in a later cleanup pass.
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
                    ParseStatLine(lineText, gemBonus)

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

    -- Scan item tooltip
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

            if string.find(lineText, socketBonusString) then
                local isActive = (r < 0.1)
                local bonusText = string.gsub(lineText, "^" .. socketBonusString .. "$", "%1")
                if isActive then
                    ParseStatLine(bonusText, gemBonus)
                elseif #emptySocketColors > 0 then
                    for _, sTable in pairs(TopFit.statList or {}) do
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
            else
                for color, pattern in pairs(socketColorPatterns) do
                    if pattern and lineText == pattern then
                        table.insert(emptySocketColors, color)
                        break
                    end
                end

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

    -- Set Name Scanning
    TopFit.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    TopFit.scanTooltip:SetHyperlink(itemLink)
    local setName = nil
    for i = 1, TopFit.scanTooltip:NumLines() do
        local leftLine = _G["TFScanTooltipTextLeft" .. i]
        local leftLineText = leftLine and leftLine:GetText()
        if leftLineText then
            local matchName = string.match(leftLineText, "^(.-)%s*%((%d+)/%d+%)")
            if matchName then
                setName = matchName
                break
            end
        end
    end
    TopFit.scanTooltip:Hide()

    if setName then
        itemBonus["SET: " .. setName] = 1
    end

    -- Mana Regen Consolidation
    itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((itemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    itemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0 then itemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end

    gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((gemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    gemBonus["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0 then gemBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end

    enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = ((enchantBonus["ITEM_MOD_POWER_REGEN0_SHORT"] or 0) + (enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0))
    enchantBonus["ITEM_MOD_POWER_REGEN0_SHORT"] = nil
    if enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] == 0 then enchantBonus["ITEM_MOD_MANA_REGENERATION_SHORT"] = nil end

    -- Total Bonus Aggregation
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

    -- Save to Global Persistent Cache
    if TopFit.db and TopFit.db.global then
        TopFit.db.global.itemCache = TopFit.db.global.itemCache or {}
        TopFit.db.global.itemCache[cacheKey] = result
    end

    return result
end

function TopFit:CalculateItemScore(itemLink)
    local itemTable = TopFit.itemsCache[itemLink] or TopFit:GetCachedItem(itemLink)
    if not itemTable or not TopFit.db or not TopFit.db.profile or not TopFit.db.profile.sets then return end
    
    TopFit.scoresCache[itemLink] = TopFit.scoresCache[itemLink] or {}

    for setCode, setTable in pairs(TopFit.db.profile.sets) do
        local set = setTable.weights or {}
        local caps = setTable.caps
        
        local itemScore = 0
        local capsModifier = 0
        for stat, statValue in pairs(set) do
            if itemTable.totalBonus[stat] then
                if ((not caps) or (not caps[stat]) or (not TopFit:HasActiveHardCap(caps[stat]))) then
                    itemScore = itemScore + statValue * itemTable.totalBonus[stat]
                else
                    capsModifier = capsModifier + statValue * itemTable.totalBonus[stat]
                end
            end
        end
        
        local rawScore = 0
        local rawModifier = 0
        for stat, statValue in pairs(set) do
            if itemTable.itemBonus[stat] then
                if ((not caps) or (not caps[stat]) or (not TopFit:HasActiveHardCap(caps[stat]))) then
                    rawScore = rawScore + statValue * itemTable.itemBonus[stat]
                else
                    rawModifier = rawModifier + statValue * itemTable.totalBonus[stat]
                end
            end
        end
        
        local potentialGemScore = TopFit.GetPotentialGemScore and TopFit:GetPotentialGemScore(itemTable, set, caps) or 0
        itemScore = itemScore + potentialGemScore
        
        TopFit.scoresCache[itemLink][setCode] = {
            itemScore = itemScore,
            itemScoreWithoutCaps = itemScore + capsModifier,
            rawScore = rawScore,
            rawScoreWithoutCaps = rawScore + rawModifier,
        }
    end
end

function TopFit:CalculateScores()
    for itemLink, _ in pairs(TopFit.itemsCache) do
        TopFit:CalculateItemScore(itemLink)
    end
end

function TopFit:GetEquipLocationsByInvType(itemEquipLoc)
    if itemEquipLoc == "INVTYPE_2HWEAPON" then
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
    return {}
end

-- Direct Equippable Items Collector (Maps to both numeric slot IDs and string slot names)
function TopFit:GetEquippableItems(requestedSlotID)
    local itemListBySlot = {}

    -- Initialize empty lists for both numeric IDs and string names
    for slotName, slotID in pairs(TopFit.slots or {}) do
        itemListBySlot[slotID] = itemListBySlot[slotID] or {}
        itemListBySlot[slotName] = itemListBySlot[slotID]
    end

    local processedKeys = {}

    local function AddItemToSlots(itemLink, bag, slot)
        if not itemLink then return end
        local key = itemLink .. ":" .. (bag or "nil") .. ":" .. (slot or "nil")
        if processedKeys[key] then return end
        processedKeys[key] = true

        local itemTable = TopFit:GetCachedItem(itemLink)
        local equipLoc = itemTable and itemTable.itemEquipLoc
        if not equipLoc then
            local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            equipLoc = select(9, GetInfo(itemLink))
        end

        if equipLoc and equipLoc ~= "" then
            local targetSlots = TopFit:GetEquipLocationsByInvType(equipLoc)
            if targetSlots and #targetSlots > 0 then
                local isBoE = false
                if bag and slot then
                    TopFit.scanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
                    TopFit.scanTooltip:SetBagItem(bag, slot)
                    for i = 1, TopFit.scanTooltip:NumLines() do
                        local leftLine = _G["TFScanTooltipTextLeft" .. i]
                        local leftLineText = leftLine and leftLine:GetText()
                        if leftLineText and string.find(leftLineText, _G["ITEM_BIND_ON_EQUIP"] or "Bind on Equip") then
                            isBoE = true
                            break
                        end
                    end
                    TopFit.scanTooltip:Hide()
                end

                for _, slotID in ipairs(targetSlots) do
                    itemListBySlot[slotID] = itemListBySlot[slotID] or {}
                    tinsert(itemListBySlot[slotID], {
                        itemLink = itemLink,
                        isBoE = isBoE,
                        bag = bag,
                        slot = slot,
                    })
                end
            end
        end
    end

    -- 1. Scan Equipped Items
    for _, invSlot in pairs(TopFit.slots or {}) do
        local itemLink = GetInventoryItemLink("player", invSlot)
        if itemLink then
            AddItemToSlots(itemLink, nil, invSlot)
        end
    end

    -- 2. Scan Bags
    local maxBags = (NUM_BAG_SLOTS or 4) + (NUM_REAGENT_BAG_SLOTS or 0)
    for bag = 0, maxBags do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            if itemLink then
                AddItemToSlots(itemLink, bag, slot)
            end
        end
    end

    -- 3. Add Virtual Items
    if (TopFit.setCode and TopFit.db and TopFit.db.profile and TopFit.db.profile.sets[TopFit.setCode] and TopFit.db.profile.sets[TopFit.setCode].virtualItems and not TopFit.db.profile.sets[TopFit.setCode].skipVirtualItems) then
        for _, itemLink in pairs(TopFit.db.profile.sets[TopFit.setCode].virtualItems) do
            local item = TopFit:GetCachedItem(itemLink)
            if item then
                local equipSlots = TopFit:GetEquipLocationsByInvType(item.itemEquipLoc)
                for _, slotID in pairs(equipSlots) do
                    itemListBySlot[slotID] = itemListBySlot[slotID] or {}
                    tinsert(itemListBySlot[slotID], {
                        itemLink = itemLink,
                        isBoE = false,
                        isVirtual = true
                    })
                end
            end
        end
    end

    if requestedSlotID then
        return itemListBySlot[requestedSlotID] or {}
    else
        return itemListBySlot
    end
end

-- Safely retrieves scores, automatically calculating on-demand if missing
function TopFit:GetItemScore(itemLink, setCode, dontUseCaps, useRawItem)
    if not itemLink or not setCode then return 0 end

    -- On-demand calculation if score entry doesn't exist yet for this setCode
    if not TopFit.scoresCache[itemLink] or not TopFit.scoresCache[itemLink][setCode] then
        TopFit:CalculateItemScore(itemLink)
    end

    local scoreEntry = TopFit.scoresCache[itemLink] and TopFit.scoresCache[itemLink][setCode]
    if not scoreEntry then return 0 end
    
    if dontUseCaps then
        return useRawItem and scoreEntry.rawScoreWithoutCaps or scoreEntry.itemScoreWithoutCaps
    else
        return useRawItem and scoreEntry.rawScore or scoreEntry.itemScore
    end
end

-- Multi-tier cache resolution to handle variations in WoW itemLink strings
function TopFit:GetCachedItem(itemLink)
    if not itemLink then return nil end

    -- 1. Direct exact link match in runtime memory
    if TopFit.itemsCache[itemLink] then
        return TopFit.itemsCache[itemLink]
    end

    -- 2. Attempt cache update for this link
    TopFit:UpdateCache(itemLink)
    if TopFit.itemsCache[itemLink] then
        return TopFit.itemsCache[itemLink]
    end

    -- 3. Soft Match Fallback: Match by extracted itemID / specifier if link format differs
    local itemIDSpec = string.match(itemLink, "item:([%d:-]+)") or string.match(itemLink, "item:(%d+)")
    if itemIDSpec then
        for cachedLink, itemTable in pairs(TopFit.itemsCache) do
            if cachedLink:find("item:" .. itemIDSpec, 1, true) or (itemTable.itemID and tostring(itemTable.itemID) == itemIDSpec) then
                TopFit.itemsCache[itemLink] = itemTable
                return itemTable
            end
        end

        -- Check global persistent SavedVariables cache
        if TopFit.db and TopFit.db.global and TopFit.db.global.itemCache and TopFit.db.global.itemCache[itemIDSpec] then
            local itemTable = TopFit.db.global.itemCache[itemIDSpec]
            TopFit.itemsCache[itemLink] = itemTable
            return itemTable
        end
    end

    return nil
end