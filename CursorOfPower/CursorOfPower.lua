-- CursorOfPower.lua
-- Version 1.3: ring + sparkles + minimap toggle (fixed)

local addonName = ...

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

-- Ring size (30 is nice)
local RING_SIZE = 30

-- Ring texture
local RING_TEXTURE = "Interface\\AddOns\\CursorOfPower\\media\\Circle.tga"

-- Ring color
local RING_COLOR = { 1, 1, 1, 1 } -- white

-- Sparkle textures
local SPARKLE_TEXTURES = {
    "Interface\\AddOns\\CursorOfPower\\media\\sparkle1.tga",
    "Interface\\AddOns\\CursorOfPower\\media\\sparkle2.tga",
    "Interface\\AddOns\\CursorOfPower\\media\\sparkle3.tga",
}

-- Sparkle settings
local SPARKLE_SIZE           = 16     -- base size
local SPARKLE_LIFETIME       = 0.35   -- seconds each sparkle lives
local SPARKLE_SPAWN_INTERVAL = 0.035  -- seconds between spawns
local SPARKLE_START_ALPHA    = 0.9
local SPARKLE_END_ALPHA      = 0.0
local SPARKLE_MIN_SCALE      = 0.6    -- shrink to ~60% size over lifetime

------------------------------------------------------------
-- SAVED VARIABLES (defaults)
------------------------------------------------------------

CursorOfPowerDB = CursorOfPowerDB or nil
local db = {
    enableRing     = true,
    enableSparkles = true,
}

local function ApplyDefaults(existing)
    if not existing then existing = {} end
    if existing.enableRing == nil then
        existing.enableRing = true
    end
    if existing.enableSparkles == nil then
        existing.enableSparkles = true
    end
    if existing.minimapAngle == nil then
        existing.minimapAngle = 45 -- default position (45° around the minimap)
    end
    return existing
end

------------------------------------------------------------
-- MAIN RING FRAME (purely visual)
------------------------------------------------------------

local ringFrame = CreateFrame("Frame", "CursorOfPowerFrame", UIParent)
ringFrame:SetSize(RING_SIZE, RING_SIZE)
ringFrame:SetFrameStrata("TOOLTIP")
ringFrame:SetIgnoreParentScale(true)

local ringTex = ringFrame:CreateTexture(nil, "OVERLAY")
ringTex:SetAllPoints(true)
ringTex:SetTexture(RING_TEXTURE)
ringTex:SetBlendMode("BLEND")
ringTex:SetVertexColor(unpack(RING_COLOR))

ringFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

local function UpdateRingVisibility()
    if db.enableRing then
        ringFrame:Show()
    else
        ringFrame:Hide()
    end
end

------------------------------------------------------------
-- SPARKLE SYSTEM
------------------------------------------------------------

local sparklePool = {}
local activeSparkles = {}
local sparkleTimer = 0

local function AcquireSparkle()
    local sparkle = table.remove(sparklePool)
    if not sparkle then
        sparkle = CreateFrame("Frame", nil, UIParent)
        sparkle:SetFrameStrata("TOOLTIP")
        sparkle:SetIgnoreParentScale(true)
        sparkle:SetSize(SPARKLE_SIZE, SPARKLE_SIZE)

        local tex = sparkle:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(true)
        tex:SetBlendMode("ADD")
        sparkle.tex = tex
    end

    sparkle:Show()
    return sparkle
end

local function ReleaseSparkle(sparkle)
    sparkle:Hide()
    sparkle.life = nil
    sparkle.maxLife = nil
    table.insert(sparklePool, sparkle)
end

local function ClearAllSparkles()
    for i = #activeSparkles, 1, -1 do
        local s = activeSparkles[i]
        ReleaseSparkle(s)
        activeSparkles[i] = nil
    end
end

