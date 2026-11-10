-- Session summary: shown when a session ends after 15 minutes without a cast, and on
-- /fm summary for the current or last session. A card in the HUD card's look (default; Story
-- 10.5, SummaryCardModel drawn by DetailPane) or a block in the own chat frame (setting; the text
-- lines of SummaryModel). Item data comes from the item cache; names that load later refresh the
-- open window. Nothing is sent to other chat channels. Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, type, ipairs, pairs, lower, match, select =
    setmetatable, type, ipairs, pairs, string.lower, string.match, select
local L, Frames, SummaryModel, Context = ns.L, ns.Frames, ns.SummaryModel, ns.Context

local Summary = {}
Summary.__index = Summary
ns.Summary = Summary

-- Account-wide summary settings (FishingMasteryDB.settings.summary).
Summary.DEFAULTS = ns.Options.DEFAULTS.summary
Summary.STYLES = { window = true, chat = true }
Summary.POSITION_KEY = "summary"
Summary.WIDTH, Summary.PAD = 300, 12
Summary.TEMPLATE = "TooltipBackdropTemplate" -- the HUD card's frame (Story 9.1)
Summary.BACK = { 0.03, 0.03, 0.06, 0.92 } -- without the template
Summary.BUTTON = 30 -- room for the Close button under the card
Summary.BUTTON_LEVEL = 5 -- frame levels of the Close button above the window
Summary.CLOSE_WIDTH = 90
Summary.QUALITY_HEX = 4 -- C_Item.GetItemQualityColor: hex

function Summary.Settings(settings)
    local summary = type(settings.summary) == "table" and settings.summary or {}
    settings.summary = summary
    if not Summary.STYLES[summary.style] then
        summary.style = Summary.DEFAULTS.style
    end
    return summary
end

-- deps: { env, castLog, settings (db.settings), store (FishingMasteryCharDB.ui), serverTime(),
-- print(text) }.
function Summary.Start(deps)
    local self = setmetatable({
        env = deps.env,
        castLog = deps.castLog,
        settings = Summary.Settings(deps.settings),
        thresholds = ns.Stats.Thresholds(deps.settings.thresholds),
        store = deps.store,
        serverTime = deps.serverTime,
        print = deps.print,
    }, Summary)
    if self.castLog then
        self.castLog:OnSessionEnd(function(session)
            self:Show(session)
        end)
    end
    return self
end

-- The summary model of a session; onLoad runs when an uncached item's data arrives.
function Summary:Model(session, onLoad)
    local castLog = self.castLog
    local items = {}
    for id in pairs(type(session.items) == "table" and session.items or {}) do
        local info = castLog.items:Info(id, onLoad)
        local hex = info.quality
            and select(
                Summary.QUALITY_HEX,
                Context.Call(self.env, "C_Item.GetItemQualityColor", info.quality)
            )
        info.hex = type(hex) == "string" and hex or nil
        items[id] = info
    end
    local model = SummaryModel.Build({
        session = session,
        now = self.serverTime(),
        totals = castLog.char and castLog.char.totals,
        items = items,
        thresholds = self.thresholds,
    })
    self.model = model
    return model
end

-- Summary lines of a session (the chat style).
function Summary:Lines(session, onLoad)
    local model = self:Model(session, onLoad)
    return SummaryModel.Lines(model, model.compare and Context.MapName(self.env, model.compare.map))
end

-- The Close button: a plain button in the dropdown look, like the HUD's own buttons. The shared
-- Controls.Button (a Button built on InsetFrameTemplate) took the mouse on this window but its
-- click never arrived (owner check, Story 10.5); a plain button does.
local function closeButton(env, frame)
    local button = env.CreateFrame("Button", nil, frame)
    button:SetSize(Summary.CLOSE_WIDTH, ns.Controls.HEIGHT)
    button:RegisterForClicks("LeftButtonUp")
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(button)
    local b = ns.Controls.BACK
    back:SetColorTexture(b[1], b[2], b[3], b[4])
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    local h = ns.Style.HOVER
    highlight:SetColorTexture(h[1], h[2], h[3], h[4])
    local label = button:CreateFontString(nil, "OVERLAY", ns.Style.FONTS.small)
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(label)
    button:SetText(L.BUTTON_CLOSE)
    button:SetScript(
        "OnClick",
        ns.Guard.Wrap("summary:close", function()
            frame:Hide()
        end)
    )
    return button
