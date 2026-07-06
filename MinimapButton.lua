-- MinimapButton.lua for TopFit
-- Repurposed from RollFor's MinimapButton implementation

local TopFit = TopFit

-- Helper functions to interact with TopFit's profile database
local function GetAngle()
    if not TopFit.db or not TopFit.db.profile then return 0 end
    TopFit.db.profile.minimap = TopFit.db.profile.minimap or {}
    return TopFit.db.profile.minimap.angle or 0
end

local function PersistAngle(angle)
    if TopFit.db and TopFit.db.profile then
        TopFit.db.profile.minimap = TopFit.db.profile.minimap or {}
        TopFit.db.profile.minimap.angle = angle
    end
end

local function IsHidden()
    if not TopFit.db or not TopFit.db.profile then return false end
    TopFit.db.profile.minimap = TopFit.db.profile.minimap or {}
    return TopFit.db.profile.minimap.hide or false
end

local function IsLocked()
    if not TopFit.db or not TopFit.db.profile then return false end
    TopFit.db.profile.minimap = TopFit.db.profile.minimap or {}
    return TopFit.db.profile.minimap.lock or false
end

local function CreateMinimapButton()
    local frame = CreateFrame("Button", "TopFitMinimapButton", Minimap)
    local was_dragging = false

    -- Forward declarations of functions used by frame scripts
    local OnUpdate, UpdatePosition

    frame:SetScript("OnClick", function(self, button)
        if IsControlKeyDown() then
            -- Control+Click opens options panel
            InterfaceOptionsFrame_OpenToCategory("TopFit")
        elseif button == "RightButton" then
            -- Right-Click opens the SimC export window
            TopFit:ShowSimcExportDialog()
        elseif IsShiftKeyDown() then
            -- Shift+Click opens the Import dialog
            TopFit:ShowImportDialog()
        else
            -- Left-Click toggles calculation panel
            if (not TopFit.ProgressFrame) or (not TopFit.ProgressFrame:IsShown()) then
                TopFit:CreateProgressFrame()
            else
                TopFit:HideProgressFrame()
            end
        end
        self:GetScript("OnEnter")(self)
        GameTooltip:Hide()
    end)

    frame:SetScript("OnEnter", function(self)
        if not self.dragging then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("|cff00c0ffTopFit|r")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd200/tf show|r - |cffffffffShow calculation frame|r")
            GameTooltip:AddLine("|cffffd200/tf options|r - |cffffffffOpen options|r")
            GameTooltip:AddLine("|cffffd200/tf import|r - |cffffffffImport weight string|r")
            GameTooltip:AddLine("|cffffd200/tf export|r - |cffffffffExport current set|r")
            GameTooltip:AddLine("|cffffd200/tf simc|r - |cffffffffExport .simc profile|r")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffffffClick|r to toggle calculation window.")
            GameTooltip:AddLine("|cffffffffRight-Click|r to export .simc profile.")
            GameTooltip:AddLine("|cffffffffCtrl+Click|r to open options.")
            GameTooltip:AddLine("|cffffffffShift+Click|r to import weights.")
            GameTooltip:Show()
        end
    end)

    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:SetScript("OnDragStart", function(self)
        if IsLocked() then return end
        self.dragging = true
        self:LockHighlight()
        self.icon:SetTexCoord(0, 1, 0, 1)
        self:SetScript("OnUpdate", OnUpdate)
        GameTooltip:Hide()
        was_dragging = true
    end)

    frame:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        self:UnlockHighlight()
    end)

    OnUpdate = function(self)
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()

        px, py = px / scale, py / scale

        local angle = math.deg(math.atan2(py - my, px - mx)) % 360
        PersistAngle(angle)
        UpdatePosition(self)
    end

    UpdatePosition = function(self)
        local angle = math.rad(GetAngle() or math.random(0, 360))
        local cos = math.cos(angle)
        local sin = math.sin(angle)
        local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"

        local round = false
        if minimapShape == "ROUND" then
            round = true
        elseif minimapShape == "SQUARE" then
            round = false
        elseif minimapShape == "CORNER-TOPRIGHT" then
            round = not (cos < 0 or sin < 0)
        elseif minimapShape == "CORNER-TOPLEFT" then
            round = not (cos > 0 or sin < 0)
        elseif minimapShape == "CORNER-BOTTOMRIGHT" then
            round = not (cos < 0 or sin > 0)
        elseif minimapShape == "CORNER-BOTTOMLEFT" then
            round = not (cos > 0 or sin > 0)
        elseif minimapShape == "SIDE-LEFT" then
            round = cos <= 0
        elseif minimapShape == "SIDE-RIGHT" then
            round = cos >= 0
        elseif minimapShape == "SIDE-TOP" then
            round = sin <= 0
        elseif minimapShape == "SIDE-BOTTOM" then
            round = sin >= 0
        elseif minimapShape == "TRICORNER-TOPRIGHT" then
            round = not (cos < 0 and sin > 0)
        elseif minimapShape == "TRICORNER-TOPLEFT" then
            round = not (cos > 0 and sin > 0)
        elseif minimapShape == "TRICORNER-BOTTOMRIGHT" then
            round = not (cos < 0 and sin < 0)
        elseif minimapShape == "TRICORNER-BOTTOMLEFT" then
            round = not (cos > 0 and sin < 0)
        end

        local x, y
        if round then
            x = cos * 80
            y = sin * 80
        else
            x = math.max(-82, math.min(110 * cos, 84))
            y = math.max(-86, math.min(110 * sin, 82))
        end

        self:ClearAllPoints()
        self:SetPoint("CENTER", x, y)
    end

    -- Setup frame visual properties
    frame:SetFrameStrata("MEDIUM")
    frame:SetWidth(31)
    frame:SetHeight(31)
    frame:SetFrameLevel(8)
    frame:RegisterForClicks("anyUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = frame:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local icon = frame:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\Achievement_BG_trueAVshutout") -- TopFit's Golden Sword icon
    frame.icon = icon

    UpdatePosition(frame)

    frame:SetScript("OnEvent", function(self) UpdatePosition(self) end)
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if IsHidden() then
        frame:Hide()
    else
        frame:Show()
    end

    return frame
end

-- Safely hooks TopFit's initialization routine to invoke our button creator
local original_OnInitialize = TopFit.OnInitialize
function TopFit:OnInitialize()
    if original_OnInitialize then
        original_OnInitialize(self)
    end
    TopFit.minimapButtonFrame = CreateMinimapButton()
end