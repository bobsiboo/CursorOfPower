-- CursorOfPower.lua
-- Version 1.4

local addonName = ...

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local RING_SIZE = 30
local RING_TEXTURE = "Interface\\AddOns\\CursorOfPower\\media\\Circle.tga"

local BASE_RING_COLOR = { 1, 1, 1, 1 }

local currentRingColor = { unpack(BASE_RING_COLOR) }
local targetRingColor  = { unpack(BASE_RING_COLOR) }

local COLOR_TRANSITION_TIME = 0.08

local SPARKLE_TEXTURES = {
    "Interface\\AddOns\\CursorOfPower\\media\\sparkle1.tga",
    "Interface\\AddOns\\CursorOfPower\\media\\sparkle2.tga",
    "Interface\\AddOns\\CursorOfPower\\media\\sparkle3.tga",
}

local SPARKLE_SIZE           = 16
local SPARKLE_LIFETIME       = 0.35
local SPARKLE_SPAWN_INTERVAL = 0.035
local SPARKLE_START_ALPHA    = 0.9
local SPARKLE_END_ALPHA      = 0.0
local SPARKLE_MIN_SCALE      = 0.6

local ELITE_SPARKLE_SIZE_MULT   = 1.8
local ELITE_SPARKLE_BRIGHT_MULT = 1.8

------------------------------------------------------------
-- SAVED VARIABLES
------------------------------------------------------------

CursorOfPowerDB = CursorOfPowerDB or nil
local db = {
    enableRing        = true,
    enableSparkles    = true,
    enableTargetColor = false,
    minimapAngle      = 45,
}

local function ApplyDefaults(existing)
    if not existing then existing = {} end
    if existing.enableRing == nil then existing.enableRing = true end
    if existing.enableSparkles == nil then existing.enableSparkles = true end
    if existing.enableTargetColor == nil then existing.enableTargetColor = false end
    if existing.minimapAngle == nil then existing.minimapAngle = 45 end
    return existing
end

------------------------------------------------------------
-- PLUGIN API
------------------------------------------------------------

CursorOfPower = CursorOfPower or {}
local COP = CursorOfPower

COP.version      = "1.4.0"
COP.currentColor = { unpack(BASE_RING_COLOR) } -- final color actually used

-- Plugin update callbacks (for secondary rings, etc.)
local updateCallbacks = {} -- [source] = function(x, y, size, r, g, b, a)

function COP.RegisterUpdateCallback(source, func)
    if type(source) ~= "string" or func ~= nil and type(func) ~= "function" then
        return
    end
    updateCallbacks[source] = func
end

function COP.UnregisterUpdateCallback(source)
    updateCallbacks[source] = nil
end


local sizeMultBySource      = {}
local sparkleMultBySource   = {}
local colorOverrideBySource = {}

local glowTimeLeft = 0
local glowTotal    = 0.001
local glowIntensity = 0

function COP.SetSizeMultiplier(source, mult)
    if type(mult) ~= "number" or mult <= 0 then
        sizeMultBySource[source] = nil
    else
        sizeMultBySource[source] = mult
    end
end

function COP.SetSparkleDensityMultiplier(source, mult)
    if type(mult) ~= "number" or mult <= 0 then
        sparkleMultBySource[source] = nil
    else
        sparkleMultBySource[source] = mult
    end
end

function COP.SetColorOverride(source, r, g, b, a)
    if not r or not g or not b then
        colorOverrideBySource[source] = nil
    else
        colorOverrideBySource[source] = { r, g, b, a or 1 }
    end
end

function COP.ClearColorOverride(source)
    colorOverrideBySource[source] = nil
end

local function GetEffectiveSizeMultiplier()
    local m = 1
    for _, v in pairs(sizeMultBySource) do
        m = m * v
    end
    return m
end

local function GetEffectiveSparkleDensityMultiplier()
    local m = 1
    for _, v in pairs(sparkleMultBySource) do
        m = m * v
    end
    return m
end

local function GetColorOverride()
    -- Assumes at most one active source in normal use.
    for _, v in pairs(colorOverrideBySource) do
        return v[1], v[2], v[3], v[4]
    end
    return nil
end

function COP.TriggerGlow(intensity, duration)
    glowIntensity = math.max(0, intensity or 1)
    glowTotal     = math.max(0.05, duration or 0.3)
    glowTimeLeft  = glowTotal
end

function COP.IsRingEnabled()
    return db and db.enableRing
end

function COP.IsSparklesEnabled()
    return db and db.enableSparkles
end

function COP.IsTargetColorEnabled()
    return db and db.enableTargetColor
end

------------------------------------------------------------
-- RING FRAME
------------------------------------------------------------

