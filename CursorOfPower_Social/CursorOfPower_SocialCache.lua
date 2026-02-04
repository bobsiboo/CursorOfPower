-- CursorOfPower_SocialCache.lua
-- Social data cache (friends / ignores / bnet / guild / communities)
-- No rendering here; just data + query functions.

local addonName, ns = ...

------------------------------------------------------------
-- Exported SocialCache table
------------------------------------------------------------

local SocialCache = {}
ns.SocialCache = SocialCache

------------------------------------------------------------
-- Debug helper (set DEBUG = true if you need logs)
------------------------------------------------------------

local DEBUG = false

local function dprint(...)
    if not DEBUG then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff88[CoP SocialCache]|r " .. table.concat(
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
-- Internal cache tables
------------------------------------------------------------

local Cache = {
    friends     = {},
    ignores     = {},
    bnet        = {},
    communities = {},
}

------------------------------------------------------------
-- Key helpers
------------------------------------------------------------

local function MakeKey(name, realm)
    if not name then return nil end

    -- Already "Name-Realm"
    if name:find("-", 1, true) and (not realm or realm == "") then
        return name
    end

    if realm and realm ~= "" then
        return name .. "-" .. realm
    end

    return name
end

local function GetUnitKey(unit)
    local guid = UnitGUID(unit)
    if guid then
        return guid
    end

    local name, realm = UnitName(unit)
    if not name then return nil end

    return MakeKey(name, realm)
end

------------------------------------------------------------
-- Guild (no cache needed)
------------------------------------------------------------

function SocialCache.IsUnitGuildMate(unit)
    if not UnitIsPlayer(unit) then return false end
    if not IsInGuild() then return false end

    local myGuild    = GetGuildInfo("player")
    local theirGuild = GetGuildInfo(unit)
    if not myGuild or not theirGuild then return false end

    return myGuild == theirGuild
end

------------------------------------------------------------
-- Friends cache
------------------------------------------------------------

local function RebuildFriendsCache()
    wipe(Cache.friends)
    if not C_FriendList or not C_FriendList.GetNumFriends then return end

    local numFriends = C_FriendList.GetNumFriends() or 0
    dprint("RebuildFriendsCache, numFriends =", numFriends)

    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name then
            local raw = info.name
            local name, realm = raw:match("^([^%-]+)%-(.+)$")
            name  = name or raw
            realm = realm or ""

            if info.guid then
                Cache.friends[info.guid] = true
                dprint(" friend guid:", info.guid, "raw:", raw)
            end

            local key = MakeKey(name, realm)
            if key then
                Cache.friends[key] = true
                dprint(" friend key:", key, "raw:", raw)
            end
        end
    end
end

function SocialCache.IsUnitOnFriendList(unit)
    if not UnitIsPlayer(unit) then return false end
    local key = GetUnitKey(unit)
    if not key then return false end
    local hit = Cache.friends[key] or false
    if DEBUG and hit then
        local name, realm = UnitName(unit)
        dprint("IsUnitOnFriendList HIT for", name or "?", realm or "", "key:", key)
    end
    return hit
end

------------------------------------------------------------
-- Ignore cache
------------------------------------------------------------

local function RebuildIgnoreCache()
    wipe(Cache.ignores)

    local numIgnores = 0
    if C_FriendList and C_FriendList.GetNumIgnores then
        numIgnores = C_FriendList.GetNumIgnores() or 0
    elseif GetNumIgnores then
        numIgnores = GetNumIgnores() or 0
    end

    dprint("RebuildIgnoreCache, numIgnores =", numIgnores)

    for i = 1, numIgnores do
        local raw
        if C_FriendList and C_FriendList.GetIgnoreName then
            raw = C_FriendList.GetIgnoreName(i)
        elseif GetIgnoreName then
            raw = GetIgnoreName(i)
        end

        if raw then
            local name, realm = raw:match("^([^%-]+)%-(.+)$")
            name  = name or raw
            realm = realm or ""
            local key = MakeKey(name, realm)
            if key then
                Cache.ignores[key] = true
                dprint(" ignore key:", key, "raw:", raw)
            end
        end
    end
end

