-- The HUD (Draft 5, Story 9.8): the card or the compact line (HudCard.lua) in a movable frame,
-- shown from the first cast until the session ends (on by default). Updates when an attempt ends,
-- on skill and zone changes and login, and once per second only while a lure is shown (the water
-- is read again only on those events, not on the ticks). Numbers from HudModel.lua, the card from
-- HudCardModel.lua. Unnamed, insecure frames; never touches protected frames.
local _, ns = ...

local setmetatable, type, ipairs, pairs, select = setmetatable, type, ipairs, pairs, select
local Frames, HudModel, Context, Style = ns.Frames, ns.HudModel, ns.Context, ns.Style

local Hud = {}
Hud.__index = Hud
ns.Hud = Hud

-- Account-wide HUD settings (FishingMasteryDB.settings.hud); the position is per character.
Hud.DEFAULTS = ns.Options.DEFAULTS.hud
Hud.LAYOUTS = { card = true, compact = true }
Hud.MIN_SCALE, Hud.MAX_SCALE = 0.5, 2
Hud.POSITION_KEY = "hud"
Hud.FALLBACK = { point = "TOP", x = 0, y = -140 }
Hud.QUALITY_HEX = 4 -- C_Item.GetItemQualityColor: hex color
Hud.ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }
Hud.TICK = 1 -- seconds between updates while a lure is shown

-- settings.hud with every missing or invalid value set to its default; a style saved before Epic 9
-- becomes its layout (full: card, text: compact) once.
function Hud.Settings(settings)
    local hud = type(settings.hud) == "table" and settings.hud or {}
    settings.hud = hud
    local layout = ns.Options.Layout(hud)
    for key, value in pairs(Hud.DEFAULTS) do
        if type(hud[key]) ~= type(value) then
            hud[key] = value
        end
    end
    hud.layout, hud.style = layout, nil
    return hud
end

-- deps: { env, bus, castLog, settings (db.settings), store (FishingMasteryCharDB.ui),
-- serverTime(), after(seconds, fn) (nil: no timers), areas (Area resolver, optional) }.
function Hud.Start(deps)
    local self = setmetatable({
        env = deps.env,
        castLog = deps.castLog,
        settings = Hud.Settings(deps.settings),
        thresholds = ns.Stats.Thresholds(deps.settings.thresholds),
        store = deps.store,
        serverTime = deps.serverTime,
        after = deps.after,
        areas = deps.areas,
        ticking = false,
        forced = false, -- shown by /fm hud show without an open session
        requested = {}, -- item IDs with a load callback
    }, Hud)
    local function refresh()
        self:Refresh()
    end
    deps.bus:On("SKILL_LINES_CHANGED", refresh)
    deps.bus:On("PLAYER_ENTERING_WORLD", refresh)
    for _, event in ipairs(Hud.ZONE_EVENTS) do
        deps.bus:On(event, refresh)
    end
    if self.castLog then
        self.castLog:OnSessionEnd(refresh)
    end
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
    frame:SetScript("OnLeave", function(f)
        ns.Tip.Close(self.env, f)
    end)
    self.card = ns.HudCard.Create(env, frame, {
        layout = function()
            self:ToggleLayout()
        end,
        stop = function()
            self:StopSession()
        end,
    })
    for _, view in ipairs({ self.card.card, self.card.compact }) do
        view:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    end
    self.frame = frame
    return frame
end

-- Name, icon, and quality color of an item from the item cache; an uncached name is requested
-- once and the HUD refreshes when it arrives.
local function itemInfo(self, id)
    local items = self.castLog and self.castLog.items
    if not items or type(id) ~= "number" then
        return {}
    end
    local onLoad = nil
    if not self.requested[id] then
        onLoad = function()
            self:Refresh()
        end
    end
    local info = items:Info(id, onLoad)
    if not info.name then
        self.requested[id] = true
    end
    local hex = info.quality
        and select(
            Hud.QUALITY_HEX,
            Context.Call(self.env, "C_Item.GetItemQualityColor", info.quality)
        )
    return { name = info.name, icon = info.icon, hex = type(hex) == "string" and hex or nil }
end

