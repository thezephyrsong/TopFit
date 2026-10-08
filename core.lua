-- utility for rounding
function round(input, places)
    if not places then
        places = 0
    end
    if type(input) == "number" and type(places) == "number" then
        local pow = 1
        for i = 1, ceil(places) do
            pow = pow * 10
        end
        return floor(input * pow + 0.5) / pow
    else
        return input
    end
end

-- create Addon object
TopFit = LibStub("AceAddon-3.0"):NewAddon("TopFit", "AceConsole-3.0")

TopFit.hasClassicTalentAPI = (type(GetNumTalentTabs) == "function") and (type(GetTalentInfo) == "function")

function TopFit:GetNumTalentTabsSafe()
    if not TopFit.hasClassicTalentAPI then return 0 end
    return GetNumTalentTabs() or 0
end

function TopFit:GetNumTalentsSafe(tab)
    if not TopFit.hasClassicTalentAPI or type(GetNumTalents) ~= "function" then return 0 end
    return GetNumTalents(tab) or 0
end

function TopFit:GetTalentTabNameSafe(tab)
    if not TopFit.hasClassicTalentAPI or type(GetTalentTabInfo) ~= "function" then return nil end
    return GetTalentTabInfo(tab)
end

function TopFit:GetTalentRankSafe(tab, index)
    if not TopFit.hasClassicTalentAPI then return 0, nil, nil end
    local name, _, _, _, currentRank, maxRank = GetTalentInfo(tab, index)
    return currentRank or 0, name, maxRank
end

-- Scans active Retail C_ClassTalents / C_Traits loadout and returns active ranks
function TopFit:GetRetailTalentRanks()
    local ranksBySpellID = {}
    local ranksByName = {}

    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then
        return ranksBySpellID, ranksByName
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return ranksBySpellID, ranksByName end

    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then return ranksBySpellID, ranksByName end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.activeRank and nodeInfo.activeRank > 0 then
                    local entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
                    if entryID then
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo and defInfo.spellID then
                                ranksBySpellID[defInfo.spellID] = nodeInfo.activeRank

                                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(defInfo.spellID)
                                local spellName = spellInfo and spellInfo.name
                                if spellName then
                                    ranksByName[spellName] = nodeInfo.activeRank
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return ranksBySpellID, ranksByName
end

-- debug function
function TopFit:Debug(text)
    if self.db.profile.debugMode then
        TopFit:Print("Debug: "..text)
    end
end

-- debug function
function TopFit:Warning(text)
    --TODO: create table of warnings and dont print any multiples
end

-- joins any number of tables together
function TopFit:JoinTables(...)
    local result = {}
    local tab
    
    for i = 1, select("#", ...) do
        tab = select(i, ...)
        if tab then
            for index, value in pairs(tab) do
                tinsert(result, value)
            end
        end
    end
    
    return result
end

