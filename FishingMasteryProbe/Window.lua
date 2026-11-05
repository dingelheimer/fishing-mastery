-- Guided test run window. Renders View.Step and forwards button clicks to Progress; it never
-- triggers game actions. Frames come from an injected environment (_G in game).
local _, ns = ...

local type, pcall, ipairs, pairs, setmetatable = type, pcall, ipairs, pairs, setmetatable
local L = ns.L

local Window = {}
Window.__index = Window
ns.Window = Window

Window.WIDTH = 440
Window.HEIGHT = 500
Window.PADDING = 16
Window.TEMPLATE = "BasicFrameTemplateWithInset"
Window.BUTTON_TEMPLATE = "UIPanelButtonTemplate"
Window.SOUND = "READY_CHECK"

-- Text lines from top to bottom: { field, font object }.
Window.LINES = {
    { "header", "GameFontNormalSmall" },
    { "title", "GameFontNormalLarge" },
    { "instruction", "GameFontHighlight" },
    { "counter", "GameFontNormal" },
    { "state", "GameFontHighlightSmall" },
    { "extra", "GameFontHighlightSmall" },
    { "prereq", "GameFontHighlightSmall" },
    { "why", "GameFontHighlightSmall" },
    { "questions", "GameFontDisableSmall" },
}

-- Creates a frame with a template, falling back to no template if it does not exist.
function Window.CreateFrame(env, frameType, parent, template)
    local ok, frame = pcall(env.CreateFrame, frameType, nil, parent, template)
    if ok and frame then
        return frame
    end
    return env.CreateFrame(frameType, nil, parent)
end

-- Plays the step-advance sound if the sound API and kit exist.
function Window.PlayCue(env)
    local kit = env.SOUNDKIT
    local id = type(kit) == "table" and kit[Window.SOUND]
    if id and type(env.PlaySound) == "function" then
        pcall(env.PlaySound, id)
    end
end

-- Saves the frame position in store[key] (default "window").
local function savePosition(frame, store, key)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if type(point) == "string" and type(x) == "number" and type(y) == "number" then
        store[key or "window"] = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
end

function Window.RestorePosition(frame, env, store, key)
    frame:ClearAllPoints()
    local pos = store[key or "window"]
    if type(pos) == "table" and type(pos.point) == "string" and type(pos.x) == "number" then
        frame:SetPoint(pos.point, env.UIParent, pos.relativePoint or pos.point, pos.x, pos.y or 0)
    else
        frame:SetPoint("CENTER", env.UIParent, "CENTER", 0, 0)
    end
end

-- Movable and clamped; the position is saved in store[key] on drag stop.
function Window.MakeMovable(frame, store, key)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript(
        "OnDragStop",
        ns.Guard.Wrap("window:drag", function(self)
            self:StopMovingOrSizing()
            savePosition(self, store, key)
        end)
    )
end

local function text(frame, font, width)
    local line = frame:CreateFontString(nil, "OVERLAY", font)
    line:SetWidth(width)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(true)
    return line
end

local function button(self, parent, label, width, onClick)
    local b = Window.CreateFrame(self.env, "Button", parent, Window.BUTTON_TEMPLATE)
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", ns.Guard.Wrap("window:click", onClick))
    return b
end

-- Lays out a row of buttons from the bottom left of the window (y: offset from the bottom).
local function row(frame, buttons, y)
    local previous
    for _, b in ipairs(buttons) do
        if previous then
            b:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", Window.PADDING, y or 14)
        end
        previous = b
    end
end