function Hud:Model(session)
    local rank, modifier = Context.Fishing(self.env)
    local _, lureSeconds = Context.LureTime(self.env)
    local info = itemInfo(self, session.lastItem)
    return HudModel.Build({
        session = session,
        now = self.serverTime(),
        rank = rank,
        modifier = modifier,
        lureSeconds = lureSeconds,
        itemName = info.name,
        itemIcon = info.icon,
        thresholds = self.thresholds,
    })
end

-- The smart lure's suggestion for this water ({ name, bonus, icon }), or nil.
local function suggestion(self)
    local now = ns.SmartLure.Now(self.env, self.areas, ns.Journal)
    local choice = now.choice
    if
        not (
            choice
            and choice.lure
            and (choice.reason == "reaches" or choice.reason == "strongest")
        )
    then
        return nil
    end
    local id = choice.lure.id
    return {
        name = now.name(id),
        bonus = choice.lure.bonus,
        icon = Context.Call(self.env, "C_Item.GetItemIconByID", id),
    }
end

-- The HudCardModel input: the session model, the cap, the water, the lures, and the items.
function Hud:CardInput(model)
    local env = self.env
    local _, _, max = Context.Fishing(env)
    local enchant, seconds = Context.LureTime(env)
    local zone = self.settings.zoneLine and self.zone or nil
    local input = {
        model = model,
        max = max,
        zone = zone,
        lure = seconds
            and { bonus = ((ns.Journal or {}).lureEnchants or {})[enchant], seconds = seconds },
        last = itemInfo(self, model.lastItem),
        info = function(id)
            return itemInfo(self, id)
        end,
    }
    if zone and not seconds then
        input.suggestion = suggestion(self)
    end
    return input
end

-- An empty session for /fm hud show without an open session (to place the HUD).
local function emptySession(now)
    return { start = now, last = now, casts = 0, catches = 0, counts = {}, active = 0 }
end

local function draw(self, model)
    local frame, layout = self.frame, self.settings.layout
    self.input = self:CardInput(model)
    ns.HudCard.Draw(self.card, ns.HudCardModel.Build(self.input), layout)
    local view = ns.HudCard.Shown(self.card, layout)
    frame:SetSize(view:GetWidth(), view:GetHeight())
    frame:SetScale(self.settings.scale)
    frame:SetAlpha(self.settings.opacity)
end

local function scheduleTick(self)
    if not self.after or self.ticking then
        return
    end
    self.ticking = true
    self.after(Hud.TICK, function()
        self.ticking = false
        self:Refresh(true)
    end)
end

-- Shows the HUD with fresh numbers while a session is open (or forced), else hides it.
-- keepZone: the lure tick, which reuses the zone line.
function Hud:Refresh(keepZone)
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
    if self.settings.zoneLine and not (keepZone and self.zone) then
        local char = self.castLog and self.castLog.char
        self.zone = ns.HudZone.Read(self.env, self.areas, char, self.thresholds)
    end
    local model = self:Model(session)
    self.model = model
    if not self.frame then
        build(self)
    end
    draw(self, model)
    self.frame:Show()
    if ns.Tip.IsOpen(self.frame) then -- an open tooltip shows the same numbers as the card
        self:ShowTooltip(self.frame)
    end
    if model.lureSeconds then
        scheduleTick(self)
    end
end

-- The HUD tooltip of Draft 6 (HudCardModel.Tip); the dev flag adds the resolved area line.
function Hud:ShowTooltip(owner)
    if not self.input then
        return
    end
    local extra
    if ns.Dev and ns.Dev.Enabled(ns.db) then
        extra = function(tip)
            tip:Line(ns.HudZone.DevAreaLine(self.env, self.areas), Style.ADDON)
        end
    end
    ns.Tip.Open(self.env, owner, ns.HudCardModel.Tip(self.input, extra), "ANCHOR_BOTTOM")
end

-- The layout button: the card or the compact line, saved like the Settings page does.
function Hud:ToggleLayout()
    local settings = self.settings
    settings.layout = settings.layout == "card" and "compact" or "card"
    self:Refresh()
end

-- The stop button: ends the session now; the HUD hides until the next cast.
function Hud:StopSession()
    if self.castLog and self.castLog:StopSession() then
        self:Refresh()
    end
end
