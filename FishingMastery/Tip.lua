-- Tooltip builder in the Blizzard style (Epic 9, Draft 6): a title, gold labels with white values,
-- empty lines between groups, colors only for meaning, green hints last, and explanations only
-- while Shift is held. Tip.Open draws through a callback and redraws when Shift changes while the
-- owner still holds the tooltip. Uses GameTooltip; one event frame for the modifier state.
local _, ns = ...

local setmetatable, ipairs, type, tostring = setmetatable, ipairs, type, tostring
local L, Style = ns.L, ns.Style

local Tip = {}
Tip.__index = Tip
ns.Tip = Tip

Tip.ANCHOR = "ANCHOR_RIGHT"
Tip.SHIFT_KEYS = { LSHIFT = true, RSHIFT = true }

local current -- { env, owner, anchor, draw } of the shown tooltip
local watcher -- the MODIFIER_STATE_CHANGED frame

local function shiftDown(env)
    local fn = env.IsShiftKeyDown
    return type(fn) == "function" and fn() and true or false
end

local function render(open)
    local tooltip = open.env.GameTooltip
    tooltip:SetOwner(open.owner, open.anchor or Tip.ANCHOR)
    local tip = setmetatable({ tooltip = tooltip, shift = shiftDown(open.env), lines = 0 }, Tip)
    open.draw(tip)
    tooltip:Show()
end

local function owned(open)
    local tooltip = open.env.GameTooltip
    if type(tooltip.IsOwned) == "function" then
        return tooltip:IsOwned(open.owner)
    end
    return tooltip.owner == open.owner
end

local function watch(env)
    if watcher then
        return
    end
    watcher = env.CreateFrame("Frame")
    watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    watcher:SetScript(
        "OnEvent",
        ns.Guard.Wrap("tip:shift", function(_, _, key)
            if not (current and Tip.SHIFT_KEYS[key]) then
                return
            end
            if owned(current) then
                render(current)
            else
                current = nil
            end
        end)
    )
end

-- Shows the tooltip of owner drawn by draw(tip); redrawn on Shift while owner holds it.
function Tip.Open(env, owner, draw, anchor)
    if not env.GameTooltip then
        return
    end
    current = { env = env, owner = owner, anchor = anchor, draw = draw }
    watch(env)
    render(current)
end

-- Hides the tooltip of owner (OnLeave).
function Tip.Close(env, owner)
    if current and current.owner == owner then
        current = nil
    end
    if env.GameTooltip then
        env.GameTooltip:Hide()
    end
end

local function add(self, text, color, wrap)
    color = color or Style.WHITE
    if self.lines == 0 then
        self.tooltip:SetText(text, color[1], color[2], color[3])
    else
        self.tooltip:AddLine(text, color[1], color[2], color[3], wrap and true or false)
    end
    self.lines = self.lines + 1
end

-- The first line: what the tooltip is about (white unless a color is given).
function Tip:Title(text, color)
    add(self, text, color or Style.WHITE)
    return self
end

-- A gold label on the left, the value on the right (white unless a color is given).
function Tip:Pair(label, value, color)
    color = color or Style.WHITE
    local gold = Style.GOLD
    if self.lines == 0 then -- no title yet: a tooltip cannot start with a double line
        add(self, label .. ": " .. tostring(value), gold)
        return self
    end
    self.tooltip:AddDoubleLine(
        label,
        value,
        gold[1],
        gold[2],
        gold[3],
        color[1],
        color[2],
        color[3]
    )
    self.lines = self.lines + 1
    return self
end

-- A gold group header.
function Tip:Header(text)
    add(self, text, Style.GOLD)
    return self
end

-- One short line (white unless a color is given); never wrapped.
function Tip:Line(text, color)
    add(self, text, color)
    return self
end

-- An empty line between groups (none at the top).
function Tip:Gap()
    if self.lines > 0 then
        add(self, " ")
    end
    return self
end

-- A green click hint.
function Tip:Hint(text)
    add(self, text, Style.GREEN)
    return self
end

-- Explanations: wrapped grey lines while Shift is held, else the grey "Hold Shift" line.
function Tip:Details(lines)
    self:Gap()
    if not self.shift then
        add(self, L.TIP_SHIFT, Style.GREY)
        return self
    end
    for _, line in ipairs(lines) do
        add(self, line, Style.GREY, true)
    end
    return self
end

-- A longer white sentence, wrapped (white unless a color is given).
function Tip:Text(text, color)
    add(self, text, color, true)
    return self
end

-- Shows plain lines (charts, older tables): the first as the title, the others wrapped below.
function Tip.Lines(env, owner, lines, anchor)
    Tip.Open(env, owner, function(tip)
        tip:Title(lines[1] or "")
        for i = 2, #lines do
            tip:Text(lines[i])
        end
    end, anchor)
end
