-- Tooltip functions for TopFit (Retail WoW Compatibility)

local isProcessing = false

local function round(num, numDecimalPlaces)
    if not num then return 0 end
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

local function IsEquippableItemSafe(item)
    if not item then return false end
    if C_Item and C_Item.IsEquippableItem then
        return C_Item.IsEquippableItem(item)
    elseif IsEquippableItem then
        return IsEquippableItem(item)
    end
    return false
end

local function GetItemInfoSafe(item)
    if not item then return nil end
    local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if GetInfo then
        return GetInfo(item)
    end
    return nil
end

local function GetTooltipItem(tt, data)
    if data and data.hyperlink then
        return nil, data.hyperlink
    end
    if data and data.id then
        local _, link = GetItemInfoSafe(data.id)
        if link then return nil, link end
    end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local name, link = TooltipUtil.GetDisplayedItem(tt)
        if link then return name, link end
    end
    if tt and tt.GetItem then
        local name, link = tt:GetItem()
        if link then return name, link end
    end
    return nil, nil
end

local function UnpackLocationSafe(location)
    if not location then return nil end
    if C_EquipmentSet and C_EquipmentSet.UnpackLocation then
        local player, bank, bags, voidStorage, slot, bag = C_EquipmentSet.UnpackLocation(location)
        return player, bank, bags, voidStorage, slot, bag
    elseif EquipmentManager_UnpackLocation then
        local player, bank, bags, slot, bag = EquipmentManager_UnpackLocation(location)
        return player, bank, bags, false, slot, bag
    end
    return nil
end

