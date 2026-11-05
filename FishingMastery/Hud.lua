-- The HUD: a compact, movable bar with the session numbers, shown from the first cast until the
-- session ends (on by default). Updates when an attempt ends, on skill changes and login, and
-- once per second only while a lure is shown. Unnamed, insecure frame; never touches protected
-- frames. Texts come from HudModel.lua.
local _, ns = ...

local setmetatable, type, ipairs, pairs, tonumber = setmetatable, type, ipairs, pairs, tonumber
local match, lower = string.match, string.lower
local isSecret = issecretvalue or function()
    return false
end
local L, Frames, HudModel, Session, Context = ns.L, ns.Frames, ns.HudModel, ns.Session, ns.Context
local Call = Context.Call

local Hud = {}
Hud.__index = Hud
ns.Hud = Hud

-- Account-wide HUD settings (FishingMasteryDB.settings.hud); the position is per character.
Hud.DEFAULTS = { enabled = true, locked = false, scale = 1, style = "full" }
Hud.STYLES = { full = true, text = true }
Hud.MIN_SCALE, Hud.MAX_SCALE = 0.5, 2
Hud.POSITION_KEY = "hud"
Hud.FALLBACK = { point = "TOP", x = 0, y = -140 }
Hud.WIDTH, Hud.TEXT_WIDTH, Hud.LINE = 240, 420, 14
Hud.LINES = { "session", "rates", "skill", "lure", "last" }
Hud.GREY, Hud.WHITE = { 0.55, 0.55, 0.55 }, { 1, 1, 1 }
Hud.TICK = 1 -- seconds between updates while a lure is shown

-- settings.hud with every missing or invalid value set to its default.
function Hud.Settings(settings)
    local hud = type(settings.hud) == "table" and settings.hud or {}
    settings.hud = hud
    for key, value in pairs(Hud.DEFAULTS) do
        if type(hud[key]) ~= type(value) then
            hud[key] = value
        end
    end
    if not Hud.STYLES[hud.style] then
        hud.style = Hud.DEFAULTS.style
    end
    return hud
end

-- deps: { env, bus, castLog, settings (db.settings), store (FishingMasteryCharDB.ui),
-- serverTime(), after(seconds, fn) (nil: no timers) }.
function Hud.Start(deps)
    local self = setmetatable({
        env = deps.env,
        castLog = deps.castLog,
        settings = Hud.Settings(deps.settings),
        thresholds = ns.Stats.Thresholds(deps.settings.thresholds),
        store = deps.store,
        serverTime = deps.serverTime,
        after = deps.after,
        idleFor = nil, -- session.last the idle timer was set for
        ticking = false,
        forced = false, -- shown by /fm hud show without an open session
    }, Hud)
    local function refresh()
        self:Refresh()
    end
    deps.bus:On("SKILL_LINES_CHANGED", refresh)
    deps.bus:On("PLAYER_ENTERING_WORLD", refresh)
    deps.bus:On("ITEM_DATA_LOAD_RESULT", function(_, itemID)
        if not isSecret(itemID) and itemID == self.waitingItem then
            self.waitingItem = nil
            self:Refresh()
        end
    end)
    return self
end

local function build(self)
    local env = self.env
    local frame = Frames.Create(env, "Frame", env.UIParent)
    frame:SetFrameStrata("MEDIUM")
    Frames.RestorePosition(frame, env, self.store, Hud.POSITION_KEY, Hud.FALLBACK)
    Frames.MakeMovable(frame, self.store, Hud.POSITION_KEY)
    frame:SetScript("OnDragStart", function(f)
        if not self.settings.locked then
            f:StartMoving()
        end
    end)
    frame:SetScript(
        "OnEnter",
        ns.Guard.Wrap("hud:tooltip", function(f)
            self:ShowTooltip(f)
        end)
    )
    frame:SetScript("OnLeave", function()
        local tip = self.env.GameTooltip
        if tip then
            tip:Hide()
        end
    end)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0, 0.55)
    self.lines = {}
    for i, name in ipairs(Hud.LINES) do
        local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -5 - (i - 1) * Hud.LINE)
        line:SetJustifyH("LEFT")
        self.lines[name] = line
    end
    self.icon = frame:CreateTexture(nil, "ARTWORK")
    self.icon:SetSize(Hud.LINE - 2, Hud.LINE - 2)
    self.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -5 - 4 * Hud.LINE)
    self.frame = frame
    return frame
