-- Event frame, SavedVariables setup, character entry, attempt tracker start, and the /fm slash
-- command.
local addonName, ns = ...

local CreateFrame, GetServerTime, GetTimePreciseSec, format, tremove, _G =
    CreateFrame, GetServerTime, GetTimePreciseSec, string.format, table.remove, _G
local L = ns.L

-- The version for the chat: the TOC version the packager wrote from the tag, without the tag's
-- leading "v" ("v1.0.0" -> "1.0.0"), or "development build" in a checkout, where the TOC still
-- holds the packager keyword (or without the API).
function ns.VersionText(raw)
    if type(raw) ~= "string" or raw == "" or raw:find("@", 1, true) then
        return L.VERSION_DEV
    end
    return (raw:gsub("^v(%d)", "%1"))
end

ns.VERSION = ns.VersionText(C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version"))

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
    ns.loadedAt = GetTimePreciseSec() -- load time measurement (/fm dev)
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

-- C_Timer.After with the callback run through the guard, or nil without C_Timer.
local function timer(where)
    if not (C_Timer and C_Timer.After) then
        return nil
    end
    return function(seconds, fn)
        C_Timer.After(seconds, ns.Guard.Wrap(where, fn))
    end
end

-- A setting changed in the panel: apply it at once (T only at the next login).
local function applySetting(key)
    local settings = ns.db.settings
    if key == "countBelow" or key == "greyBelow" then
        local thresholds = ns.Stats.Thresholds(settings.thresholds)
        ns.hud.thresholds, ns.summary.thresholds = thresholds, thresholds
        ns.stats:SetThresholds(thresholds)
    elseif key == "minimapShown" then
        ns.minimap:Update()
    elseif key == "autoLure" and ns.castKey then
        ns.castKey:Update()
    elseif key == "loudSplash" and ns.soundBoost then
        ns.soundBoost:Update()
    elseif key == "hideUI" and ns.hideUI then
        ns.hideUI:Update()
    elseif key == "activeCap" then
        ns.Print(format(L.OPT_CAP_NEXT_LOGIN, ns.Options.Get(settings, "activeCap")))
    end
    ns.hud:Refresh()
end

-- A setting changed outside the settings panel (the Helpers page): applied the same way.
function ns.ApplySetting(key)
    ns.Guard.Call("settings:apply", applySetting, key)
end

-- Settings panel and minimap button (after the main window, which they open).
local function startSettings()
    ns.settingsPanel = ns.SettingsPanel.Start({
        env = _G,
        settings = ns.db.settings,
        onChange = function(key)
            ns.Guard.Call("settings:apply", applySetting, key)
        end,
    })
    ns.minimap = ns.MinimapButton.Start({
        env = _G,
        settings = ns.db.settings,
        store = ns.charDb.ui,
        hud = ns.hud,
        toggleWindow = function()
            if ns.castLog.char then
                ns.mainWindow:Toggle()
            end
        end,
        toggleJournal = function()
            if ns.castLog.char then
                ns.mainWindow:Toggle(ns.JournalWindow.PAGE)
            end
        end,
        openSettings = function()
            if not ns.settingsPanel:Open() then
                ns.Print(L.OPT_UNAVAILABLE)
            end
        end,
    })
end

-- Attempt tracking and the cast log run on the same bus; timers go through the guard. T for
-- this login is set first, so totals counted with another T are counted again.
local function startTracker()
    ns.Totals.SetCap(ns.Options.Get(ns.db.settings, "activeCap"))
    ns.area = ns.Area.New(ns.Zones, function(id)
        return ns.Context.AreaName(_G, id)
    end)
    local after = timer("timer:attempt") or function() end
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
        after = timer("timer:check"),
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
            local cast = castLog:OnAttempt(record)
            ns.hud:Refresh()
            ns.Helpers.OnCast(cast)
        end,
    })
    ns.hud = ns.Hud.Start({
        env = _G,
        bus = bus,
        castLog = castLog,
        settings = ns.db.settings,
        store = ns.charDb.ui,
        serverTime = GetServerTime,
        after = timer("timer:hud"),
        areas = ns.area,
    })
    ns.summary = ns.Summary.Start({
        env = _G,
        castLog = castLog,
        settings = ns.db.settings,
        store = ns.charDb.ui,
        serverTime = GetServerTime,
        print = ns.Print,
    })
    ns.mainWindow = ns.MainWindow.Start({ env = _G, store = ns.charDb.ui })
    ns.stats = ns.StatsWindow.Start({
        env = _G,
        castLog = castLog,
        db = ns.db,
        charKey = ns.charKey,
        store = ns.charDb.ui,
        host = ns.mainWindow,
        serverTime = GetServerTime,
        after = timer("timer:stats"),
    })
    ns.journalWindow = ns.JournalWindow.Start({
        env = _G,
        castLog = castLog,
        db = ns.db,
        charKey = ns.charKey,
        store = ns.charDb.ui,
        host = ns.mainWindow,
        areas = ns.area,
        zones = ns.Zones,
        journal = ns.Journal,
        after = timer("timer:journal"),
    })
    ns.Helpers.Start({
        env = _G,
        bus = bus,
        settings = ns.db.settings,
        store = ns.charDb,
        areas = ns.area,
        print = ns.Print,
        now = GetTimePreciseSec,
        timer = timer,
    })
    ns.recipeRead = ns.RecipeRead.Start({
        env = _G,
        bus = bus,
        db = ns.db,
        isJournal = function(id)
            return ns.journalWindow:IsJournal(id)
        end,
        after = timer("timer:recipes"),
        onStored = function()
            ns.journalWindow:Redraw()
        end,
    })
    startSettings()
    if ns.char then
        ns.ItemTooltip.Start({ env = _G, settings = ns.db.settings, char = ns.char })
    end
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
    local started = GetTimePreciseSec()
    ns.Guard.Call("tracker:start", startTracker)
    local trackerSec = GetTimePreciseSec() - started
    local now = GetServerTime()
    ns.Backup.Take(ns.db, ns.Codec.Day(now), now)
    ns.Guard.Call("dev:start", ns.Dev.Start, {
        db = ns.db,
        bus = bus,
        env = _G,
        now = GetTimePreciseSec,
        serverTime = GetServerTime,
        after = timer("timer:dev"),
        print = ns.Print,
        loadedAt = ns.loadedAt,
        trackerSec = trackerSec,
        isFishingSpell = ns.Tracker.FishingSpellCheck(_G),
    })
end)

SLASH_FM1 = "/fm"
SLASH_FM2 = "/fishingmastery"
SlashCmdList.FM = function(message)
    ns.Guard.Call("slash", ns.Commands.Dispatch, message)
end