end

local function build(self)
    local env = self.env
    local frame, template = Frames.CreateFirst(env, "Frame", env.UIParent, { Summary.TEMPLATE })
    if not template then
        local back = frame:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(frame)
        local c = Summary.BACK
        back:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    ns.Look.Backing(frame) -- the HUD background setting (Story 10.4)
    -- DIALOG keeps it above the game's windows; not top-level: a top-level frame raises itself on
    -- every show and click but not its buttons, which then lie under it (owner check, Story 10.5).
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(Summary.WIDTH)
    Frames.RestorePosition(frame, env, self.store, Summary.POSITION_KEY)
    Frames.MakeMovable(frame, self.store, Summary.POSITION_KEY)
    local pad = Summary.PAD
    self.pane = ns.DetailPane.Create(env, frame, pad, -pad, Summary.WIDTH - 2 * pad, 2000)
    self.closeButton = closeButton(env, frame)
    self.closeButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, pad - 2)
    self.frame = frame
    return frame
end

local function title(session)
    return session.ended and L.SUMMARY_TITLE or L.SUMMARY_TITLE_OPEN
end

local function render(self, session)
    local model = self:Model(session, function()
        if self.shown == session and self.frame and self.frame:IsShown() then
            render(self, session)
        end
    end)
    local frame = self.frame or build(self)
    local input = {
        session = session,
        mapName = function(map)
            return Context.MapName(self.env, map)
        end,
    }
    self.pane:Draw(ns.SummaryCardModel.Draw(model, input))
    local height = self.pane:Height()
    self.pane.frame:SetHeight(height > 1 and height or 1) -- ends above the Close button
    frame:SetHeight(height + 2 * Summary.PAD + Summary.BUTTON)
    frame:Show()
    -- Above the window and the card's text frame at its current level (/fstack in the owner
    -- check showed the button under both).
    self.closeButton:SetFrameLevel(frame:GetFrameLevel() + Summary.BUTTON_LEVEL)
end

-- Shows the summary of a session in the window or in the own chat frame.
function Summary:Show(session)
    if type(session) ~= "table" then
        return
    end
    self.shown = session
    if self.settings.style == "chat" then
        self.print(title(session))
        for _, line in ipairs(self:Lines(session)) do
            self.print("  " .. line)
        end
        return
    end
    render(self, session)
end

-- The open session, else the last one, or nil.
function Summary:Latest()
    local castLog = self.castLog
    local session = castLog and castLog:Session()
    if session then
        return session
    end
    local sessions = castLog and castLog.char and castLog.char.sessions
    return sessions and sessions[#sessions] or nil
end

-- /fm summary [window|chat]. Returns a text to print, or nil after showing the summary.
function Summary:Command(rest)
    local style = lower(match(rest or "", "^%s*(%S*)") or "")
    if style ~= "" then
        if not Summary.STYLES[style] then
            return L.SUMMARY_USAGE
        end
        self.settings.style = style
        return L["SUMMARY_STYLE_" .. style]
    end
    local session = self:Latest()
    if not session then
        return L.SUMMARY_NONE
    end
    self:Show(session)
    return nil
end

ns.Commands.Register("summary", L.CMD_SUMMARY, function(rest)
    if not ns.summary then
        ns.Print(L.STATUS_NOT_READY)
        return
    end
    local text = ns.summary:Command(rest)
    if text then
        ns.Print(text)
    end
end)
