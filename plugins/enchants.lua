-- Enchants tab: pick, per gear group, which enchant a set assumes (see enchant.lua).
--   Auto  = the enchant with the best weighted score for the selected set (default)
--   None  = assume no enchant in that group
--   <name> = that specific enchant
-- Only enchants TopFit can score are listed (the rest -- procs, profession perks, threat -- are
-- unscored, see enchant.lua); at most MAX_MENU_ENTRIES are shown per group, best first, since a
-- Blizzard dropdown holds a limited number of buttons.

local MAX_MENU_ENTRIES = 30   -- a Blizzard dropdown holds 32 buttons; two are Auto and None

-- Map internal TopFit stat keys to readable names for the UI
local READABLE_STATS = {
    ["ITEM_MOD_STRENGTH_SHORT"] = "Strength",
    ["ITEM_MOD_AGILITY_SHORT"] = "Agility",
    ["ITEM_MOD_STAMINA_SHORT"] = "Stamina",
    ["ITEM_MOD_INTELLECT_SHORT"] = "Intellect",
    ["ITEM_MOD_SPIRIT_SHORT"] = "Spirit",
    ["TOPFIT_SPELL_DAMAGE_FLAT"] = "Spell Power",
    ["TOPFIT_SPELL_HEALING_FLAT"] = "Healing",
    ["RESISTANCE0_NAME"] = "Armor",
    ["RESISTANCE6_NAME"] = "Arcane Res",
    ["RESISTANCE2_NAME"] = "Fire Res",
    ["RESISTANCE3_NAME"] = "Nature Res",
    ["RESISTANCE4_NAME"] = "Frost Res",
    ["RESISTANCE5_NAME"] = "Shadow Res",
}

local function SelectedSetTable()
    local code = TopFit.ProgressFrame and TopFit.ProgressFrame.selectedSet
    return code, code and TopFit.db.profile.sets[code]
end

-- Readable effect text: the loader builds entry.text (enchant.lua); fall back to the raw stat table
local function FormatStats(entry)
    if not entry then return "" end
    if entry.text and entry.text ~= "" then return entry.text end
    if not entry.stats then return "" end
    local parts = {}
    for stat, val in pairs(entry.stats) do
        if val > 0 then
            tinsert(parts, string.format("+%s %s", val, READABLE_STATS[stat] or stat))
        end
    end
    return table.concat(parts, ", ")
end

local function Describe(entry)
    if not entry then return "None" end
    local label = entry.shortName or entry.name
    local statText = FormatStats(entry)
    if statText ~= "" then
        return label .. "  |cffaaaaaa(" .. statText .. ")|r"
    end
    return label
end