end

-- Name and icon of the last caught item; an uncached name is requested once and filled in on
-- ITEM_DATA_LOAD_RESULT.
local function itemInfo(self, id)
    if type(id) ~= "number" then
        return nil, nil
    end
    local name = Call(self.env, "C_Item.GetItemInfo", id)
    local icon = Call(self.env, "C_Item.GetItemIconByID", id)
    name = not isSecret(name) and type(name) == "string" and name or nil
    icon = not isSecret(icon) and icon or nil
    if not name and self.requested ~= id then
        self.requested, self.waitingItem = id, id
        Call(self.env, "C_Item.RequestLoadItemDataByID", id)
    end
    return name, icon
end

function Hud:Model(session)
    local rank, modifier = Context.Fishing(self.env)
    local _, lureSeconds = Context.LureTime(self.env)
    local name, icon = itemInfo(self, session.lastItem)
    return HudModel.Build({
        session = session,
        now = self.serverTime(),
        rank = rank,
        modifier = modifier,
        lureSeconds = lureSeconds,
        itemName = name,
        itemIcon = icon,
        thresholds = self.thresholds,
    })
end

-- An empty session for /fm hud show without an open session (to place the HUD).
local function emptySession(now)
    return { start = now, last = now, casts = 0, catches = 0, counts = {}, active = 0 }
end

local function draw(self, model)
    local frame, full = self.frame, self.settings.style == "full"
    local texts = HudModel.Lines(model)
    for i, name in ipairs(Hud.LINES) do
        local line = self.lines[name]
        line:SetShown(full or i == 1)
        line:SetText(full and texts[name] or nil)
    end
    if full then
        local color = texts.grey and Hud.GREY or Hud.WHITE
        self.lines.rates:SetTextColor(color[1], color[2], color[3])
        local last = self.lines.last
        last:ClearAllPoints()
        last:SetPoint("TOPLEFT", frame, "TOPLEFT", texts.icon and 22 or 6, -5 - 4 * Hud.LINE)
        self.icon:SetTexture(texts.icon)
        self.icon:SetShown(texts.icon ~= nil)
        frame:SetSize(Hud.WIDTH, 10 + #Hud.LINES * Hud.LINE)
    else
        self.lines.session:SetText(HudModel.Short(model))
        self.icon:SetShown(false)
        frame:SetSize(Hud.TEXT_WIDTH, 10 + Hud.LINE)
    end
    frame:SetScale(self.settings.scale)
end

-- Ends the session on time when nobody casts: one timer per new last cast.
local function scheduleIdle(self, session)
    if not self.after or self.idleFor == session.last then
        return
    end
    self.idleFor = session.last
    local wait = Session.IDLE - (self.serverTime() - session.last) + 1
    self.after(wait > 0 and wait or 1, function()
        self.idleFor = nil
        self:Refresh()
    end)
end

local function scheduleTick(self)
    if not self.after or self.ticking then
        return
    end
    self.ticking = true
    self.after(Hud.TICK, function()
        self.ticking = false
        self:Refresh()
    end)
end

-- Shows the HUD with fresh numbers while a session is open (or forced), else hides it.
function Hud:Refresh()
    local session = self.castLog and self.castLog:Session()
    if session then
        self.forced = false
    end
    local shown = self.settings.enabled and (session ~= nil or self.forced)
    if not shown then
        if self.frame then
            self.frame:Hide()
        end
        return
    end
    session = session or emptySession(self.serverTime())
    local model = self:Model(session)
    self.model = model
    if not self.frame then
        build(self)
    end
    draw(self, model)
    self.frame:Show()
    if session.casts > 0 then
        scheduleIdle(self, session)
    end
    if model.lureSeconds then
        scheduleTick(self)
    end
end

function Hud:ShowTooltip(owner)
    local tip = self.env.GameTooltip
    if not tip or not self.model then
        return
    end
    tip:SetOwner(owner, "ANCHOR_BOTTOM")
    tip:SetText(L.PREFIX)
    for _, line in ipairs(HudModel.Tooltip(self.model)) do
        tip:AddLine(line, 1, 1, 1, true)
    end
    tip:Show()
end

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
    elseif action == "style" and Hud.STYLES[value] then
        hud.style = value
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
