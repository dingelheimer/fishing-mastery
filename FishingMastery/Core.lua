-- Event frame, SavedVariables setup, character entry, attempt tracker start, and the /fm slash
-- command.
local addonName, ns = ...

local CreateFrame, GetServerTime, GetTimePreciseSec, format, tremove, _G =
    CreateFrame, GetServerTime, GetTimePreciseSec, string.format, table.remove, _G
local L = ns.L

ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

function ns.Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33bbff" .. L.PREFIX .. ":|r " .. text)
end

-- Recent Lua errors for /fm, kept in memory only.
ns.MAX_RECENT_ERRORS = 10
ns.recentErrors = {}
ns.Guard.SetSink(function(record)
    local recent = ns.recentErrors
    recent[#recent + 1] = record
    if #recent > ns.MAX_RECENT_ERRORS then
        tremove(recent, 1)
    end
end)

local frame = CreateFrame("Frame")
local bus = ns.Events.New(frame)
ns.bus = bus
frame:SetScript("OnEvent", function(_, event, ...)
    bus:Dispatch(event, ...)
end)

bus:On("ADDON_LOADED", function(_, loadedName)
    if loadedName ~= addonName then
        return
    end
    bus:Off("ADDON_LOADED")
    local db, info = ns.Db.Init(FishingMasteryDB, { now = GetServerTime() })
    FishingMasteryDB = db
    FishingMasteryCharDB = ns.Db.InitChar(FishingMasteryCharDB)
    ns.db, ns.charDb, ns.loadInfo = db, FishingMasteryCharDB, info
    if info.newer then
        ns.Print(format(L.DB_NEWER, info.newer, ns.Db.SCHEMA_VERSION))
    elseif info.migratedFrom then
        ns.Print(format(L.MIGRATED, info.migratedFrom, db.schemaVersion))
    end
end)

-- Attempt tracking and the cast log run on the same bus; the timer goes through the guard.
local function startTracker()
    local after = function() end
    if C_Timer and C_Timer.After then
        after = function(seconds, fn)
            C_Timer.After(seconds, ns.Guard.Wrap("timer:attempt", fn))
        end
    end
    local castLog = ns.CastLog.Start({
        env = _G,
        bus = bus,
        char = ns.char,
        serverTime = GetServerTime,
        report = function(entries)
            ns.Print(format(L.QUARANTINE, #entries))
        end,
        settings = ns.db.settings,
        remind = function()
            ns.Print(L.REMINDER)
        end,
    })
    ns.castLog = castLog
    ns.tracker = ns.Tracker.Start({
        env = _G,
        bus = bus,
        now = GetTimePreciseSec,
        after = after,
        context = function()
            return castLog:Context()
        end,
        loot = function()
            return castLog:Loot()
        end,
        onAttempt = function(record)
            castLog:OnAttempt(record)
        end,
    })
end

bus:On("PLAYER_LOGIN", function()
    bus:Off("PLAYER_LOGIN")
    if not ns.db then
        return
    end
    ns.charKey, ns.char = ns.Character.Ensure(ns.db, _G, GetServerTime())
    if not ns.charKey then
        ns.Print(L.NO_CHARACTER)
    end
    ns.Db.ConfirmLogin(ns.db, ns.loadInfo, ns.Guard.errors)
    ns.Guard.Call("tracker:start", startTracker)
    local now = GetServerTime()
    ns.Backup.Take(ns.db, ns.Codec.Day(now), now)
end)

SLASH_FM1 = "/fm"
SLASH_FM2 = "/fishingmastery"
SlashCmdList.FM = function(message)
    ns.Guard.Call("slash", ns.Commands.Dispatch, message)
end
