-- Session summary: shown when a session ends after 15 minutes without a cast, and on
-- /fm summary for the current or last session. A small window (default) or a block in the own
-- chat frame (setting). Item data comes from the item cache; names that load later refresh the
-- open window. Texts come from SummaryModel.lua; nothing is sent to other chat channels.
local _, ns = ...

local setmetatable, type, ipairs, pairs, concat, lower, match =
    setmetatable, type, ipairs, pairs, table.concat, string.lower, string.match
local L, Frames, SummaryModel, Context = ns.L, ns.Frames, ns.SummaryModel, ns.Context

local Summary = {}
Summary.__index = Summary
ns.Summary = Summary

-- Account-wide summary settings (FishingMasteryDB.settings.summary).
Summary.DEFAULTS = ns.Options.DEFAULTS.summary
Summary.STYLES = { window = true, chat = true }
Summary.POSITION_KEY = "summary"
Summary.WIDTH, Summary.LINE = 380, 15

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

-- Summary lines of a session; onLoad runs when an uncached item's data arrives.
function Summary:Lines(session, onLoad)
    local castLog = self.castLog
    local items = {}
    for id in pairs(type(session.items) == "table" and session.items or {}) do
        items[id] = castLog.items:Info(id, onLoad)
    end
    local model = SummaryModel.Build({
        session = session,
        now = self.serverTime(),
        totals = castLog.char and castLog.char.totals,
        items = items,
        thresholds = self.thresholds,
    })
    self.model = model
    return SummaryModel.Lines(model, model.compare and Context.MapName(self.env, model.compare.map))
end

local function build(self)
    local env = self.env
    local frame = Frames.Create(env, "Frame", env.UIParent, Frames.TEMPLATE)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    Frames.RestorePosition(frame, env, self.store, Summary.POSITION_KEY)
    Frames.MakeMovable(frame, self.store, Summary.POSITION_KEY)
    self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.title:SetPoint("TOP", frame, "TOP", 0, -6)
    self.body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    self.body:SetWidth(Summary.WIDTH - 32)
    self.body:SetJustifyH("LEFT")
    self.closeButton = Frames.Button(env, frame, L.BUTTON_CLOSE, 80, function()
        frame:Hide()
    end)
    self.closeButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    self.frame = frame
    return frame
end

local function title(session)
    return session.ended and L.SUMMARY_TITLE or L.SUMMARY_TITLE_OPEN
end

local function render(self, session)
    local lines = self:Lines(session, function()
        if self.shown == session and self.frame and self.frame:IsShown() then
            render(self, session)
        end
    end)
    local frame = self.frame or build(self)
    self.title:SetText(title(session))
    self.body:SetText(concat(lines, "\n"))
    frame:SetSize(Summary.WIDTH, 80 + #lines * Summary.LINE)
    frame:Show()
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