local function buildButtons(self)
    local frame, progress = self.frame, self.progress
    local b = {}
    b.back = button(self, frame, L.BUTTON_BACK, 70, function()
        progress:Back()
    end)
    b.start = button(self, frame, L.BUTTON_START, 80, function()
        progress:Start()
    end)
    b.done = button(self, frame, L.BUTTON_DONE, 80, function()
        progress:Done(false)
    end)
    b.skip = button(self, frame, L.BUTTON_SKIP, 70, function()
        if progress:Current().optional then
            progress:Skip("optional")
        else
            self:ShowSkipReasons(true)
        end
    end)
    b.checklist = button(self, frame, L.BUTTON_CHECKLIST, 90, function()
        self.checklist:Toggle()
    end)
    row(frame, { b.back, b.start, b.done, b.skip, b.checklist })
    self.buttons = b

    local reasons = {}
    for i, reason in ipairs({ "no_item", "no_location", "other" }) do
        reasons[i] = button(self, frame, L["SKIP_" .. reason], 96, function()
            self:ShowSkipReasons(false)
            progress:Skip(reason)
        end)
    end
    reasons[#reasons + 1] = button(self, frame, L.BUTTON_CANCEL, 70, function()
        self:ShowSkipReasons(false)
    end)
    row(frame, reasons)
    self.reasonButtons = reasons

    -- S14 helper tests, one row above the main buttons (where the skip question would be).
    local helpers = {
        button(self, frame, L.BUTTON_ENABLE_KEY, 130, function()
            self:Helper("EnableKey")
        end),
        button(self, frame, L.BUTTON_SEND_WHISPER, 130, function()
            self:Helper("SendWhisper")
        end),
    }
    row(frame, helpers, 44)
    self.helperButtons = helpers
    local question = text(frame, "GameFontNormal", Window.WIDTH - 2 * Window.PADDING)
    question:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", Window.PADDING, 44)
    question:SetText(L.SKIP_QUESTION)
    self.skipQuestion = question
end

-- deps: { progress, store = db.progress, info() -> { snapshot, events, helpers },
-- helpers() -> the Helpers object or nil before login }.
function Window.Create(env, deps)
    local self = setmetatable({
        env = env,
        progress = deps.progress,
        store = deps.store,
        info = deps.info,
        helpers = deps.helpers,
        lines = {},
        choosingReason = false,
    }, Window)
    local frame = Window.CreateFrame(env, "Frame", env.UIParent, Window.TEMPLATE)
    self.frame = frame
    frame:SetSize(Window.WIDTH, Window.HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    Window.RestorePosition(frame, env, self.store)
    Window.MakeMovable(frame, self.store)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText(L.WINDOW_TITLE)

    local width, previous = Window.WIDTH - 2 * Window.PADDING, nil
    for _, spec in ipairs(Window.LINES) do
        local line = text(frame, spec[2], width)
        if previous then
            line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
        else
            line:SetPoint("TOPLEFT", frame, "TOPLEFT", Window.PADDING, -36)
        end
        self.lines[spec[1]] = line
        previous = line
    end

    buildButtons(self)
    self.checklist = ns.Checklist.Create(env, frame, self.progress)
    frame:SetScript(
        "OnShow",
        ns.Guard.Wrap("window:show", function()
            self:Refresh()
        end)
    )
    frame:Hide()
    self:ShowSkipReasons(false)
    return self
end

function Window:ShowSkipReasons(show)
    self.choosingReason = show
    for _, b in ipairs(self.reasonButtons) do
        b:SetShown(show)
    end
    self.skipQuestion:SetShown(show)
    self:Refresh()
end

-- Redraws the current step; does nothing while the window is hidden.
function Window:Refresh()
    if not self.frame:IsShown() then
        return
    end
    local view = ns.View.Step(self.progress, self.info and self.info() or nil)
    for field, line in pairs(self.lines) do
        line:SetText(view[field] or "")
    end
    local b, choosing = self.buttons, self.choosingReason
    b.back:SetShown(not choosing)
    b.back:SetEnabled(view.buttons.back)
    b.start:SetShown(not choosing and view.buttons.start)
    b.start:SetEnabled(view.buttons.startEnabled)
    b.done:SetShown(not choosing)
    b.skip:SetShown(not choosing)
    b.checklist:SetShown(not choosing)
    for _, helper in ipairs(self.helperButtons) do
        helper:SetShown(not choosing and view.buttons.helpers)
        helper:SetEnabled(view.buttons.helpersEnabled)
    end
    self.checklist:Refresh()
end

-- Runs a helper test (EnableKey / SendWhisper) and redraws its state.
function Window:Helper(method)
    local helpers = self.helpers and self.helpers()
    if helpers then
        helpers[method](helpers)
    end
    self:Refresh()
end

function Window:Show()
    self.frame:Show()
end

function Window:Toggle()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end
