-- Event frame, SavedVariables setup, login snapshot, recorder start, S14 helper tests, guided run
-- window, and the /fmp slash command. Report, export, and reset commands live in Handover.lua.
local addonName, ns = ...

local CreateFrame, GetServerTime, GetTimePreciseSec = CreateFrame, GetServerTime, GetTimePreciseSec
local random, pcall, _G = math.random, pcall, _G
local L = ns.L

ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

function ns.Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33bbff" .. L.PREFIX .. ":|r " .. text)
end

local frame = CreateFrame("Frame")
local handlers = {}

local function refreshWindow()
    if ns.window then
        ns.Guard.Call("window:refresh", ns.window.Refresh, ns.window)
    end
end

-- Progress changes also end the S14 test key when the step is left or finished.
local function onProgressChange()
    if ns.helpers and ns.progress then
        ns.Guard.Call("helpers:sync", ns.helpers.Sync, ns.helpers, ns.progress)
    end
    refreshWindow()
end

-- Log function for recorders and helper tests: every entry also feeds the step counters.
local function observedLog(kind, data, q)
    local entry = ns.logger:Log(kind, data, q)
    if ns.progress then
        ns.Guard.Call("progress:observe", ns.progress.Observe, ns.progress, kind, data)
    end
    return entry
end

-- Guided run progress over db.progress; survives /reload. A cast-context snapshot is logged for
-- steps that ask for one (S1, S2, S9).
local function startProgress()
    ns.progress = ns.Progress.New(ns.db.progress, ns.Steps, {
        log = function(kind, data, q)
            return ns.logger:Log(kind, data, q)
        end,
        setStep = function(id)
            ns.logger:SetStep(id)
        end,
        snapshot = function(step, phase)
            local data = ns.Context.Collect(_G)
            data.phase = phase
            ns.logger:Log("context", data, step.questions[1])
        end,
        onChange = onProgressChange,
        onAdvance = function()
            ns.Window.PlayCue(_G)
        end,
    })
end

local function ensureWindow()
    if not ns.window then
        ns.window = ns.Window.Create(_G, {
            progress = ns.progress,
            store = ns.db.progress,
            info = function()
                return {
                    snapshot = ns.snapshot,
                    events = #ns.ApiList.EVENTS,
                    helpers = ns.helpers and ns.helpers:Status(),
                }
            end,
            helpers = function()
                return ns.helpers
            end,
        })
    end
    return ns.window
end

-- Bare /fmp toggles the window once the probe is loaded.
ns.Commands.onEmpty = function()
    if ns.progress then
        ns.Guard.Call("window:toggle", function()
            ensureWindow():Toggle()
        end)
    end
end

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then
        return
    end
    frame:UnregisterEvent("ADDON_LOADED")
    FishingMasteryProbeDB = ns.Db.Init(FishingMasteryProbeDB)
    ns.db = FishingMasteryProbeDB
    ns.logger = ns.Logger.New(ns.db.log, {
        now = GetTimePreciseSec,
        sanitize = ns.Serializer.Sanitize,
    })
    local sessionId = ns.Logger.MakeSessionId(GetServerTime(), random(0, 0xffff))
    ns.logger:StartSession(sessionId, ns.VERSION)
    ns.persistence = ns.Db.Mark(ns.db, sessionId)
    ns.Guard.SetSink(function(record)
        ns.logger:Log("lua_error", record)
    end)
    ns.Guard.Call("progress:start", startProgress)
end

-- Registration test for the event scan: a separate frame without a handler, unregistered at once.
local scanFrame = CreateFrame("Frame")
local function tryRegister(event)
    local ok, result = pcall(scanFrame.RegisterEvent, scanFrame, event)
    if ok then
        pcall(scanFrame.UnregisterEvent, scanFrame, event)
        if result == false then
            return false, "returned false"
        end
        return true
    end
    return false, result
end

-- Recorders run on their own bus frame; only events the snapshot could register are used.
local function startRecorders()
    local busFrame = CreateFrame("Frame")
    local bus = ns.Events.New(busFrame, ns.eventSupport)
    busFrame:SetScript("OnEvent", function(_, event, ...)
        bus:Dispatch(event, ...)
    end)
    local after = function() end
    if C_Timer and C_Timer.After then
        after = function(seconds, fn)
            C_Timer.After(seconds, ns.Guard.Wrap("timer", fn))
        end
    end
    ns.recorders = ns.Recorders.Start({
        env = _G,
        bus = bus,
        log = observedLog,
        now = GetTimePreciseSec,
        after = after,
    })
    ns.logger:Log("tooltip_hook", { mode = ns.Recorders.HookTooltip(_G, ns.recorders) }, "Q26")
    ns.Guard.Call("helpers:start", function()
        ns.helpers = ns.Helpers.New({
            env = _G,
            bus = bus,
            log = observedLog,
            now = GetTimePreciseSec,
            after = after,
            fishingSpellID = function()
                return ns.recorders and ns.recorders.fishingSpellID
            end,
            onChange = refreshWindow,
        })
    end)
end

-- Login snapshot (step S0); also run again after /fmp reset so the log keeps the environment.
function ns.RunSnapshot()
    ns.snapshot = ns.Snapshot.Run(_G, {
        log = function(kind, data, q)
            return ns.logger:Log(kind, data, q, "S0")
        end,
        registerEvent = tryRegister,
        persistence = ns.persistence,
    })
    return ns.snapshot
end

function handlers.PLAYER_LOGIN()
    frame:UnregisterEvent("PLAYER_LOGIN")
    ns.eventSupport = ns.RunSnapshot().events
    ns.Guard.Call("recorders:start", startRecorders)
    -- The window opens by itself on the first login only.
    if ns.progress and not ns.db.progress.autoOpened then
        ns.db.progress.autoOpened = true
        ns.Guard.Call("window:auto", function()
            ensureWindow():Show()
        end)
    end
end

-- Q22: tells a first login from a /reload.
function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    ns.logger:Log("entering_world", {
        isInitialLogin = isInitialLogin,
        isReloadingUi = isReloadingUi,
    }, "Q22")
end

-- The S14 test key never outlives the session.
function handlers.PLAYER_LOGOUT()
    if ns.helpers then
        ns.helpers:Shutdown()
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        ns.Guard.Call("event:" .. event, handler, ...)
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")

SLASH_FMP1 = "/fmp"
SlashCmdList.FMP = function(message)
    ns.Guard.Call("slash", ns.Commands.Dispatch, message)
end
