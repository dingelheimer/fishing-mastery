-- Hidden interface while fishing (module 5, Story 8.4; setting "hideUI", off by default): when the
-- fishing line goes out, the game's interface is hidden with SetUIVisibility(false), the call of
-- the game's own Alt+Z binding; nothing of Blizzard's is hooked. It comes back on movement,
-- combat, death, a target change, a whisper, a dialog that needs an answer, a loot window without
-- auto loot, the pole leaving the hand, a loading screen, logout, and the setting turned off. An
-- interface the player hid or brought back with Alt+Z stays the player's. While hidden, a small
-- catch line on WorldFrame (the part of the screen that stays) shows what was caught.
local _, ns = ...

local setmetatable, type, ipairs, pairs, format = setmetatable, type, ipairs, pairs, string.format
local L, Context, Options = ns.L, ns.Context, ns.Options
local isSecret = issecretvalue or function()
    return false
end

local HideUI = {}
HideUI.__index = HideUI
ns.HideUI = HideUI

-- Events that bring the interface back, with the reason kept for the specs and /fm dev.
HideUI.SHOW = {
    PLAYER_STARTED_MOVING = "moving",
    PLAYER_REGEN_DISABLED = "combat",
    PLAYER_DEAD = "dead",
    PLAYER_TARGET_CHANGED = "target",
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_BN_WHISPER = "whisper",
    PARTY_INVITE_REQUEST = "dialog",
    DUEL_REQUESTED = "dialog",
    CONFIRM_SUMMON = "dialog",
    RESURRECT_REQUEST = "dialog",
    READY_CHECK = "dialog",
    TRADE_SHOW = "dialog",
    PLAYER_MOUNT_DISPLAY_CHANGED = "mount",
    LOADING_SCREEN_ENABLED = "loading",
    PLAYER_LEAVING_WORLD = "loading",
    PLAYER_LOGOUT = "logout",
}
HideUI.LINES = 3 -- catch lines shown at once
HideUI.HOLD = 5 -- seconds a catch line stays
HideUI.LINE_HEIGHT = 24

local function shown(env)
    local ui = env.UIParent
    if type(ui) ~= "table" or type(ui.IsShown) ~= "function" then
        return true
    end
    local ok, value = pcall(ui.IsShown, ui)
    return not ok or isSecret(value) or value ~= false
end

-- deps: { env, bus, settings, isFishingSpell(id), after(seconds, fn) }.
function HideUI.Start(deps)
    local env = deps.env
    local self = setmetatable({
        env = env,
        settings = deps.settings,
        after = deps.after,
        hidden = false,
        lines = {},
        token = 0,
    }, HideUI)
    local bus = deps.bus
    bus:On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, _, spellID)
        if deps.isFishingSpell(spellID) then
            self:LineOut()
        end
    end, "player")
    for event, reason in pairs(HideUI.SHOW) do
        bus:On(event, function()
            self:Show(reason)
        end)
    end
    bus:On("LOOT_OPENED", function(_, autoLoot)
        if not (autoLoot == true or autoLoot == 1) then
            self:Show("loot")
        end
    end)
    bus:On("PLAYER_EQUIPMENT_CHANGED", function()
        if not Context.HasPole(env) then
            self:Show("pole")
        end
    end)
    return self
end

-- The fishing line went out: hides the interface (setting on, out of combat, alive, shown).
function HideUI:LineOut()
    local env = self.env
    if self.hidden and shown(env) then
        self.hidden = false -- the player brought it back with Alt+Z; hide again on this cast
    end
    if self.hidden or Options.Get(self.settings, "hideUI") ~= true then
        return
    end
    if
        Context.Call(env, "InCombatLockdown") == true
        or Context.Call(env, "UnitIsDeadOrGhost", "player") == true
        or not shown(env) -- hidden by the player: it stays the player's
    then
        return
    end
    if type(env.SetUIVisibility) ~= "function" or not pcall(env.SetUIVisibility, false) then
        return
    end
    self.hidden = true
    self.hides = (self.hides or 0) + 1
end

-- Brings the interface back (only one Fishing Mastery hid and the player did not show already).
function HideUI:Show(reason)
    if not self.hidden then
        return
    end
    self.hidden = false
    self.shownBy = reason
    self:ClearLines()
    if not shown(self.env) then
        pcall(self.env.SetUIVisibility, true)
    end
end

-- The setting changed: off brings the interface back.
function HideUI:Update()
    if Options.Get(self.settings, "hideUI") ~= true then
        self:Show("setting")
    end
end

local function itemName(env, id)
    local name = Context.Call(env, "C_Item.GetItemInfo", id)
    if isSecret(name) or type(name) ~= "string" or name == "" then
        return format(L.LURE_ITEM, id)
    end
    return name
end

local function colored(env, quality, text)
    local colors = env.ITEM_QUALITY_COLORS
    local color = type(colors) == "table" and type(quality) == "number" and colors[quality]
    if type(color) == "table" and type(color.hex) == "string" then
        return color.hex .. text .. "|r"
    end
    return text
end

local function frame(self)
    local env = self.env
    if self.frame or type(env.WorldFrame) ~= "table" then
        return self.frame
    end
    local f = env.CreateFrame("Frame", nil, env.WorldFrame)
    f:SetFrameStrata("HIGH")
    f:SetSize(480, HideUI.LINES * HideUI.LINE_HEIGHT)
    f:SetPoint("TOP", env.WorldFrame, "TOP", 0, -120)
    f.texts = {}
    for i = 1, HideUI.LINES do
        local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        text:SetPoint("TOP", f, "TOP", 0, -(i - 1) * HideUI.LINE_HEIGHT)
        f.texts[i] = text
    end
    self.frame = f
    return f
end

local function draw(self)
    local f = frame(self)
    if not f then
        return
    end
    for i, text in ipairs(f.texts) do
        text:SetText(self.lines[i] or "")
    end
    f:SetShown(#self.lines > 0)
end

function HideUI:ClearLines()
    self.lines = {}
    self.token = self.token + 1
    if self.frame then
        draw(self)
    end
end

-- A saved cast (CastLog:OnAttempt): its catch on the catch line while the interface is hidden.
function HideUI:OnCast(cast)
    if not self.hidden or type(cast) ~= "table" or cast.out ~= "catch" then
        return
    end
    for _, item in ipairs(cast.loot or {}) do
        local text = format(L.HIDEUI_CATCH, item.qty or 1, itemName(self.env, item.id))
        table.insert(self.lines, 1, colored(self.env, item.q, text))
    end
    while #self.lines > HideUI.LINES do
        table.remove(self.lines)
    end
    draw(self)
    self.token = self.token + 1
    local token = self.token
    if self.after then
        self.after(HideUI.HOLD, function()
            if self.token == token then
                self:ClearLines()
            end
        end)
    end
end
