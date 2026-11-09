-- /fm hud: show, hide, lock, unlock, reset, scale, and layout (Hud methods; moved out of Hud.lua in
-- Story 9.8). Loaded after Hud.lua.
local _, ns = ...

local tonumber = tonumber
local match, lower = string.match, string.lower
local L, Frames = ns.L, ns.Frames
local Hud = ns.Hud

-- /fm hud commands. Returns the text to print.
function Hud:Command(action, value)
    local hud = self.settings
    if action == "show" then
        hud.enabled, self.forced = true, true
    elseif action == "hide" then
        hud.enabled, self.forced = false, false
    elseif action == "lock" or action == "unlock" then
        hud.locked = action == "lock"
    elseif action == "reset" then
        self.store[Hud.POSITION_KEY], hud.scale = nil, Hud.DEFAULTS.scale
        if self.frame then
            Frames.RestorePosition(self.frame, self.env, self.store, Hud.POSITION_KEY, Hud.FALLBACK)
        end
    elseif action == "scale" then
        local scale = tonumber(value)
        if not scale or scale < Hud.MIN_SCALE or scale > Hud.MAX_SCALE then
            return L.HUD_USAGE
        end
        hud.scale = scale
    elseif action == "layout" and Hud.LAYOUTS[value] then
        hud.layout = value
    else
        return L.HUD_USAGE
    end
    self:Refresh()
    return L["HUD_DONE_" .. action]
end

ns.Commands.Register("hud", L.CMD_HUD, function(rest)
    local action, value = match(rest or "", "^(%S*)%s*(.-)$")
    if not ns.hud then
        ns.Print(L.STATUS_NOT_READY)
        return
    end
    ns.Print(ns.hud:Command(lower(action), lower(value)))
end)