function SocialCache.IsUnitIgnored(unit)
    if not UnitIsPlayer(unit) then return false end
    local key = GetUnitKey(unit)
    if not key then return false end
    local hit = Cache.ignores[key] or false
    if DEBUG and hit then
        local name, realm = UnitName(unit)
        dprint("IsUnitIgnored HIT for", name or "?", realm or "", "key:", key)
    end
    return hit
end

------------------------------------------------------------
-- BNet cache
------------------------------------------------------------

local function RebuildBNetCache()
    wipe(Cache.bnet)
    if not BNGetNumFriends or not C_BattleNet or not C_BattleNet.GetFriendAccountInfo then
        dprint("RebuildBNetCache: BNet API missing")
        return
    end

    local numBNet = BNGetNumFriends()
    dprint("RebuildBNetCache, numBNet =", numBNet)

    for i = 1, numBNet do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo then
            local game = accountInfo.gameAccountInfo
            if game.clientProgram == "WoW" then
                local rawName = game.characterName
                local guid = game.playerGuid or game.playerGUID or game.guid

                if guid then
                    Cache.bnet[guid] = true
                    dprint(" bnet guid:", guid, "name:", rawName or "?")
                end

                if rawName then
                    local key = MakeKey(rawName, game.realmName or game.realmDisplayName)
                    if key then
                        Cache.bnet[key] = true
                        dprint(" bnet key:", key)
                    end
                end
            end
        end
    end
end

function SocialCache.IsUnitOnBNetFriend(unit)
    if not UnitIsPlayer(unit) then return false end
    local key = GetUnitKey(unit)
    if not key then return false end
    local hit = Cache.bnet[key] or false
    if DEBUG and hit then
        local name, realm = UnitName(unit)
        dprint("IsUnitOnBNetFriend HIT for", name or "?", realm or "", "key:", key)
    end
    return hit
end

------------------------------------------------------------
-- Community cache
------------------------------------------------------------

local function RebuildCommunityCache()
    wipe(Cache.communities)

    if not C_Club or not C_Club.IsEnabled or not C_Club.IsEnabled() then
        dprint("RebuildCommunityCache: Clubs disabled")
        return
    end

    local clubs = C_Club.GetSubscribedClubs()
    if not clubs then
        dprint("RebuildCommunityCache: no clubs")
        return
    end

    dprint("RebuildCommunityCache, num clubs:", #clubs)

    for _, club in ipairs(clubs) do
        local info = C_Club.GetClubInfo(club.clubId)
        if info and info.clubType == Enum.ClubType.Character then
            local members = C_Club.GetClubMembers(club.clubId)
            if members then
                for _, memberId in ipairs(members) do
                    local memberInfo = C_Club.GetMemberInfo(club.clubId, memberId)
                    if memberInfo then
                        if memberInfo.guid then
                            Cache.communities[memberInfo.guid] = true
                        elseif memberInfo.name then
                            local key = MakeKey(memberInfo.name, memberInfo.realm)
                            if key then
                                Cache.communities[key] = true
                            end
                        end
                    end
                end
            end
        end
    end
end

function SocialCache.IsUnitInCommunities(unit)
    if not UnitIsPlayer(unit) then return false end
    local key = GetUnitKey(unit)
    if not key then return false end
    local hit = Cache.communities[key] or false
    if DEBUG and hit then
        local name, realm = UnitName(unit)
        dprint("IsUnitInCommunities HIT for", name or "?", realm or "", "key:", key)
    end
    return hit
end

------------------------------------------------------------
-- Events: rebuild caches when social data changes
------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("FRIENDLIST_UPDATE")
eventFrame:RegisterEvent("IGNORELIST_UPDATE")
eventFrame:RegisterEvent("BN_CONNECTED")
eventFrame:RegisterEvent("BN_DISCONNECTED")
eventFrame:RegisterEvent("INITIAL_CLUBS_LOADED")
eventFrame:RegisterEvent("CLUB_MEMBER_ADDED")
eventFrame:RegisterEvent("CLUB_MEMBER_REMOVED")

eventFrame:SetScript("OnEvent", function(_, event)
    dprint("Event:", event, "- rebuilding caches")
    RebuildFriendsCache()
    RebuildIgnoreCache()
    RebuildBNetCache()
    RebuildCommunityCache()
end)
