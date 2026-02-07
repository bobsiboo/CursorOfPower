-- CursorOfPower_Social.lua
-- Social rings (friends / ignores / bnet / guild / communities)
-- Uses SocialCache for data; owns all frames + rendering.

local addonName, ns = ...
local SocialCache = ns.SocialCache or {}

------------------------------------------------------------
-- Debug helper (off by default)
------------------------------------------------------------

local DEBUG = false

local function dprint(...)
    if not DEBUG then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff88[CoP Social]|r " .. table.concat(
        (function(...)
            local t = {}
            for i = 1, select("#", ...) do
                t[#t+1] = tostring(select(i, ...))
            end
            return t
        end)(...),
        " "
    ))
end

------------------------------------------------------------
-- Core compatibility (requires CursorOfPower >= 1.4.0)
------------------------------------------------------------

local REQUIRED_CORE_VERSION = "1.4.0"
local compatOK = false

local function ParseVersion(v)
    if not v then return 0, 0, 0 end
    local a, b, c = v:match("^(%d+)%.(%d+)%.?(%d*)$")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c ~= "" and c or "0") or 0
end

local function IsVersionAtLeast(v, req)
    local A, B, C = ParseVersion(v)
    local rA, rB, rC = ParseVersion(req)
    if A ~= rA then return A > rA end
    if B ~= rB then return B > rB end
    return C >= rC
end

local function CheckCoreCompatibility()
    local core = _G.CursorOfPower
    if not core or not core.version then
        print("|cffff5555[Cursor of Power: Social]|r Core addon not found or too old (no API).")
        return false
    end

    if not IsVersionAtLeast(core.version, REQUIRED_CORE_VERSION) then
        print("|cffff5555[Cursor of Power: Social]|r Core version "
            .. core.version .. " is too old. Require "
            .. REQUIRED_CORE_VERSION .. "+.")
        return false
    end

    dprint("Core version OK:", core.version)
    return true
end

local compatFrame = CreateFrame("Frame")
compatFrame:RegisterEvent("PLAYER_LOGIN")
compatFrame:SetScript("OnEvent", function(self, event)
    compatOK = CheckCoreCompatibility()
    self:UnregisterEvent("PLAYER_LOGIN")
end)

------------------------------------------------------------
-- Colors & config
------------------------------------------------------------

-- Outer ring = community ring (guild > communities)
local COLOR_COMMUNITY_GUILD     = { r = 0.36, g = 0.91, b = 0.10 } -- #5be81a
local COLOR_COMMUNITY_COMMUNITY = { r = 0.66, g = 0.26, b = 0.99 } -- #a842fc

-- Middle ring = BNet > friendlist > ignore
local COLOR_BNET   = { r = 0.00, g = 0.80, b = 1.00 }
local COLOR_FRIEND = { r = 0.20, g = 1.00, b = 0.60 }
local COLOR_IGNORE = { r = 1.00, g = 0.10, b = 0.10 }

local TRACKED_UNIT = "mouseover"
local CORE_TEXTURE = "Interface\\AddOns\\CursorOfPower\\media\\Circle.tga"

------------------------------------------------------------
-- Visual frame + ring textures
------------------------------------------------------------

local socialFrame = CreateFrame("Frame", "CursorOfPowerSocialFrame", UIParent)
socialFrame:SetFrameStrata("TOOLTIP")
socialFrame:SetIgnoreParentScale(true)
socialFrame:Hide()

-- Middle ring (friends / BNet / ignore)
local middleRing = socialFrame:CreateTexture(nil, "ARTWORK")
middleRing:SetTexture(CORE_TEXTURE)
middleRing:SetPoint("CENTER")

-- Outer ring (guild / communities)
local outerRing = socialFrame:CreateTexture(nil, "ARTWORK")
outerRing:SetTexture(CORE_TEXTURE)
outerRing:SetPoint("CENTER")

local function SetRing(tex, color)
    if not color then
        tex:Hide()
    else
        tex:SetVertexColor(color.r, color.g, color.b, 1)
        tex:Show()
    end
end

------------------------------------------------------------
-- Social classification using SocialCache
------------------------------------------------------------

local function GetFriendRingColor(unit)
    if not UnitIsPlayer(unit) then
        return nil
    end

    -- Guard for nil functions, just in case
    if SocialCache.IsUnitOnBNetFriend and SocialCache.IsUnitOnBNetFriend(unit) then
        return COLOR_BNET
    end

    if SocialCache.IsUnitOnFriendList and SocialCache.IsUnitOnFriendList(unit) then
        return COLOR_FRIEND
    end

    if SocialCache.IsUnitIgnored and SocialCache.IsUnitIgnored(unit) then
        return COLOR_IGNORE
    end

    return nil
end

local function GetCommunityRingColor(unit)
    if not UnitIsPlayer(unit) then
        return nil
    end

    if SocialCache.IsUnitGuildMate and SocialCache.IsUnitGuildMate(unit) then
        return COLOR_COMMUNITY_GUILD
    end

    if SocialCache.IsUnitInCommunities and SocialCache.IsUnitInCommunities(unit) then
        return COLOR_COMMUNITY_COMMUNITY
    end

    return nil
end

------------------------------------------------------------
-- Update functions
------------------------------------------------------------

local function GetTrackedUnitKey(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        return nil
    end

    local name, realm = UnitName(unit)
    if not name then
        return nil
    end

    -- Include realm if available to avoid collisions
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end

    return name
end

local lastUnitKey

local function UpdateSocialRings(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        socialFrame:Hide()
        return
    end

    local friendColor    = GetFriendRingColor(unit)
    local communityColor = GetCommunityRingColor(unit)

    SetRing(middleRing,   friendColor)
    SetRing(outerRing,    communityColor)

    if friendColor or communityColor then
        socialFrame:Show()
    else
        socialFrame:Hide()
    end
end

local function UpdateSocialFramePosition()
    local x, y = GetCursorPosition()
    if not x then return end

    socialFrame:ClearAllPoints()
    socialFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

    local baseSize = 32
    if _G.CursorOfPowerFrame then
        baseSize = _G.CursorOfPowerFrame:GetWidth() or baseSize
    end

    local MIDDLE_FACTOR = 1.3
    local OUTER_FACTOR  = 1.6

    local outerSize  = baseSize * OUTER_FACTOR
    local middleSize = baseSize * MIDDLE_FACTOR

    socialFrame:SetSize(outerSize, outerSize)
    outerRing:SetSize(outerSize, outerSize)
    middleRing:SetSize(middleSize, middleSize)
end

------------------------------------------------------------
-- Driver frame: always gets OnUpdate
------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
    if not compatOK then
        socialFrame:Hide()
        return
    end

    -- Use a safe key instead of GUID (GUID is a secret value now)
    local unitKey = GetTrackedUnitKey(TRACKED_UNIT)

    if unitKey ~= lastUnitKey then
        lastUnitKey = unitKey
        if unitKey then
            UpdateSocialRings(TRACKED_UNIT)
        else
            socialFrame:Hide()
        end
    end

    if socialFrame:IsShown() then
        UpdateSocialFramePosition()
    end
end)

dprint("CursorOfPower_Social.lua loaded, driver active")