function TopFit:CreateEnchantsPlugin()
    local frame, pluginId = TopFit:RegisterPlugin("Enchants",
        "Choose which enchant each gear group is assumed to have. Enchants are not scored on the items themselves, since any enchant can go on whichever item you wear.")
    frame.initialized = false
    frame.rows = {}

    local menu  -- shared dropdown menu frame

    local function Refresh()
        if not frame.initialized then return end
        TopFit:ClearEnchantCache()
        local setCode, setTable = SelectedSetTable()
        frame.enabledCheck:SetChecked(setTable and not setTable.skipEnchants or false)
        for _, row in ipairs(frame.rows) do
            local text = "-"
            if setTable then
                local pin = setTable.enchants and setTable.enchants[row.group]
                local chosen = TopFit:GetChosenEnchant(setCode, row.group)
                local weights = TopFit:GetEffectiveWeights(setTable.weights or {}, setTable)
                local scoreText = ""
                if chosen and (next(chosen.stats) or chosen.weaponDamage) then
                    local score = TopFit:ScoreEnchantEntry(chosen, weights)
                    if chosen.weaponDamage then
                        -- flat weapon damage: shown for a typical 2.0-speed weapon; the calculation uses the real weapon's speed
                        score = score + (chosen.weaponDamage / 2.0) * ((weights["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] or 0)
                            + (chosen.group == "Ranged" and (weights["TOPFIT_RANGED_DPS"] or 0) or (weights["TOPFIT_MELEE_DPS"] or 0)))
                    end
                    scoreText = string.format("  |cff00ff00(+%.1f)|r", score)
                end
                if setTable.skipEnchants then
                    text = "|cff888888(enchants off for this set)|r"
                elseif pin == "none" then
                    text = "None"
                elseif pin and TopFit:GetEnchantEntry(row.group, pin) then
                    text = Describe(chosen) .. scoreText
                else
                    text = "Auto: " .. (chosen and Describe(chosen) or "nothing useful for this set") .. scoreText
                end
            end
            row.value:SetText(text)
        end
    end

    local function Choose(group, choice)
        local setCode, setTable = SelectedSetTable()
        if not setTable then return end
        setTable.enchants = setTable.enchants or {}
        if choice == "auto" then
            setTable.enchants[group] = nil
        else
            setTable.enchants[group] = choice
        end
        CloseDropDownMenus()
        Refresh()
    end

    local function InitMenu(self, level)
        local group = menu.currentGroup
        local setCode, setTable = SelectedSetTable()
        if not group or not setTable then return end

        local info = UIDropDownMenu_CreateInfo()
        info.text = "Auto (best for this set)"
        info.arg1 = group; info.arg2 = "auto"
        info.func = function(_, g, c) Choose(g, c) end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text = "None"
        info.arg1 = group; info.arg2 = "none"
        info.func = function(_, g, c) Choose(g, c) end
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        local weights = TopFit:GetEffectiveWeights(setTable.weights or {}, setTable)
        local list = {}
        for _, entry in ipairs(TopFit:GetEnchantsForGroup(group)) do
            if next(entry.stats) or entry.weaponDamage then
                local score = TopFit:ScoreEnchantEntry(entry, weights)
                if entry.weaponDamage then
                    -- shown as the DPS it adds to a typical 2.0-speed weapon (the real value uses the item's speed)
                    score = score + (entry.weaponDamage / 2.0) * ((weights["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] or 0)
                        + (entry.group == "Ranged" and (weights["TOPFIT_RANGED_DPS"] or 0) or (weights["TOPFIT_MELEE_DPS"] or 0)))
                end
                tinsert(list, { entry = entry, score = score })
            end
        end
        table.sort(list, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.entry.name < b.entry.name
        end)
        
        for i = 1, math.min(#list, MAX_MENU_ENTRIES) do
            local item = list[i]
            info = UIDropDownMenu_CreateInfo()
            
            local statText = FormatStats(item.entry)
            local label = item.entry.shortName or item.entry.name
            if statText ~= "" then
                info.text = string.format("%s  |cffaaaaaa(%s)|r  %.1f", label, statText, item.score)
            else
                info.text = string.format("%s  %.1f", label, item.score)
            end
            
            info.arg1 = group; info.arg2 = item.entry.name
            info.func = function(_, g, c) Choose(g, c) end
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
        end
    end

    local function Initialize()
        if frame.initialized then return end
        frame.initialized = true

        local check = LibStub("tekKonfig-Checkbox").new(frame, nil, "Include enchants in this set's calculation", "TOPLEFT", frame, "TOPLEFT", 0, 0)
        check.tiptext = "|cffffffffWhen checked, the enchants chosen below are added on top of the best items for this set (score and cap stats)."
        local checksound = check:GetScript("OnClick")
        check:SetScript("OnClick", function(self)
            if checksound then checksound(self) end
            local _, setTable = SelectedSetTable()
            if setTable then
                setTable.skipEnchants = not self:GetChecked() or nil
                Refresh()
            end
        end)
        frame.enabledCheck = check

        local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, -6)
        hint:SetPoint("RIGHT", frame, "RIGHT")
        hint:SetJustifyH("LEFT")
        hint:SetText("Click a row to choose its enchant. The number is its score for this set. Procs, profession perks and threat enchants are not scored.")

        menu = CreateFrame("Frame", "TopFit_EnchantMenu", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(menu, InitMenu, "MENU")

        -- The rows sit in a scroll frame: with 14 groups they are taller than the tab. The checkbox and
        -- hint above stay fixed.
        local scroll = CreateFrame("ScrollFrame", "TopFit_EnchantScrollFrame", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 0)   -- room for the scroll bar
        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(1)
        content:SetHeight(1)
        scroll:SetScrollChild(content)
        scroll:SetScript("OnSizeChanged", function(self, width)
            if width and width > 0 then content:SetWidth(width) end
        end)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local target = self:GetVerticalScroll() - delta * 36
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), target)))
        end)
        frame.scroll = scroll

        local ROW_HEIGHT, ROW_GAP = 18, 6
        local previous = nil
        for _, group in ipairs(TopFit.EnchantGroups) do
          if TopFit:GroupHasScoredEnchants(group) then
            local button = CreateFrame("Button", nil, content)
            button:SetHeight(ROW_HEIGHT)
            if previous then
                button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -ROW_GAP)
            else
                button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            end
            button:SetPoint("RIGHT", content, "RIGHT")
            button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            label:SetPoint("LEFT", button, "LEFT", 0, 0)
            label:SetWidth(80)
            label:SetJustifyH("LEFT")
            label:SetText(group)

            local value = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            value:SetPoint("LEFT", label, "RIGHT", 4, 0)
            value:SetPoint("RIGHT", button, "RIGHT", 0, 0)
            value:SetJustifyH("LEFT")

            button:SetScript("OnClick", function(self)
                if not select(2, SelectedSetTable()) then return end
                menu.currentGroup = group
                UIDropDownMenu_Initialize(menu, InitMenu, "MENU")
                ToggleDropDownMenu(1, nil, menu, self, 0, 0)
            end)

            tinsert(frame.rows, { group = group, button = button, value = value })
            previous = button
          end
        end
        content:SetHeight(math.max(1, #frame.rows * (ROW_HEIGHT + ROW_GAP)))
        scroll:UpdateScrollChildRect()
        Refresh()
    end

    TopFit.RegisterCallback("TopFit_enchants", "OnShow", function(event, id)
        if id == pluginId then
            Initialize()
            Refresh()
        end
    end)
    TopFit.RegisterCallback("TopFit_enchants", "OnSetChanged", function(event, setId)
        Refresh()
    end)
end