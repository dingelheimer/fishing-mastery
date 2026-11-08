-- /fm helpers (module 5, Story 8.5): what the helpers did this login, for the owner's session
-- check against the tracker: presses of the casting key by what they did (cast, lure, wait), the
-- presses that came from a double right-click, the casts the tracker recorded, and the state of
-- each helper setting. Counts live in memory only; nothing is saved.
local _, ns = ...

local setmetatable, ipairs, format = setmetatable, ipairs, string.format
local L, Options = ns.L, ns.Options

local HelperStatus = {}
HelperStatus.__index = HelperStatus
ns.HelperStatus = HelperStatus

-- deps: { settings, castKey, doubleCast, hideUI, soundBoost }.
function HelperStatus.Start(deps)
    local self = setmetatable({
        settings = deps.settings,
        castKey = deps.castKey,
        doubleCast = deps.doubleCast,
        hideUI = deps.hideUI,
        soundBoost = deps.soundBoost,
        presses = { spell = 0, lure = 0, wait = 0, none = 0 },
        casts = 0,
    }, HelperStatus)
    deps.castKey:OnRelease(function(mode)
        local key = mode or "none"
        self.presses[key] = (self.presses[key] or 0) + 1
    end)
    return self
end

-- A cast the tracker saved (Core's onAttempt).
function HelperStatus:OnCast(cast)
    if cast then
        self.casts = self.casts + 1
    end
end

local function onOff(self, key)
    return Options.Get(self.settings, key) == true and L.HELPERS_ON or L.HELPERS_OFF
end

-- The two chat lines of /fm helpers.
function HelperStatus:Lines()
    local p = self.presses
    return {
        format(
            L.HELPERS_COUNTS,
            p.spell,
            p.lure,
            p.wait,
            self.doubleCast.armedCount or 0,
            self.casts
        ),
        format(
            L.HELPERS_STATE,
            onOff(self, "doubleClick"),
            onOff(self, "autoLure"),
            onOff(self, "loudSplash"),
            self.soundBoost:Active() and L.HELPERS_ACTIVE or L.HELPERS_IDLE,
            onOff(self, "hideUI"),
            self.hideUI.hides or 0
        ),
    }
end

ns.Commands.Register("helpers", L.CMD_HELPERS, function()
    if not ns.helperStatus then
        ns.Print(L.NO_CHARACTER)
        return
    end
    for _, line in ipairs(ns.helperStatus:Lines()) do
        ns.Print(line)
    end
end)