local function SpawnSparkle(x, y)
    if not db.enableSparkles then
        return
    end

    local sparkle = AcquireSparkle()

    -- Pick random sparkle texture
    local texPath = SPARKLE_TEXTURES[math.random(#SPARKLE_TEXTURES)]
    sparkle.tex:SetTexture(texPath)

    -- Position near cursor
    sparkle:ClearAllPoints()
    local dx = (math.random() - 0.5) * 8
    local dy = (math.random() - 0.5) * 8
    sparkle:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + dx, y + dy)

    -- Random size variation
    local sizeVar = 0.7 + math.random() * 0.6 -- 0.7–1.3
    sparkle:SetSize(SPARKLE_SIZE * sizeVar, SPARKLE_SIZE * sizeVar)

    -- Lifespan
    sparkle.life    = SPARKLE_LIFETIME
    sparkle.maxLife = SPARKLE_LIFETIME

    -- Alpha
    sparkle.tex:SetVertexColor(1, 1, 1, SPARKLE_START_ALPHA)

    table.insert(activeSparkles, sparkle)
end

------------------------------------------------------------
-- DRIVER FRAME (always runs OnUpdate)
------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(self, elapsed)
    local x, y = GetCursorPosition()
    if not x or not y then
        return
    end

    -- Move ring (only if enabled)
    if db.enableRing then
        ringFrame:ClearAllPoints()
        ringFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        ringFrame:Show()
    else
        ringFrame:Hide()
    end

    -- Sparkle spawning (only when enabled)
    if db.enableSparkles then
        sparkleTimer = sparkleTimer + (elapsed or 0)
        while sparkleTimer >= SPARKLE_SPAWN_INTERVAL do
            SpawnSparkle(x, y)
            sparkleTimer = sparkleTimer - SPARKLE_SPAWN_INTERVAL
        end
    end

    -- Sparkles ALWAYS update so they fade out even after disabling
    for i = #activeSparkles, 1, -1 do
        local s = activeSparkles[i]
        s.life = s.life - elapsed
        if s.life <= 0 then
            ReleaseSparkle(s)
            table.remove(activeSparkles, i)
        else
            local t = 1 - (s.life / s.maxLife) -- 0 at birth, 1 at end

            -- Fade alpha
            local alpha = SPARKLE_START_ALPHA + (SPARKLE_END_ALPHA - SPARKLE_START_ALPHA) * t
            s.tex:SetVertexColor(1, 1, 1, alpha)

            -- Shrink over time
            local scale = 1 - (1 - SPARKLE_MIN_SCALE) * t
            local size  = SPARKLE_SIZE * scale
            s:SetSize(size, size)
        end
    end
end)


------------------------------------------------------------
-- MINIMAP BUTTON
------------------------------------------------------------

local minimapButton = CreateFrame("Button", "CursorOfPowerMinimapButton", Minimap)
minimapButton:SetSize(32, 32)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)

-- Allow both clicks and dragging
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

-- Border (round frame)
local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetSize(54, 54)
overlay:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

-- Icon inside the circle
local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\AddOns\\CursorOfPower\\CursorOfPowerIcon.tga")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) -- crop corners so it fits the round frame
icon:SetSize(20, 20)
icon:SetPoint("CENTER", minimapButton, "CENTER", 1, 1)
minimapButton.icon = icon

-- Position function using angle saved in db
local function UpdateMinimapButtonPosition()
    if not db or not Minimap then return end

    local angle = math.rad(db.minimapAngle or 45)
    local radius = (Minimap:GetWidth() / 2) + 5

    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Tooltip
local function UpdateTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Cursor of Power", 1, 0.82, 0)
    local ringStatus     = db.enableRing     and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local sparklesStatus = db.enableSparkles and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    GameTooltip:AddLine("Left-click: Toggle circle (" .. ringStatus .. ")", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Toggle sparkles (" .. sparklesStatus .. ")", 1, 1, 1)
    GameTooltip:AddLine("Drag with Left-click to move button.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

minimapButton:SetScript("OnEnter", function(self)
    UpdateTooltip(self)
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Click handling (same ToggleRing / ToggleSparkles you already have)
local function ToggleRing()
    db.enableRing = not db.enableRing
    UpdateRingVisibility()
    if db.enableRing then
        print("|cff00ffffCursor of Power|r: Circle enabled.")
    else
        print("|cff00ffffCursor of Power|r: Circle disabled.")
    end
end

local function ToggleSparkles()
    db.enableSparkles = not db.enableSparkles
    if not db.enableSparkles then
        ClearAllSparkles()
    end

    if db.enableSparkles then
        print("|cff00ffffCursor of Power|r: Sparkles enabled.")
    else
        print("|cff00ffffCursor of Power|r: Sparkles disabled.")
    end
end

minimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        ToggleRing()
    elseif button == "RightButton" then
        ToggleSparkles()
    end

    if GameTooltip:IsOwned(self) then
        UpdateTooltip(self)
    end
end)

-- Drag logic: move around the minimap edge and save angle
minimapButton:SetScript("OnDragStart", function(self)
    self.isDragging = true
end)

minimapButton:SetScript("OnDragStop", function(self)
    self.isDragging = false
end)

minimapButton:SetScript("OnUpdate", function(self)
    if not self.isDragging then return end

    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()

    -- Use Minimap's scale here, NOT UIParent's, or you'll get offset
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale

    local angle = math.atan2(cy - my, cx - mx)
    db.minimapAngle = math.deg(angle)

    UpdateMinimapButtonPosition()
end)

-- Initial placement
UpdateMinimapButtonPosition()



------------------------------------------------------------
-- EVENT HANDLER (LOAD SAVED SETTINGS)
------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        CursorOfPowerDB = ApplyDefaults(CursorOfPowerDB)
        db = CursorOfPowerDB

        UpdateRingVisibility()
        UpdateMinimapButtonPosition()

        self:UnregisterEvent("ADDON_LOADED")
    end
end)