function TopFit:EquipRecommendedItems()
    if (not TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].skipVirtualItems) and TopFit.db.profile.sets[TopFit.setCode].virtualItems and #(TopFit.db.profile.sets[TopFit.setCode].virtualItems) > 0 then
        TopFit:Print("No items will be equipped because virtual items were included in the set calculation.")
        
        TopFit.ProgressFrame:StoppedCalculation()
        TopFit.isBlocked = false
        TopFit.ignoreCapsForCalculation = nil
        
        if (#TopFit.workSetList > 0) then
            TopFit:CalculateSets()
        end
        return
    end
    
    TopFit.updateEquipmentCounter = 10000
    TopFit.equipRetries = 0
    TopFit.updateFrame:SetScript("OnUpdate", TopFit.onUpdateForEquipment)
end

function TopFit:onUpdateForEquipment()
    if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then
        return
    end

    local allDone = true
    for slotID, recTable in pairs(TopFit.itemRecommendations) do
        if (TopFit:GetItemScore(recTable.locationTable.itemLink, TopFit.setCode, TopFit.ignoreCapsForCalculation) > 0) then
            local slotItemLink = GetInventoryItemLink("player", slotID)
            if (slotItemLink ~= recTable.locationTable.itemLink) then
                allDone = false
            end
        end
    end
    
    TopFit.updateEquipmentCounter = TopFit.updateEquipmentCounter + 1
    
    if (TopFit.updateEquipmentCounter > 100) then
        for slotID, recTable in pairs(TopFit.itemRecommendations) do
            local slotItemLink = GetInventoryItemLink("player", slotID)
            if (slotItemLink ~= recTable.locationTable.itemLink) then
                local found = false
                local foundBag, foundSlot
                for bag = 0, 4 do
                    for slot = 1, C_Container.GetContainerNumSlots(bag) do
                        local itemLink = C_Container.GetContainerItemLink(bag,slot)
                        
                        if itemLink == recTable.locationTable.itemLink then
                            foundBag = bag
                            foundSlot = slot
                            found = true
                            break
                        end
                    end
                end
                
                if not found then
                    for _, invSlot in pairs(TopFit.slots) do
                        local itemLink = GetInventoryItemLink("player", invSlot)
                        
                        if itemLink == recTable.locationTable.itemLink then
                            foundBag = nil
                            foundSlot = invSlot
                            found = true
                            break
                        end
                    end
                end
                
                if not found then
                    TopFit:Print(recTable.locationTable.itemLink.." could not be found in your inventory for equipping! Did you remove it during calculation?")
                    TopFit.itemRecommendations[slotID] = nil
                else
                    ClearCursor()
                    if foundBag then
                        C_Container.PickupContainerItem(foundBag, foundSlot)
                    else
                        PickupInventoryItem(foundSlot)
                    end
                    EquipCursorItem(slotID)
                end
            end
        end
        
        TopFit.updateEquipmentCounter = 0
        TopFit.equipRetries = TopFit.equipRetries + 1
    end
    
    if ((allDone) or (TopFit.equipRetries > 5)) then
        if (not allDone) then
            TopFit:Print("Oh. I am sorry, but I must have made a mistake. I cannot equip all the items I chose:")
            
            for slotID, recTable in pairs(TopFit.itemRecommendations) do
                local slotItemLink = GetInventoryItemLink("player", slotID)
                if (slotItemLink ~= recTable.locationTable.itemLink) then
                    TopFit:Print("  "..recTable.locationTable.itemLink.." into Slot "..slotID.." ("..TopFit.slotNames[slotID]..")")
                    TopFit.itemRecommendations[slotID] = nil
                end
            end
        end
        
        TopFit:Debug("All Done!")
        TopFit.updateFrame:SetScript("OnUpdate", nil)
        TopFit.ProgressFrame:StoppedCalculation()
        
        local ignoredSlots = {}
        for _, slotID in pairs(TopFit.slots) do
            if not TopFit.itemRecommendations[slotID] then
                tinsert(ignoredSlots, slotID)
            end
        end
        TopFit:SaveGearToEquipmentSet(TopFit:GenerateSetName(TopFit.currentSetName), ignoredSlots)
    
        TopFit.isBlocked = false
        TopFit.ignoreCapsForCalculation = nil
        
        if (#TopFit.workSetList > 0) then
            TopFit:CalculateSets()
        end
    end
end

local function GetDefaultEquipmentSetIcon()
    for _, slotID in ipairs({ 16, 1, 5, 17, 3 }) do
        local icon
        if GetInventoryItemTexture then icon = GetInventoryItemTexture("player", slotID) end
        if not icon then
            local link = GetInventoryItemLink("player", slotID)
            if link and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(link) end
        end
        if icon then return icon end
    end
    return 134400
end

function TopFit:GetEquipmentSetIDSafe(setName)
    return C_EquipmentSet.GetEquipmentSetID(setName)
end

function TopFit:SaveGearToEquipmentSet(setName, ignoredSlots, verbose)
    if not C_EquipmentSet.CanUseEquipmentSets() then
        TopFit:Print("Could not save equipment set '"..setName.."': C_EquipmentSet.CanUseEquipmentSets() returned false.")
        return false
    end

    pcall(C_EquipmentSet.ClearIgnoredSlotsForSave)
    local ignoreFailed = false
    if ignoredSlots then
        for _, slotID in ipairs(ignoredSlots) do
            if not pcall(C_EquipmentSet.IgnoreSlotForSave, slotID) then
                ignoreFailed = true
            end
        end
    end

    local setID = TopFit:GetEquipmentSetIDSafe(setName)
    local created = false
    local ok, err
    if setID then
        ok, err = pcall(C_EquipmentSet.SaveEquipmentSet, setID)
    else
        created = true
        ok, err = pcall(C_EquipmentSet.CreateEquipmentSet, setName, GetDefaultEquipmentSetIcon())
        setID = TopFit:GetEquipmentSetIDSafe(setName)
    end

    pcall(C_EquipmentSet.ClearIgnoredSlotsForSave)

    if not ok then
        TopFit:Print(("Failed to %s equipment set '%s': %s"):format(created and "create" or "update", setName, tostring(err)))
        return false
    end

    local function PrintAllSets(reason)
        TopFit:Print(reason)
        local okNum, numSets = pcall(C_EquipmentSet.GetNumEquipmentSets)
        if okNum then TopFit:Print("C_EquipmentSet.GetNumEquipmentSets() = "..tostring(numSets)) end
        local okIDs, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
        if okIDs and ids then
            TopFit:Print("Equipment sets on this character ("..#ids.."):")
            for _, id in ipairs(ids) do
                local name, _, _, _, items, equipped = C_EquipmentSet.GetEquipmentSetInfo(id)
                TopFit:Print(("  [%s] %s -- %s item(s), %s equipped"):format(tostring(id), tostring(name), tostring(items), tostring(equipped)))
            end
        else
            TopFit:Print("(could not list equipment sets: "..tostring(ids)..")")
        end
    end

    if not setID then
        PrintAllSets(("Equipment set '%s' was NOT created: CreateEquipmentSet raised no error, but no set with that name exists afterwards."):format(setName))
        return false
    end

    local _, _, _, _, numItems, numEquipped, _, _, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(setID)
    TopFit:Print(("Equipment set '%s' %s (ID %s): %s item(s) saved, %s slot(s) ignored.%s"):format(
        setName, created and "created" or "updated", tostring(setID), tostring(numItems), tostring(numIgnored),
        ignoreFailed and " (slot exclusion failed: C_EquipmentSet.IgnoreSlotForSave errored)" or ""))
    if numItems == 0 then
        TopFit:Print("Warning: the set was saved with 0 items. Nothing was equipped in the slots it covers when it was saved.")
    end

    if verbose then
        PrintAllSets("Equipment sets on this character:")
    end
    return true
end

function TopFit:GenerateSetName(name)
    return (((name ~= nil) and string.sub(name.." ", 1, 12).."(TF)") or "TopFit")
end

function TopFit:ChatCommand(input)
    if not input or input:trim() == "" then
        TopFit:OpenOptionsPanel()
    else
        local command, rest = input:trim():match("^(%S+)%s*(.*)$")
        command = command and command:lower()
        if command == "show" then
            TopFit:CreateProgressFrame()
        elseif command == "options" then
            TopFit:OpenOptionsPanel()
        elseif command == "import" then
            TopFit:ShowImportDialog()
        elseif command == "export" then
            TopFit:ShowExportDialog(rest and rest:lower() == "pawn")
        elseif command == "simc" then
            TopFit:ShowSimcExportDialog()
        elseif command == "talentdebug" then
            TopFit:DebugTalentCounts()
        elseif command == "saveset" then
            local testName = (rest and rest ~= "") and rest or "TopFit Test"
            TopFit:SaveGearToEquipmentSet(testName, nil, true)
        elseif command == "weapondebug" then
            TopFit:DebugWeaponSlots()
        elseif command == "caps" then
            TopFit:CapsCommand(rest)
        else
            TopFit:Print("Available Options:\n  show - shows the calculations frame\n  options - shows TopFit's options\n  import - import a Pawn/AskMrRobot/TopFit weight string as a new set\n  export [pawn] - export the selected set as a string (add 'pawn' for Pawn format)\n  simc - export your currently equipped gear as a .simc profile\n  talentdebug - print raw talent tab/count info for debugging\n  saveset [name] - save your worn gear into an equipment set and report exactly what happened (for testing)\n  weapondebug - print weapon slot subType/speed/damage scan results for debugging\n  caps - list/add/remove/toggle cap entries for the selected set (type 'caps' alone for help)")
        end
    end
end

function TopFit:ResolveStatToken(input)
    if not input or input == "" then
        return nil
    end
    if _G[input] and TopFit.statList then
        for _, tokens in pairs(TopFit.statList) do
            for _, token in ipairs(tokens) do
                if token == input then
                    return token
                end
            end
        end
    end
    local lowerInput = input:lower()
    if TopFit.statList then
        for _, tokens in pairs(TopFit.statList) do
            for _, token in ipairs(tokens) do
                local displayName = _G[token]
                if displayName and displayName:lower() == lowerInput then
                    return token
                end
            end
        end
    end
    return nil
end

function TopFit:CapsCommand(rest)
    if not TopFit.ProgressFrame or not TopFit.ProgressFrame.selectedSet then
        TopFit:Print("No set is currently selected.")
        return
    end
    local setCode = TopFit.ProgressFrame.selectedSet
    local caps = TopFit.db.profile.sets[setCode].caps
    
    local subcommand, args = rest:trim():match("^(%S*)%s*(.-)$")
    subcommand = subcommand and subcommand:lower()
    
    if subcommand == "" then
        TopFit:Print("Cap entries for \"" .. TopFit.db.profile.sets[setCode].name .. "\":")
        local any = false
        for stat, capList in pairs(caps) do
            local displayName = _G[stat] or stat
            for slot, entry in ipairs(capList) do
                any = true
                TopFit:Print(("  [%s] slot %d: value=%s, %s, %s%s"):format(
                    displayName, slot, tostring(entry.value), entry.soft and "soft" or "hard",
                    entry.active and "active" or "inactive",
                    entry.label and (" -- " .. entry.label) or ""))
            end
        end
        if not any then
            TopFit:Print("  (none)")
        end
        TopFit:Print("Use '/topfit caps add <stat> <value> <soft|hard> [label]', 'remove <stat> <slot#>', or 'toggle <stat> <slot#>'.")
        return
    end
    
    if subcommand == "add" then
        local statInput, value, capType, label = args:match("^(%S+)%s+(%S+)%s+(%S+)%s*(.-)$")
        local statKey = statInput and TopFit:ResolveStatToken(statInput)
        value = tonumber(value)
        if not statKey or not value or not (capType and (capType:lower() == "soft" or capType:lower() == "hard")) then
            TopFit:Print("Usage: /topfit caps add <stat> <value> <soft|hard> [label]")
            return
        end
        caps[statKey] = caps[statKey] or {}
        tinsert(caps[statKey], {
            active = true,
            soft = capType:lower() == "soft",
            value = value,
            label = (label ~= "" and label) or nil,
        })
        TopFit:Print(("Added cap slot %d for %s: %s (%s)."):format(#caps[statKey], _G[statKey] or statKey, value, capType:lower()))
        TopFit:CalculateScores()
        return
    end
    
    if subcommand == "remove" or subcommand == "toggle" then
        local statInput, slot = args:match("^(%S+)%s+(%d+)$")
        local statKey = statInput and TopFit:ResolveStatToken(statInput)
        slot = tonumber(slot)
        if not statKey or not slot or not caps[statKey] or not caps[statKey][slot] then
            TopFit:Print(("Usage: /topfit caps %s <stat> <slot#> -- use '/topfit caps' to see valid slots."):format(subcommand))
            return
        end
        if subcommand == "remove" then
            tremove(caps[statKey], slot)
            TopFit:Print(("Removed slot %d for %s."):format(slot, _G[statKey] or statKey))
        else
            caps[statKey][slot].active = not caps[statKey][slot].active
            TopFit:Print(("Slot %d for %s is now %s."):format(slot, _G[statKey] or statKey, caps[statKey][slot].active and "active" or "inactive"))
        end
        TopFit:CalculateScores()
        return
    end
    
    TopFit:Print("Usage: /topfit caps [add|remove|toggle] ...")
end

function TopFit:SetupCharacterModeTab()
    if TopFit.characterModeTab then return end
    if not CharacterFrame or not CharacterFrame.ModeTabs or not CharacterFrame.ModeTabs.Tabs then return end

    local tabs = CharacterFrame.ModeTabs.Tabs
    local tab = CreateFrame("Button", "TopFit_CharacterModeTab", CharacterFrame.ModeTabs, "CharacterFrameModeSideTabTemplate")
    TopFit.characterModeTab = tab

    if tab.Icon then
        tab.Icon:SetTexture("Interface\\Icons\\Achievement_BG_trueAVshutout")
    end

    -- Anchor directly below the last native tab without modifying Blizzard's Tabs array
    local prevTab = tabs[#tabs]
    if prevTab then
        tab:SetPoint("TOPLEFT", prevTab, "BOTTOMLEFT", 0, -4)
    end

    tab:SetScript("OnClick", function()
        if not TopFit.ProgressFrame or not TopFit.ProgressFrame:IsShown() then
            TopFit:CreateProgressFrame()
        else
            TopFit:HideProgressFrame()
        end
    end)

    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("TopFit Gear Optimizer", 1, 1, 1)
        GameTooltip:AddLine("Click to open calculation settings and recommendations.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)

    tab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function TopFit:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("TopFitDB")

    self.ITEM_CACHE_VERSION = 2
    if self.db.global.itemCacheVersion ~= self.ITEM_CACHE_VERSION then
        self.db.global.itemCache = {}
        self.db.global.itemCacheVersion = self.ITEM_CACHE_VERSION
    end
    
    TopFit.eventHandler = TopFit.eventHandler or LibStub("CallbackHandler-1.0"):New(TopFit)
    TopFit.scanTooltip = CreateFrame('GameTooltip', 'TFScanTooltip', UIParent, 'GameTooltipTemplate')

    if (not self.db.profile.sets) then
        self.db.profile.sets = {
            set_1 = {
                name = "Default Set",
                weights = {},
                caps = {},
                forced = {},
            },
        }
    end
    
    for set, table in pairs(self.db.profile.sets) do
        if table.forced == nil then
            table.forced = {}
        end
        
        for stat, value in pairs(table.weights) do
            table.weights[stat] = tonumber(value) or nil
        end
        
        for stat, capEntry in pairs(table.caps) do
            if capEntry.value ~= nil and capEntry[1] == nil then
                table.caps[stat] = { capEntry }
            end
        end
        for stat, capList in pairs(table.caps) do
            for _, capTable in ipairs(capList) do
                capTable.value = tonumber(capTable.value)
            end
        end
    end
    
    _G["TOPFIT_WEAPON_SPEED"] = "Weapon Speed"
    _G["TOPFIT_HIT_CHANCE_ALL"] = "Hit Chance"
    _G["TOPFIT_CRIT_CHANCE_ALL"] = "Critical Strike Chance"
    _G["TOPFIT_CRIT_CHANCE_MELEE"] = "Melee Critical Strike Chance"
    _G["TOPFIT_CRIT_CHANCE_RANGED"] = "Ranged Critical Strike Chance"
    _G["TOPFIT_CRIT_CHANCE_SPELL"] = "Spell Critical Strike Chance"
    _G["TOPFIT_DODGE_PARRY_REDUCTION"] = "Dodge/Parry Reduction"
    _G["TOPFIT_PARRY_CHANCE_ALL"] = "Parry Chance"
    _G["TOPFIT_BLOCK_CHANCE_ALL"] = "Block Chance"
    _G["TOPFIT_HIT_CHANCE_SPELL"] = "Spell Hit Chance"
    _G["TOPFIT_CRIT_CHANCE_PHYSICAL"] = "Physical Critical Strike Chance"
    _G["TOPFIT_DODGE_CHANCE_ALL"] = "Dodge Chance"
    _G["TOPFIT_ARMOR_PENETRATION_PERCENT"] = "Armor Penetration"
    _G["TOPFIT_RESILIENCE_PERCENT"] = "Resilience"
    _G["TOPFIT_HASTE_PERCENT"] = "Haste"
    _G["TOPFIT_ARCANE_DAMAGE_FLAT"] = "Arcane Damage"
    _G["TOPFIT_FIRE_DAMAGE_FLAT"] = "Fire Damage"
    _G["TOPFIT_FROST_DAMAGE_FLAT"] = "Frost Damage"
    _G["TOPFIT_HOLY_DAMAGE_FLAT"] = "Holy Damage"
    _G["TOPFIT_NATURE_DAMAGE_FLAT"] = "Nature Damage"
    _G["TOPFIT_SHADOW_DAMAGE_FLAT"] = "Shadow Damage"
    _G["TOPFIT_DEFENSE_FLAT"] = "Defense"
    _G["TOPFIT_SPELL_HEALING_FLAT"] = "Healing Power"
    _G["TOPFIT_SPELL_DAMAGE_FLAT"] = "Spell Damage"

    TopFit.statList = {
        ["Basic Attributes"] = {
            [1] = "ITEM_MOD_AGILITY_SHORT",
            [2] = "ITEM_MOD_INTELLECT_SHORT",
            [3] = "ITEM_MOD_SPIRIT_SHORT",
            [4] = "ITEM_MOD_STAMINA_SHORT",
            [5] = "ITEM_MOD_STRENGTH_SHORT",
        },
        ["Melee"] = {
            [1] = "TOPFIT_ARMOR_PENETRATION_PERCENT",
            [2] = "ITEM_MOD_ATTACK_POWER_SHORT",
            [3] = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
            [4] = "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
            [5] = "TOPFIT_WEAPON_SPEED",
            [6] = "TOPFIT_CRIT_CHANCE_MELEE",
            [7] = "TOPFIT_DODGE_PARRY_REDUCTION",
        },
        ["Caster"] = {
            [1] = "ITEM_MOD_SPELL_PENETRATION_SHORT",
            [2] = "ITEM_MOD_MANA_REGENERATION_SHORT",
            [3] = "TOPFIT_SPELL_DAMAGE_FLAT",
            [4] = "TOPFIT_SPELL_HEALING_FLAT",
            [5] = "TOPFIT_CRIT_CHANCE_SPELL",
            [6] = "TOPFIT_HIT_CHANCE_SPELL",
            [7] = "TOPFIT_ARCANE_DAMAGE_FLAT",
            [8] = "TOPFIT_FIRE_DAMAGE_FLAT",
            [9] = "TOPFIT_FROST_DAMAGE_FLAT",
            [10] = "TOPFIT_HOLY_DAMAGE_FLAT",
            [11] = "TOPFIT_NATURE_DAMAGE_FLAT",
            [12] = "TOPFIT_SHADOW_DAMAGE_FLAT",
        },
        ["Defensive"] = {
            [1] = "ITEM_MOD_BLOCK_VALUE_SHORT",
            [2] = "RESISTANCE0_NAME",
            [3] = "TOPFIT_DEFENSE_FLAT",
            [4] = "TOPFIT_PARRY_CHANCE_ALL",
            [5] = "TOPFIT_BLOCK_CHANCE_ALL",
            [6] = "TOPFIT_DODGE_CHANCE_ALL",
            [7] = "TOPFIT_RESILIENCE_PERCENT",
        },
        ["Hybrid"] = {
            [1] = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
            [2] = "TOPFIT_HASTE_PERCENT",
            [3] = "TOPFIT_HIT_CHANCE_ALL",
            [4] = "TOPFIT_CRIT_CHANCE_ALL",
            [5] = "TOPFIT_CRIT_CHANCE_PHYSICAL",
        },
        ["Misc."] = {
            [1] = "ITEM_MOD_HEALTH_SHORT",
            [2] = "ITEM_MOD_MANA_SHORT",
            [3] = "ITEM_MOD_HEALTH_REGENERATION_SHORT",
        },
        ["Resistances"] = {
            [1] = "RESISTANCE1_NAME",
            [2] = "RESISTANCE2_NAME",
            [3] = "RESISTANCE3_NAME",
            [4] = "RESISTANCE4_NAME",
            [5] = "RESISTANCE5_NAME",
            [6] = "RESISTANCE6_NAME",
        },
    }
    
    TopFit.slotList = {
        "BackSlot",
        "ChestSlot",
        "FeetSlot",
        "Finger0Slot",
        "Finger1Slot",
        "HandsSlot",
        "HeadSlot",
        "LegsSlot",
        "MainHandSlot",
        "NeckSlot",
        "RangedSlot",
        "SecondaryHandSlot",
        "ShirtSlot",
        "ShoulderSlot",
        "TabardSlot",
        "Trinket0Slot",
        "Trinket1Slot",
        "WaistSlot",
        "WristSlot",
    }
    
    TopFit.slots = {}
    TopFit.slotNames = {}
    for _, slotName in pairs(TopFit.slotList) do
        local slotID, _, _ = GetInventorySlotInfo(slotName)
        TopFit.slots[slotName] = slotID;
        TopFit.slotNames[slotID] = slotName;
    end
    
    TopFit.updateFrame = CreateFrame("Frame")
    TopFit:createOptions()

    self:RegisterChatCommand("topfit", "ChatCommand")
    self:RegisterChatCommand("tf", "ChatCommand")
    
    TopFit.itemsCache = {}
    TopFit.scoresCache = {}
    
    TopFit.equippableItems = {}
    TopFit:collectEquippableItems()
    TopFit.loginDelay = 150
    
    TopFit.eventFrame = CreateFrame("Frame")
    TopFit.eventFrame:RegisterEvent("BAG_UPDATE")
    TopFit.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    TopFit.eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    TopFit.eventFrame:SetScript("OnEvent", TopFit.FrameOnEvent)
    TopFit.eventFrame:SetScript("OnUpdate", TopFit.delayCalculationOnLogin)
    
    TopFit.calculationsFrame = CreateFrame("Frame");
    
    local isPlateWearer, isMailWearer = false, false
    if (select(2, UnitClass("player")) == "WARRIOR") or (select(2, UnitClass("player")) == "PALADIN") then
        isPlateWearer = true
    end
    if (select(2, UnitClass("player")) == "SHAMAN") or (select(2, UnitClass("player")) == "HUNTER") then
        isMailWearer = true
    end
    
    TopFit.heirloomInfo = {
        plateHeirlooms = {
            [3] = {
                [1] = 42949,
                [2] = 44100,
                [3] = 44099,
            },
            [5] = {
                [1] = 48685,
            },
        },
        mailHeirlooms = {
            [3] = {
                [1] = 44102,
                [2] = 42950,
                [3] = 42951,
                [4] = 44101,
            },
            [5] = {
                [1] = 48677,
                [2] = 48683,
            },
        },
        isPlateWearer = isPlateWearer,
        isMailWearer = isMailWearer
    }
    
    TopFit.plugins = {}
end

function TopFit:collectEquippableItems()
    local newItem = false
    
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local item = C_Container.GetContainerItemLink(bag, slot)
            
            if item and C_Item.IsEquippableItem(item) then
                local found = false
                for _, link in pairs(TopFit.equippableItems) do
                    if link == item then
                        found = true
                        break
                    end
                end
                
                if not found then
                    tinsert(TopFit.equippableItems, item)
                    newItem = true
                end
            end
        end
    end
    
    for _, invSlot in pairs(TopFit.slots) do
        local item = GetInventoryItemLink("player", invSlot)
        
        if item and C_Item.IsEquippableItem(item) then
            local found = false
            for _, link in pairs(TopFit.equippableItems) do
                if link == item then
                    found = true
                    break
                end
            end
            
            if not found then
                tinsert(TopFit.equippableItems, item)
                newItem = true
            end
        end
    end
    
    return newItem
end

function TopFit:delayCalculationOnLogin()
    if TopFit.loginDelay then
        TopFit.loginDelay = TopFit.loginDelay - 1
        if TopFit.loginDelay <= 0 then
            TopFit.loginDelay = nil
            TopFit.eventFrame:SetScript("OnUpdate", nil)
        end
    end
end

function TopFit:FrameOnEvent(event, ...)
    if (event == "BAG_UPDATE") then
        TopFit:collectItems()
        
        if TopFit:collectEquippableItems() and not TopFit.loginDelay then
            if TopFit.db.profile.defaultUpdateSet then
                if not TopFit.workSetList then
                    TopFit.workSetList = {}
                end
                tinsert(TopFit.workSetList, TopFit.db.profile.defaultUpdateSet)
                
                TopFit:CalculateSets(true)
            end
        end
    elseif (event == "GET_ITEM_INFO_RECEIVED") then
        local itemID, success = ...
        if success and TopFit.pendingItemInfoRequests and TopFit.pendingItemInfoRequests[itemID] then
            TopFit.pendingItemInfoRequests[itemID] = nil
            TopFit:RescanPendingItem(itemID)
        end
    elseif (event == "PLAYER_LEVEL_UP") then
        for itemLink, itemTable in pairs(TopFit.itemsCache) do
            if itemTable.itemQuality == 7 then
                TopFit.itemsCache[itemLink] = nil
                TopFit.scoresCache[itemLink] = nil
            end
        end
        
        if TopFit.db.profile.defaultUpdateSet then
            if not TopFit.workSetList then
                TopFit.workSetList = {}
            end
            tinsert(TopFit.workSetList, TopFit.db.profile.defaultUpdateSet)
            
            TopFit:CalculateSets(true)
        end
    end
end

function TopFit:OnEnable()
    TopFit:SetupCharacterModeTab()
end

function TopFit:OnDisable()
    -- Called when the addon is disabled
end