local function TooltipAddCompareLines(tt, link)
    if not TopFit or not TopFit.GetCachedItem then return end
    local itemTable = TopFit:GetCachedItem(link)
    
    if not itemTable or not TopFit.db or not TopFit.db.profile or not TopFit.db.profile.sets then
        return
    end
    
    tt:AddLine(" ")
    tt:AddLine("Compared with your current items for each set:")
    for setCode, setTable in pairs(TopFit.db.profile.sets) do
        if not setTable.excludeFromTooltip then
            local setName = TopFit.GenerateSetName and TopFit:GenerateSetName(setTable.name) or setTable.name
            local setID = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID and C_EquipmentSet.GetEquipmentSetID(setName)
            
            local itemPositions = setID and C_EquipmentSet.GetItemLocations(setID)
            local itemIDs = setID and C_EquipmentSet.GetItemIDs(setID)
            local itemLinks = {}
            
            if itemPositions then
                for slotID, itemLocation in pairs(itemPositions) do
                    if itemLocation and itemLocation ~= 1 and itemLocation ~= 0 then
                        local itemLink = nil
                        local player, bank, bags, voidStorage, slot, bag = UnpackLocationSafe(itemLocation)
                        if player then
                            if voidStorage or bank then
                                local storedItemID = itemIDs and itemIDs[slotID]
                                if storedItemID and storedItemID ~= 1 and storedItemID ~= 0 then
                                    _, itemLink = GetItemInfoSafe(storedItemID)
                                end
                            elseif bags and bag and slot and C_Container and C_Container.GetContainerItemLink then
                                itemLink = C_Container.GetContainerItemLink(bag, slot)
                            elseif slot then
                                itemLink = GetInventoryItemLink("player", slot)
                            end
                        end
                        itemLinks[slotID] = itemLink
                    end
                end
            end
                
            for _, slotID in pairs(itemTable.equipLocationsByType or {}) do
                local itemID = nil
                local itemLink = itemLinks[slotID] or (setTable.calculatedItems and setTable.calculatedItems[slotID])
                local rawScore, asIsScore, rawCompareScore, asIsCompareScore = 0, 0, 0, 0
                local extraText = ""
                local compareTable = nil
                local itemTable2 = nil
                local compareTable2 = nil
                local compareNotCached = false
                
                if TopFit.GetItemScore then
                    rawScore = TopFit:GetItemScore(itemTable.itemLink, setCode, false, true)
                    asIsScore = TopFit:GetItemScore(itemTable.itemLink, setCode, false, false)
                end
                
                if not itemLink and itemIDs and itemIDs[slotID] and itemIDs[slotID] ~= 1 and itemIDs[slotID] ~= 0 then
                    _, itemLink = GetItemInfoSafe(itemIDs[slotID])
                end

                if itemLink then
                    compareTable = TopFit:GetCachedItem(itemLink)
                    if not compareTable then
                        compareNotCached = true
                    end
                end
                
                if compareTable and TopFit.GetItemScore then
                    rawCompareScore = TopFit:GetItemScore(compareTable.itemLink, setCode, false, true)
                    asIsCompareScore = TopFit:GetItemScore(compareTable.itemLink, setCode, false, false)
                end
                
                local ratio, rawRatio = 1, 1
                if rawCompareScore ~= 0 then
                    rawRatio = rawScore / rawCompareScore
                end
                
                if asIsCompareScore ~= 0 then
                    ratio = asIsScore / asIsCompareScore
                end
                
                local function percentilize(r, score, compScore)
                    if compareNotCached then
                        return "|cff808080?|r"
                    end
                    if not compareTable or compScore == 0 then
                        if score > 0 then
                            return "|cff00ff00+" .. round(score, 1) .. " pts|r"
                        elseif score < 0 then
                            return "|cffff0000" .. round(score, 1) .. " pts|r"
                        else
                            return "|cffffff000 pts|r"
                        end
                    end

                    if r > 11 then
                        local diff = score - compScore
                        return "|cff00ff00+" .. round(diff, 1) .. " pts|r"
                    elseif r > 1.0001 then
                        return "|cff00ff00+" .. round((r - 1) * 100, 1) .. "%|r"
                    elseif r >= 0.9999 then
                        return "|cffffff000%|r"
                    elseif r < -9 then
                        return "|cffff0000" .. round((r - 1) * 100, 1) .. "%|r"
                    else
                        return "|cffff0000" .. round((r - 1) * 100, 1) .. "%|r"
                    end
                end
                
                local compareItemText = ""
                if compareNotCached then
                    compareItemText = "Item not in cache!"
                elseif not compareTable then
                    compareItemText = "No item in set"
                else
                    compareItemText = compareTable.itemLink or ""
                end
                
                local rawFormatted = percentilize(rawRatio, rawScore, rawCompareScore)
                local asIsFormatted = percentilize(ratio, asIsScore, asIsCompareScore)

                if rawFormatted ~= asIsFormatted then
                    tt:AddDoubleLine("[" .. rawFormatted .. "/" .. asIsFormatted .. "] - " .. compareItemText .. extraText, setTable.name)
                else
                    tt:AddDoubleLine("[" .. rawFormatted .. "] - " .. compareItemText .. extraText, setTable.name)
                end
            end
        end
    end
end

