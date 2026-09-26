-- caps[stat] is now a list of independent cap entries (see calculation.lua/core.lua) so a stat can
-- carry several thresholds at once. The point-and-click editor below only surfaces the first entry
-- ("slot 1" -- the primary cap for that stat); additional entries, like a preset's secondary Dual
-- Wield Hit cap alongside its primary Spell Hit cap, can be viewed/edited with /topfit caps. This
-- keeps the existing row layout untouched rather than risking new overlapping widgets for a
-- multi-slot editor that can't be visually verified here.

local backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    tileSize = 0,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function GetOrCreatePrimaryCap(stat)
    if not TopFit.ProgressFrame or not TopFit.ProgressFrame.selectedSet then return nil end
    local set = TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet]
    if not set then return nil end
    
    set.caps = set.caps or {}
    set.caps[stat] = set.caps[stat] or {}
    set.caps[stat][1] = set.caps[stat][1] or { active = false, soft = false, value = 0 }
    return set.caps[stat][1]
end

function TopFit:CreateStatsPlugin()
    local statsFrame, pluginId = TopFit:RegisterPlugin("Weights & Caps", "Use this tab to set weights and caps for your sets, defining their basic behavior.")
    
    -- options button
    statsFrame.optionsButton = CreateFrame("Button", "TopFit_ProgressFrame_optionsButton", statsFrame)
    statsFrame.optionsButton:SetPoint("TOPRIGHT", statsFrame, "TOPRIGHT", -15, -5)
    statsFrame.optionsButton:SetHeight(32)
    statsFrame.optionsButton:SetWidth(32)
    statsFrame.optionsButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_02")
    statsFrame.optionsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    
    -- set options
    statsFrame.includeInTooltipCheckButton = LibStub("tekKonfig-Checkbox").new(statsFrame, nil, "Include set in tooltip", "TOPLEFT", statsFrame, "TOPLEFT", 15, -15)
    statsFrame.includeInTooltipCheckButton.tiptext = "|cffffffffCheck to show this set in item comparison tooltips when that option is enabled."
    if (TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet) then
        statsFrame.includeInTooltipCheckButton:SetChecked(TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].excludeFromTooltip)
    end
    local checksound = statsFrame.includeInTooltipCheckButton:GetScript("OnClick")
    statsFrame.includeInTooltipCheckButton:SetScript("OnClick", function(self)
        if checksound then checksound(self) end
        if (TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet) then
            TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].excludeFromTooltip = not TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].excludeFromTooltip
        end
    end)
    
    -- option to force a two-handed weapon (empty offhand), overriding dual-wield/Titan's Grip.
    do
        local anchorTo = statsFrame.simulateDualWieldCheckButton or statsFrame.simulateTitansGripCheckButton or statsFrame.includeInTooltipCheckButton
        statsFrame.forceTwoHandedCheckButton = LibStub("tekKonfig-Checkbox").new(statsFrame, nil, "Force two-handed", "TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
        statsFrame.forceTwoHandedCheckButton.tiptext = "|cffffffffCheck to always recommend a two-handed weapon and leave the offhand slot empty for this set, regardless of dual-wield or Titan's Grip availability."
        if TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet then
            statsFrame.forceTwoHandedCheckButton:SetChecked(TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].forceTwoHanded)
        end
        local checksound2 = statsFrame.forceTwoHandedCheckButton:GetScript("OnClick")
        statsFrame.forceTwoHandedCheckButton:SetScript("OnClick", function(self)
            if checksound2 then checksound2(self) end
            if (TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet) then
                local set = TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet]
                set.forceTwoHanded = not set.forceTwoHanded
                
                if set.forceTwoHanded then
                    if set.simulateDualWield then
                        set.simulateDualWield = false
                        if statsFrame.simulateDualWieldCheckButton then
                            statsFrame.simulateDualWieldCheckButton:SetChecked(false)
                        end
                    end
                    if set.simulateTitansGrip then
                        set.simulateTitansGrip = false
                        if statsFrame.simulateTitansGripCheckButton then
                            statsFrame.simulateTitansGripCheckButton:SetChecked(false)
                        end
                    end
                end
            end
        end)
    end
    
    statsFrame.optionsButton:SetScript("OnClick", function(...)
        TopFit:OpenOptionsPanel()
        if TopFit.ProgressFrame then
            TopFit.ProgressFrame:Hide()
        end
    end)
    statsFrame.optionsButton.tipText = "Open TopFit's options"
    statsFrame.optionsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipText or "Open TopFit's options")
        GameTooltip:Show()
    end)
    statsFrame.optionsButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    statsFrame.statDropDown = CreateFrame("Frame", "TopFit_ProgressFrame_statDropDown", statsFrame, "UIDropDownMenuTemplate")
    
    UIDropDownMenu_Initialize(statsFrame.statDropDown, function(self, level)
        level = level or 1
        if (level == 1) then
            TopFit:collectItems()
            local info = UIDropDownMenu_CreateInfo()
            info.hasArrow = false
            info.notCheckable = true
            info.text = "Add stat..."
            info.isTitle = true
            UIDropDownMenu_AddButton(info, level)
            
            for categoryName, statTable in pairs(TopFit.statList) do
                local info = UIDropDownMenu_CreateInfo()
                info.hasArrow = true
                info.notCheckable = true
                info.text = categoryName
                info.isTitle = false
                info.value = categoryName
                UIDropDownMenu_AddButton(info, level)
            end
            
            -- submenu for set pieces
            local info = UIDropDownMenu_CreateInfo()
            info.hasArrow = true
            info.notCheckable = true
            info.text = "Set Piece"
            info.isTitle = false
            info.value = "setpieces"
            UIDropDownMenu_AddButton(info, level)
        elseif level == 2 then
            local parentValue = UIDROPDOWNMENU_MENU_VALUE
            
            if parentValue == "setpieces" then
                local setnames = {}
                for _, itemList in pairs(TopFit:GetEquippableItems()) do
                    for _, locationTable in pairs(itemList) do
                        local itemTable = TopFit:GetCachedItem(locationTable.itemLink)
                        if itemTable and itemTable.itemBonus then
                            for stat, _ in pairs(itemTable.itemBonus) do
                                if (string.find(stat, "SET: ")) then
                                    local setname = string.gsub(stat, "SET: (.*)", "%1")
                                    
                                    local found = false
                                    for _, setname2 in pairs(setnames) do
                                        if setname == setname2 then found = true break end
                                    end
                                    
                                    if not found then tinsert(setnames, setname) end
                                end
                            end
                        end
                    end
                end
                
                table.sort(setnames)
                for i = 1, #setnames do
                    local info = UIDropDownMenu_CreateInfo()
                    info.hasArrow = false
                    info.notCheckable = true
                    info.text = setnames[i]
                    info.isTitle = false
                    info.isChecked = false
                    info.value = setnames[i]
                    info.func = function(...)
                        TopFit:Debug("Adding stat: "..info.value)
                        if (TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet) then
                            TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].weights["SET: "..setnames[i]] = 0
                        end
                        statsFrame:UpdateSetStats()
                        TopFit:CalculateScores()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            elseif parentValue and TopFit.statList[parentValue] then
                for key, value in pairs(TopFit.statList[parentValue]) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.hasArrow = false
                    info.notCheckable = true
                    info.text = _G[value] or value
                    info.isTitle = false
                    info.isChecked = false
                    info.value = value
                    info.func = function(...)
                        TopFit:Debug("Adding stat: "..value)
                        if (TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet) then
                            TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].weights[value] = 0
                        end
                        statsFrame:UpdateSetStats()
                        TopFit:CalculateScores()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end, "MENU")
    UIDropDownMenu_JustifyText(statsFrame.statDropDown, "LEFT")
    
    statsFrame.addStatButton = CreateFrame("Button", "TopFit_ProgressFrame_expandButton", statsFrame, "UIPanelButtonTemplate")
    statsFrame.addStatButton:SetPoint("TOPLEFT", statsFrame.forceTwoHandedCheckButton, "BOTTOMLEFT", -10, -15)
    statsFrame.addStatButton:SetText("Add stat...")
    statsFrame.addStatButton:SetHeight(22)
    statsFrame.addStatButton:SetWidth(80)
    statsFrame.addStatButton:RegisterForClicks("AnyUp")
    
    statsFrame.addStatButton:SetScript("OnClick", function(self, button)
        ToggleDropDownMenu(1, nil, statsFrame.statDropDown, self, -20, 0)
    end)
    
    -- FIX: Inherit BackdropTemplate for modern WoW API
    statsFrame.editStatScrollFrame = CreateFrame("ScrollFrame", "TopFit_EditStatScrollFrame", statsFrame, "UIPanelScrollFrameTemplate, BackdropTemplate")
    statsFrame.editStatScrollFrame:SetPoint("TOPLEFT", statsFrame.addStatButton, "BOTTOMLEFT", 0, -25)
    statsFrame.editStatScrollFrame:SetPoint("BOTTOMRIGHT", statsFrame, "BOTTOMRIGHT", -25, 5)
    statsFrame.editStatScrollFrame:SetHeight(statsFrame.editStatScrollFrame:GetHeight())
    statsFrame.editStatScrollFrame:SetWidth(statsFrame.editStatScrollFrame:GetWidth())
    
    local editStatScrollFrameContent = CreateFrame("Frame", nil, statsFrame.editStatScrollFrame)
    editStatScrollFrameContent:SetAllPoints()
    editStatScrollFrameContent:SetHeight(10)
    editStatScrollFrameContent:SetWidth(235)
    statsFrame.editStatScrollFrame:SetScrollChild(editStatScrollFrameContent)
    statsFrame.editStatScrollFrame:SetBackdrop(backdrop)
    statsFrame.editStatScrollFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    statsFrame.editStatScrollFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    -- containers for stat list
    statsFrame.menuHeaders = {}
    statsFrame.statCapCheckboxes = {}
    statsFrame.editStatNameTexts = {}
    statsFrame.editStatValueTexts = {}
    statsFrame.editStatButtons = {}
    statsFrame.statCapTexts = {}
    statsFrame.statCapValueTexts = {}
    statsFrame.statCapButtons = {}
    statsFrame.capTypeTexts = {}
    statsFrame.capTypeButtons = {}
    
    function statsFrame:UpdateSetStats()
        local menuHeaders = statsFrame.menuHeaders
        local statTexts = statsFrame.editStatNameTexts
        local valueTexts = statsFrame.editStatValueTexts
        local capBoxes = statsFrame.statCapCheckboxes
        local statButtons = statsFrame.editStatButtons
        local capTexts = statsFrame.statCapTexts
        local capValueTexts = statsFrame.statCapValueTexts
        local capButtons = statsFrame.statCapButtons
        local capTypeTexts = statsFrame.capTypeTexts
        local capTypeButtons = statsFrame.capTypeButtons
        
        local sortableStatWeightTable = {}
        if TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet then
            local selectedSet = TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet]
            if selectedSet and selectedSet.caps then
                for stat, capList in pairs(selectedSet.caps) do
                    if TopFit:IsStatCapped(capList) and selectedSet.weights[stat] == nil then
                        selectedSet.weights[stat] = 0
                    end
                end
            end
            
            if selectedSet and selectedSet.weights then
                for stat, value in pairs(selectedSet.weights) do
                    table.insert(sortableStatWeightTable, {stat, value})
                end
            end
        end
        
        table.sort(sortableStatWeightTable, function(a,b)
            local order = TopFit.db.profile.statSortOrder
            
            local nameA = _G[a[1]] or a[1]
            local nameB = _G[b[1]] or b[1]
            
            if order == "NameAsc" then
                return nameA < nameB
            elseif order == "NameDesc" then
                return nameA > nameB
            elseif order == "ValueAsc" then
                return a[2] < b[2]
            elseif order == "ValueDesc" then
                return a[2] > b[2]
            elseif order == "CapAsc" then
                local a_capped = TopFit.ProgressFrame.selectedSet and TopFit:IsStatCapped(TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].caps[a[1]])
                local b_capped = TopFit.ProgressFrame.selectedSet and TopFit:IsStatCapped(TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].caps[b[1]])
                if a_capped and b_capped then
                    return nameA < nameB
                elseif a_capped then
                    return true
                elseif b_capped then
                    return false
                else
                    return nameA < nameB
                end
            elseif order == "CapDesc" then
                local a_capped = TopFit.ProgressFrame.selectedSet and TopFit:IsStatCapped(TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].caps[a[1]])
                local b_capped = TopFit.ProgressFrame.selectedSet and TopFit:IsStatCapped(TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].caps[b[1]])
                if a_capped and b_capped then
                    return nameA < nameB
                elseif a_capped then
                    return false
                elseif b_capped then
                    return true
                else
                    return nameA < nameB
                end
            else
                return a[1] < b[1]
            end
        end)
        
        -- headers
        local headerTitles = {{"Name", 165}, {"Value", 40}, {"Cap", 35}}
        if not menuHeaders[1] and TopFit.ProgressFrame and TopFit.ProgressFrame.CreateHeaderButton then
            local prefix = "TopFit_ProgressFrame_MenuHeader_"
            for i = 1, #headerTitles do
                menuHeaders[i] = TopFit.ProgressFrame:CreateHeaderButton(statsFrame, prefix .. headerTitles[i][1])
                if i == 1 then
                    menuHeaders[i]:SetPoint("BOTTOMLEFT", statsFrame.editStatScrollFrame, "TOPLEFT")
                else
                    menuHeaders[i]:SetPoint("TOPLEFT", menuHeaders[i-1], "TOPRIGHT")
                end
                menuHeaders[i]:SetText(headerTitles[i][1])
                menuHeaders[i].tiptext = headerTitles[i][1]
                menuHeaders[i]:SetWidth(headerTitles[i][2])
                menuHeaders[i]:SetScript("OnClick", function(self)
                    if TopFit.db.profile.statSortOrder == headerTitles[i][1].."Asc" then
                        TopFit.db.profile.statSortOrder = headerTitles[i][1].."Desc"
                    else
                        TopFit.db.profile.statSortOrder = headerTitles[i][1].."Asc"
                    end
                    
                    statsFrame:UpdateSetStats()
                end)
                menuHeaders[i]:Show()
            end
        end
        
        -- actual stat entries
        local stat, value
        local actualStatCount = 1
        for i = 1, #sortableStatWeightTable do
            stat = sortableStatWeightTable[i][1]
            value = sortableStatWeightTable[i][2]
            
            if not statTexts[i] then
                statButtons[i] = CreateFrame("Button", "TopFit_ProgressFrame_editStatButton"..i, editStatScrollFrameContent)
                statTexts[i] = editStatScrollFrameContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
                valueTexts[i] = editStatScrollFrameContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
                capBoxes[i] = CreateFrame("CheckButton", "TopFit_ProgressFrame_CapCheckBox"..i, editStatScrollFrameContent, "UICheckButtonTemplate")
                capButtons[i] = CreateFrame("Button", "TopFit_ProgressFrame_editCapButton"..i, editStatScrollFrameContent)
                capTexts[i] = editStatScrollFrameContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
                capValueTexts[i] = editStatScrollFrameContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
                capTypeButtons[i] = CreateFrame("Button", "TopFit_ProgressFrame_editCapTypeButton"..i, editStatScrollFrameContent)
                capTypeTexts[i] = editStatScrollFrameContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightExtraSmall")
                
                statTexts[i]:SetTextHeight(11)
                valueTexts[i]:SetTextHeight(11)
                capTexts[i]:SetTextHeight(11)
                capValueTexts[i]:SetTextHeight(11)
                capTypeTexts[i]:SetTextHeight(11)
                if i == 1 then
                    statTexts[i]:SetPoint("TOPLEFT", editStatScrollFrameContent, "TOPLEFT", 3, -3)
                else
                    statTexts[i]:SetPoint("TOPLEFT", capTexts[i - 1], "BOTTOMLEFT")
                end
                valueTexts[i]:SetPoint("RIGHT", statTexts[i], "LEFT", headerTitles[1][2] + headerTitles[2][2] - 4, 0)
                capTexts[i]:SetPoint("TOPLEFT", statTexts[i], "BOTTOMLEFT")
                capValueTexts[i]:SetPoint("RIGHT", capTexts[i], "LEFT", headerTitles[1][2] + headerTitles[2][2] - 4, 0)
                capTypeTexts[i]:SetPoint("LEFT", capBoxes[i], "LEFT")
                capTypeTexts[i]:SetPoint("RIGHT", editStatScrollFrameContent, "RIGHT")
                capTypeTexts[i]:SetPoint("TOP", capValueTexts[i], "TOP")
                statButtons[i].i = i
                statButtons[i]:SetPoint("TOPLEFT", statTexts[i], "TOPLEFT")
                statButtons[i]:SetPoint("BOTTOMRIGHT", valueTexts[i], "BOTTOMRIGHT")
                statButtons[i]:SetHighlightTexture("Interface\\Buttons\\UI-ListBox-Highlight")
                statButtons[i]:SetAlpha(0.5)
                statButtons[i]:SetScript("OnClick", function(self)
                    statsFrame:HideStatEditTextBox()
                    statsFrame:ShowStatEditTextBox(self.i)
                end)
                capButtons[i].i = i
                capButtons[i]:SetPoint("TOPLEFT", capTexts[i], "TOPLEFT")
                capButtons[i]:SetPoint("BOTTOMRIGHT", capValueTexts[i], "BOTTOMRIGHT")
                capButtons[i]:SetHighlightTexture("Interface\\Buttons\\UI-ListBox-Highlight")
                capButtons[i]:SetAlpha(0.5)
                capButtons[i]:SetScript("OnClick", function(self)
                    statsFrame:HideStatEditTextBox()
                    statsFrame:ShowStatEditTextBox(self.i, true)
                end)
                capTypeButtons[i].i = i
                capTypeButtons[i]:SetPoint("TOPLEFT", capTypeTexts[i], "TOPLEFT")
                capTypeButtons[i]:SetPoint("BOTTOMRIGHT", capTypeTexts[i], "BOTTOMRIGHT")
                capTypeButtons[i]:SetHighlightTexture("Interface\\Buttons\\UI-ListBox-Highlight")
                capTypeButtons[i]:SetAlpha(0.5)
                capTypeButtons[i]:SetScript("OnClick", function(self)
                    local myStat = statsFrame.editStatButtons[self.i].myStat
                    local primaryCap = GetOrCreatePrimaryCap(myStat)
                    if primaryCap then
                        primaryCap.soft = not primaryCap.soft
                        statsFrame:UpdateSetStats()
                    end
                end)
                
                capBoxes[i].i = i
                capBoxes[i]:SetHeight(12); capBoxes[i]:SetWidth(12)
                capBoxes[i]:SetPoint("LEFT", valueTexts[i], "RIGHT")
                capBoxes[i]:SetScript("OnClick", function(self)
                    local myStat = statsFrame.editStatButtons[self.i].myStat
                    local primaryCap = GetOrCreatePrimaryCap(myStat)
                    if primaryCap then
                        primaryCap.active = not primaryCap.active
                        statsFrame:UpdateSetStats()
                        TopFit:CalculateScores()
                    end
                end)
            end
            statButtons[i]:Show()
            statTexts[i]:Show()
            valueTexts[i]:Show()
            statTexts[i]:SetText(_G[stat] or string.gsub(stat, "SET: ", "Set: "))
            valueTexts[i]:SetText(value)
            
            local capList = TopFit.ProgressFrame.selectedSet and TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].caps[stat]
            local primaryCap = capList and capList[1]
            if primaryCap and primaryCap.active then
                capBoxes[i]:SetChecked(true)
                local extraActive = 0
                if capList then
                    for idx = 2, #capList do
                        if capList[idx].active then
                            extraActive = extraActive + 1
                        end
                    end
                end
                capTexts[i]:SetText(extraActive > 0 and ("   Cap (+" .. extraActive .. ")") or "   Cap")
                capValueTexts[i]:SetText(primaryCap.value)
                capTypeTexts[i]:SetText(primaryCap.soft and "Soft" or "Hard")
                capValueTexts[i]:Show()
                capTypeTexts[i]:Show()
                capButtons[i]:Show()
                capTypeButtons[i]:Show()
            else
                capBoxes[i]:SetChecked(false)
                capTexts[i]:SetText("")
                capValueTexts[i]:Hide()
                capTypeTexts[i]:Hide()
                capButtons[i]:Hide()
                capTypeButtons[i]:Hide()
            end
            capBoxes[i]:Show()
            statButtons[i].myStat = stat
            actualStatCount = actualStatCount + 1
        end
        
        -- hide any texts not in use
        for i = actualStatCount, #statTexts do
            statTexts[i]:Hide()
            valueTexts[i]:Hide()
            statButtons[i]:Hide()
            capBoxes[i]:Hide()
            capTexts[i]:SetText("")
            capValueTexts[i]:Hide()
            capTypeTexts[i]:Hide()
            capButtons[i]:Hide()
            capTypeButtons[i]:Hide()
        end
    end
    
    function statsFrame:ShowStatEditTextBox(statID, isCap)
        if not statsFrame.statEditTextBox then
            statsFrame.statEditTextBox = CreateFrame("EditBox", "TopFit_ProgressFrame_statEditTextBox", editStatScrollFrameContent)
            statsFrame.statEditTextBox:SetWidth(50)
            statsFrame.statEditTextBox:SetHeight(11)
            statsFrame.statEditTextBox:SetAutoFocus(false)
            statsFrame.statEditTextBox:SetFontObject("GameFontHighlightSmall")
            statsFrame.statEditTextBox:SetJustifyH("RIGHT")
            
            local left = statsFrame.statEditTextBox:CreateTexture(nil, "BACKGROUND")
            left:SetWidth(8) left:SetHeight(20)
            left:SetPoint("LEFT", -5, 0)
            left:SetTexture("Interface\\Common\\Common-Input-Border")
            left:SetTexCoord(0, 0.0625, 0, 0.625)
            local right = statsFrame.statEditTextBox:CreateTexture(nil, "BACKGROUND")
            right:SetWidth(8) right:SetHeight(20)
            right:SetPoint("RIGHT", 0, 0)
            right:SetTexture("Interface\\Common\\Common-Input-Border")
            right:SetTexCoord(0.9375, 1, 0, 0.625)
            local center = statsFrame.statEditTextBox:CreateTexture(nil, "BACKGROUND")
            center:SetHeight(20)
            center:SetPoint("RIGHT", right, "LEFT", 0, 0)
            center:SetPoint("LEFT", left, "RIGHT", 0, 0)
            center:SetTexture("Interface\\Common\\Common-Input-Border")
            center:SetTexCoord(0.0625, 0.9375, 0, 0.625)
            
            statsFrame.statEditTextBox:SetScript("OnEscapePressed", function (self)
                statsFrame:HideStatEditTextBox()
                statsFrame:UpdateSetStats()
            end)
            
            statsFrame.statEditTextBox:SetScript("OnEnterPressed", function (self)
                local val = tonumber(statsFrame.statEditTextBox:GetText())
                local myStat = statsFrame.editStatButtons[statsFrame.statEditTextBox.statID].myStat
                local capFlag = statsFrame.statEditTextBox.isCap
                if val and myStat and TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet then
                    if not capFlag then
                        if val == 0 then val = nil end
                        TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].weights[myStat] = val
                    else
                        local pCap = GetOrCreatePrimaryCap(myStat)
                        if pCap then pCap.value = val end
                    end
                else
                    TopFit:Debug("invalid input")
                end
                statsFrame:HideStatEditTextBox()
                statsFrame:UpdateSetStats()
                TopFit:CalculateScores()
            end)
        end
        if not isCap then
            statsFrame.statEditTextBox:SetPoint("RIGHT", statsFrame.editStatValueTexts[statID], "RIGHT")
            local myStat = statsFrame.editStatButtons[statID].myStat
            local val = TopFit.ProgressFrame.selectedSet and TopFit.db.profile.sets[TopFit.ProgressFrame.selectedSet].weights[myStat]
            statsFrame.statEditTextBox:SetText(val or "")
            statsFrame.editStatValueTexts[statID]:Hide()
        else
            statsFrame.statEditTextBox:SetPoint("RIGHT", statsFrame.statCapValueTexts[statID], "RIGHT")
            local myStat = statsFrame.editStatButtons[statID].myStat
            local pCap = GetOrCreatePrimaryCap(myStat)
            statsFrame.statEditTextBox:SetText(pCap and pCap.value or "")
            statsFrame.statCapValueTexts[statID]:Hide()
        end
        statsFrame.statEditTextBox:Show()
        statsFrame.statEditTextBox:HighlightText()
        statsFrame.statEditTextBox:SetFocus()
        statsFrame.statEditTextBox.statID = statID
        statsFrame.statEditTextBox.isCap = isCap
    end
    
    function statsFrame:HideStatEditTextBox()
        if statsFrame.statEditTextBox then
            statsFrame.statEditTextBox:Hide()
            statsFrame.statEditTextBox:ClearFocus()
        end
    end
    
    -- event handlers
    TopFit.RegisterCallback("TopFit_stats", "OnShow", function(event, id)
        if (id == pluginId) then
            statsFrame:UpdateSetStats()
        end
    end)
    
    TopFit.RegisterCallback("TopFit_stats", "OnSetChanged", function(event, setId)
        if (setId) then
            statsFrame.addStatButton:Enable()
            statsFrame.includeInTooltipCheckButton:Enable()
            statsFrame.includeInTooltipCheckButton:SetChecked(not TopFit.db.profile.sets[setId].excludeFromTooltip)
            if (statsFrame.simulateDualWieldCheckButton) then
                statsFrame.simulateDualWieldCheckButton:Enable()
                statsFrame.simulateDualWieldCheckButton:SetChecked(TopFit.db.profile.sets[setId].simulateDualWield)
            end
            if (statsFrame.simulateTitansGripCheckButton) then
                statsFrame.simulateTitansGripCheckButton:Enable()
                statsFrame.simulateTitansGripCheckButton:SetChecked(TopFit.db.profile.sets[setId].simulateTitansGrip)
            end
            if (statsFrame.forceTwoHandedCheckButton) then
                statsFrame.forceTwoHandedCheckButton:Enable()
                statsFrame.forceTwoHandedCheckButton:SetChecked(TopFit.db.profile.sets[setId].forceTwoHanded)
            end
        else
            statsFrame.addStatButton:Disable()
            statsFrame.includeInTooltipCheckButton:Disable()
            if (statsFrame.simulateDualWieldCheckButton) then
                statsFrame.simulateDualWieldCheckButton:Disable()
            end
            if (statsFrame.simulateTitansGripCheckButton) then
                statsFrame.simulateTitansGripCheckButton:Disable()
            end
            if (statsFrame.forceTwoHandedCheckButton) then
                statsFrame.forceTwoHandedCheckButton:Disable()
            end
        end
        statsFrame:UpdateSetStats()
    end)
end