local ringFrame = CreateFrame("Frame", "CursorOfPowerFrame", UIParent)
ringFrame:SetSize(RING_SIZE, RING_SIZE)
ringFrame:SetFrameStrata("TOOLTIP")
ringFrame:SetIgnoreParentScale(true)

local ringTex = ringFrame:CreateTexture(nil, "OVERLAY")
ringTex:SetAllPoints(true)
ringTex:SetTexture(RING_TEXTURE)
ringTex:SetBlendMode("BLEND")
ringTex:SetVertexColor(unpack(currentRingColor))

------------------------------------------------------------
-- UTILITY: ELITE DETECTION
------------------------------------------------------------

local function IsEliteMouseover()
    if not UnitExists("mouseover") then return false end
    local c = UnitClassification("mouseover")
    return (c == "elite" or c == "rareelite" or c == "worldboss")
end

------------------------------------------------------------
-- SPARKLES
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
        ReleaseSparkle(activeSparkles[i])
        activeSparkles[i] = nil
    end
end

local function SpawnSparkle(x, y)
    if not db.enableSparkles then return end

    local sparkle = AcquireSparkle()
    local texPath = SPARKLE_TEXTURES[math.random(#SPARKLE_TEXTURES)]
    sparkle.tex:SetTexture(texPath)

    sparkle:ClearAllPoints()
    local dx = (math.random() - 0.5) * 8
    local dy = (math.random() - 0.5) * 8
    sparkle:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + dx, y + dy)

    local sizeVar = 0.7 + math.random() * 0.6
    if IsEliteMouseover() then
        sizeVar = sizeVar * ELITE_SPARKLE_SIZE_MULT
    end

    local sizeMult = GetEffectiveSizeMultiplier()
    sparkle:SetSize(SPARKLE_SIZE * sizeVar * sizeMult, SPARKLE_SIZE * sizeVar * sizeMult)

    sparkle.life    = SPARKLE_LIFETIME
    sparkle.maxLife = SPARKLE_LIFETIME

    sparkle.tex:SetVertexColor(
        currentRingColor[1],
        currentRingColor[2],
        currentRingColor[3],
        SPARKLE_START_ALPHA
    )

    table.insert(activeSparkles, sparkle)
end

------------------------------------------------------------
-- TARGET-BASED RING COLORING
------------------------------------------------------------

local function GetTargetColor()
    local r, g, b, a = unpack(BASE_RING_COLOR)

    if db.enableTargetColor and UnitExists("mouseover") then
        if UnitIsEnemy("player", "mouseover") then
            r, g, b = 1, 0.2, 0.2
        elseif UnitIsFriend("player", "mouseover") then
            r, g, b = 0.2, 1, 0.2
        else
            local reaction = UnitReaction("player", "mouseover")
            if reaction == 4 then
                r, g, b = 1, 1, 0.3
            end
        end
    end

    return r, g, b, a
end

local function SetTargetColorAsBase()
    for i = 1, 4 do
        currentRingColor[i] = BASE_RING_COLOR[i]
        targetRingColor[i]  = BASE_RING_COLOR[i]
    end
    ringTex:SetVertexColor(unpack(currentRingColor))
    for i = 1, 4 do
        COP.currentColor[i] = currentRingColor[i]
    end
end

local function UpdateRingVisibility()
    if db.enableRing then
        ringFrame:Show()
    else
        ringFrame:Hide()
    end
end

------------------------------------------------------------
-- FRAME UPDATES
------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(self, elapsed)
    local x, y = GetCursorPosition()
    if not x or not y then return end

    local sizeMult = GetEffectiveSizeMultiplier()

    local glowScale = 1
    if glowTimeLeft > 0 then
        glowTimeLeft = glowTimeLeft - elapsed
        if glowTimeLeft < 0 then glowTimeLeft = 0 end
        local f = glowTimeLeft / glowTotal
        glowScale = 1 + 0.25 * glowIntensity * f
    end

    local finalSize = RING_SIZE * sizeMult * glowScale
    ringFrame:SetSize(finalSize, finalSize)

    if db.enableRing then
        ringFrame:ClearAllPoints()
        ringFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        ringFrame:Show()
    else
        ringFrame:Hide()
    end

    local tr, tg, tb, ta = GetTargetColor()
    targetRingColor[1], targetRingColor[2], targetRingColor[3], targetRingColor[4] = tr, tg, tb, ta

    local blend = math.min(1, elapsed / COLOR_TRANSITION_TIME)
    for i = 1, 4 do
        currentRingColor[i] = currentRingColor[i] + (targetRingColor[i] - currentRingColor[i]) * blend
    end

    local orr, org, orb, ora = GetColorOverride()
    local fr, fg, fb, fa
    if orr then
        fr, fg, fb, fa = orr, org, orb, ora
    else
        fr, fg, fb, fa = currentRingColor[1], currentRingColor[2], currentRingColor[3], currentRingColor[4]
    end

    ringTex:SetVertexColor(fr, fg, fb, fa)

    COP.currentColor[1] = fr
    COP.currentColor[2] = fg
    COP.currentColor[3] = fb
    COP.currentColor[4] = fa

        -- Notify registered plugins (secondary rings, etc.)
    if next(updateCallbacks) ~= nil then
        -- x, y are already in screen space; finalSize is the ring size in pixels
        for _, cb in pairs(updateCallbacks) do
            cb(x, y, finalSize, fr, fg, fb, fa)
        end
    end


    if db.enableSparkles then
        local densityMult = GetEffectiveSparkleDensityMultiplier()
        local spawnInterval = SPARKLE_SPAWN_INTERVAL / math.max(0.1, densityMult)
        sparkleTimer = sparkleTimer + elapsed
        while sparkleTimer >= spawnInterval do
            SpawnSparkle(x, y)
            sparkleTimer = sparkleTimer - spawnInterval
        end
    end

    local elite = IsEliteMouseover()
    for i = #activeSparkles, 1, -1 do
        local s = activeSparkles[i]
        s.life = s.life - elapsed

        if s.life <= 0 then
            ReleaseSparkle(s)
            table.remove(activeSparkles, i)
        else
            local t = 1 - (s.life / s.maxLife)
            local alpha = SPARKLE_START_ALPHA + (SPARKLE_END_ALPHA - SPARKLE_START_ALPHA) * t

            local r, g, b = COP.currentColor[1], COP.currentColor[2], COP.currentColor[3]
            if elite then
                r = math.min(1, r * ELITE_SPARKLE_BRIGHT_MULT)
                g = math.min(1, g * ELITE_SPARKLE_BRIGHT_MULT)
                b = math.min(1, b * ELITE_SPARKLE_BRIGHT_MULT)
            end

            s.tex:SetVertexColor(r, g, b, alpha)

            local scale = 1 - (1 - SPARKLE_MIN_SCALE) * t
            local size  = SPARKLE_SIZE * scale * sizeMult
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
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetSize(54, 54)
overlay:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\AddOns\\CursorOfPower\\CursorOfPowerIcon.tga")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetSize(20, 20)
icon:SetPoint("CENTER", minimapButton, "CENTER", 1, 1)
minimapButton.icon = icon

local function UpdateMinimapButtonPosition()
    local angle = math.rad(db.minimapAngle or 45)
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Cursor of Power", 1, 0.82, 0)

    local ring    = db.enableRing        and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local spark   = db.enableSparkles    and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local target  = db.enableTargetColor and "|cff00ff00ON|r" or "|cffff0000OFF|r"

    GameTooltip:AddLine("Left-click: Toggle circle (" .. ring .. ")", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Toggle sparkles (" .. spark .. ")", 1, 1, 1)
    GameTooltip:AddLine("Alt+Right-click: Toggle target color (" .. target .. ")", 1, 1, 1)
    GameTooltip:AddLine("Drag to move.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

minimapButton:SetScript("OnEnter", UpdateTooltip)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ToggleRing()
    db.enableRing = not db.enableRing
    UpdateRingVisibility()
end

local function ToggleSparkles()
    db.enableSparkles = not db.enableSparkles
    if not db.enableSparkles then
        ClearAllSparkles()
    end
end

local function ToggleTargetColor()
    db.enableTargetColor = not db.enableTargetColor
    if not db.enableTargetColor then
        SetTargetColorAsBase()
    end
end

minimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        ToggleRing()
    elseif button == "RightButton" then
        if IsAltKeyDown() then
            ToggleTargetColor()
        else
            ToggleSparkles()
        end
    end

    if GameTooltip:IsOwned(self) then
        UpdateTooltip(self)
    end
end)

minimapButton:SetScript("OnDragStart", function(self) self.isDragging = true end)
minimapButton:SetScript("OnDragStop",  function(self) self.isDragging = false end)

minimapButton:SetScript("OnUpdate", function(self)
    if not self.isDragging then return end

    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale

    local angle = math.atan2(cy - my, cx - mx)
    db.minimapAngle = math.deg(angle)

    UpdateMinimapButtonPosition()
end)

UpdateMinimapButtonPosition()

------------------------------------------------------------
-- EVENT HANDLER
------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        CursorOfPowerDB = ApplyDefaults(CursorOfPowerDB)
        db = CursorOfPowerDB
        COP.db = db

        UpdateRingVisibility()
        UpdateMinimapButtonPosition()
        SetTargetColorAsBase()

        self:UnregisterEvent("ADDON_LOADED")
    end
end)