local function TooltipAddLines(tt, link)
    if not TopFit or not TopFit.GetCachedItem then return end
    local itemTable = TopFit:GetCachedItem(link)
    if not itemTable then return end
    
    if TopFit.db and TopFit.db.profile and TopFit.db.profile.debugMode then
        tt:AddLine("Item stats as seen by TopFit:", 0.5, 0.9, 1)
        if itemTable["itemBonus"] then
            for stat, value in pairs(itemTable["itemBonus"]) do
                if not string.find(stat, "SET: ") then
                    local valueString = ""
                    local first = true
                    for _, setTable in pairs(TopFit.db.profile.sets or {}) do
                        local weightedValue = (setTable.weights and setTable.weights[stat] or 0) * value
                        if first then
                            first = false
                        else
                            valueString = valueString .. " / "
                        end
                        valueString = valueString .. (tonumber(weightedValue) or "0")
                    end
                    tt:AddDoubleLine("  +" .. value .. " " .. (_G[stat] or stat), valueString, 0.5, 0.9, 1)
                end
            end
        end
        
        if itemTable["enchantBonus"] then
            tt:AddLine("Enchant:", 1, 0.9, 0.5)
            for stat, value in pairs(itemTable["enchantBonus"]) do
                local valueString = ""
                local first = true
                for _, setTable in pairs(TopFit.db.profile.sets or {}) do
                    local weightedValue = (setTable.weights and setTable.weights[stat] or 0) * value
                    if first then
                        first = false
                    else
                        valueString = valueString .. " / "
                    end
                    valueString = valueString .. (tonumber(weightedValue) or "0")
                end
                tt:AddDoubleLine("  +" .. value .. " " .. (_G[stat] or stat), valueString, 1, 0.9, 0.5)
            end
        end
        
        if itemTable["gemBonus"] then
            local first = true
            for stat, value in pairs(itemTable["gemBonus"]) do
                if first then
                    first = false
                    tt:AddLine("Gems:", 0.8, 0.2, 0)
                end
                
                local valueString = ""
                local firstWeight = true
                for _, setTable in pairs(TopFit.db.profile.sets or {}) do
                    local weightedValue = (setTable.weights and setTable.weights[stat] or 0) * value
                    if firstWeight then
                        firstWeight = false
                    else
                        valueString = valueString .. " / "
                    end
                    valueString = valueString .. (tonumber(weightedValue) or "0")
                end
                tt:AddDoubleLine("  +" .. value .. " " .. (_G[stat] or stat), valueString, 0.8, 0.2, 0)
            end
        end
    end
    
    if TopFit.db and TopFit.db.profile and TopFit.db.profile.showTooltip then
        local first = true
        for setCode, setTable in pairs(TopFit.db.profile.sets or {}) do
            if not setTable.excludeFromTooltip then
                if first then
                    first = false
                    tt:AddLine("Set Values:", 0.6, 1, 0.7)
                end
                local score = TopFit.GetItemScore and TopFit:GetItemScore(itemTable.itemLink, setCode) or 0
                tt:AddLine("  " .. round(score, 2) .. " - " .. (setTable.name or ""), 0.6, 1, 0.7)
            end
        end
    end
end

-- Hook tooltip processing via TooltipDataProcessor (Modern Retail API)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if isProcessing then return end
        if tt ~= GameTooltip and tt ~= ItemRefTooltip and tt ~= ShoppingTooltip1 and tt ~= ShoppingTooltip2 then
            return
        end

        isProcessing = true
        local _, link = GetTooltipItem(tt, data)
        if link and IsEquippableItemSafe(link) then
            TooltipAddLines(tt, link)
            
            if (tt == GameTooltip or tt == ItemRefTooltip) and TopFit and TopFit.db and TopFit.db.profile and TopFit.db.profile.showComparisonTooltip and not TopFit.isBlocked then
                TooltipAddCompareLines(tt, link)
            end
        end
        isProcessing = false
    end)
else
    local function OnTooltipSetItem(self)
        if self == TopFit.scanTooltip or self == TFScanTooltip then return end
        local _, link = GetTooltipItem(self)
        if link and IsEquippableItemSafe(link) then
            TooltipAddLines(self, link)
            if (self == GameTooltip or self == ItemRefTooltip) and TopFit and TopFit.db and TopFit.db.profile and TopFit.showComparisonTooltip and not TopFit.isBlocked then
                TooltipAddCompareLines(self, link)
            end
        end
    end

    if GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ItemRefTooltip and ItemRefTooltip.HasScript and ItemRefTooltip:HasScript("OnTooltipSetItem") then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ShoppingTooltip1 and ShoppingTooltip1.HasScript and ShoppingTooltip1:HasScript("OnTooltipSetItem") then
        ShoppingTooltip1:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ShoppingTooltip2 and ShoppingTooltip2.HasScript and ShoppingTooltip2:HasScript("OnTooltipSetItem") then
        ShoppingTooltip2:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
end