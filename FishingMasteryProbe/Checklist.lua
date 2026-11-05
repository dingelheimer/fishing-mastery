-- Checklist overview next to the guided test run window: every step with open/done/skipped.
local _, ns = ...

local ipairs, setmetatable = ipairs, setmetatable
local L = ns.L

local Checklist = {}
Checklist.__index = Checklist
ns.Checklist = Checklist

Checklist.WIDTH = 380
Checklist.LINE_HEIGHT = 18
Checklist.COLORS = {
    open = { 1, 1, 1 },
    done = { 0.3, 1, 0.3 },
    skipped = { 0.6, 0.6, 0.6 },
    current = { 1, 0.82, 0 },
}

-- parent: the main window frame. Hidden until toggled.
function Checklist.Create(env, parent, progress)
    local count = #progress.steps.list
    local frame = ns.Window.CreateFrame(env, "Frame", parent, ns.Window.TEMPLATE)
    frame:SetSize(Checklist.WIDTH, 44 + count * Checklist.LINE_HEIGHT)
    frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText(L.CHECKLIST_TITLE)
    local lines = {}
    for i = 1, count do
        local line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32 - (i - 1) * Checklist.LINE_HEIGHT)
        line:SetWidth(Checklist.WIDTH - 28)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        lines[i] = line
    end
    local self = setmetatable({ frame = frame, lines = lines, progress = progress }, Checklist)
    frame:SetScript(
        "OnShow",
        ns.Guard.Wrap("checklist:show", function()
            self:Refresh()
        end)
    )
    frame:Hide()
    return self
end

function Checklist:Refresh()
    if not self.frame:IsShown() then
        return
    end
    for i, item in ipairs(ns.View.Checklist(self.progress)) do
        local line = self.lines[i]
        if line then
            local color = Checklist.COLORS[item.current and "current" or item.status]
            line:SetText(item.text)
            line:SetTextColor(color[1], color[2], color[3])
        end
    end
end

function Checklist:Toggle()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end
