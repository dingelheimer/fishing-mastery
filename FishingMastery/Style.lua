-- Pure values: the colors and fonts of the UI drafts (Epic 9) and small text helpers. Every
-- window, tooltip, and table takes its colors from here. No frame or API calls.
local _, ns = ...

local format, floor, type, tostring, abs = string.format, math.floor, type, tostring, math.abs
local L = ns.L

local Style = {}
ns.Style = Style

-- { r, g, b } in 0-1, as SetTextColor and AddDoubleLine take them.
Style.GOLD = { 1, 0.82, 0 } -- labels, headers (GameFontNormal)
Style.WHITE = { 1, 1, 1 } -- values (GameFontHighlight)
Style.GREY = { 0.55, 0.55, 0.55 } -- secondary text, small samples, ranges
Style.GREEN = { 0.12, 1, 0 } -- good, click hints
Style.ORANGE = { 1, 0.5, 0 } -- warnings, risk
Style.RED = { 1, 0.19, 0.19 } -- bad
Style.ADDON = { 0.2, 0.73, 1 } -- the addon's name color (chat prefix, item tooltip)
Style.SEASON = { 0.62, 0.82, 1 } -- season tag
Style.NIGHT = { 0.8, 0.72, 1 } -- night tag

-- Background tints { r, g, b, a } for rows and tags.
Style.STRIPE = { 1, 1, 1, 0.035 } -- even table rows
Style.HOVER = { 1, 0.82, 0, 0.12 } -- the row under the mouse
Style.HEADER = { 0.2, 0.15, 0.08, 0.9 } -- table header bar
Style.TAG_SEASON = { 0.31, 0.63, 1, 0.18 }
Style.TAG_NIGHT = { 0.63, 0.47, 1, 0.2 }

-- Font objects of the client by role.
Style.FONTS = {
    title = "GameFontNormalLarge", -- page and panel headers (gold)
    label = "GameFontNormal", -- labels (gold)
    value = "GameFontHighlight", -- values (white)
    small = "GameFontHighlightSmall", -- table cells
    smallLabel = "GameFontNormalSmall", -- table headers, tags
    secondary = "GameFontDisableSmall", -- legends, notes (grey)
    big = "GameFontHighlightHuge", -- headline numbers
}

-- "ffrrggbb" of a color.
function Style.Hex(color)
    local function byte(v)
        return floor((v or 0) * 255 + 0.5)
    end
    return format("ff%02x%02x%02x", byte(color[1]), byte(color[2]), byte(color[3]))
end

-- text wrapped in a color escape (tooltips and labels only, never copyable text).
function Style.Paint(text, color)
    return "|c" .. Style.Hex(color) .. tostring(text) .. "|r"
end

-- A whole number with thousands separators: 1284 -> "1,284"; other values as given.
function Style.Number(value)
    if type(value) ~= "number" or value ~= floor(value) then
        return value ~= nil and tostring(value) or ""
    end
    local text = tostring(abs(value))
    local sep = L.THOUSANDS
    local out = text:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
    if out:sub(1, #sep) == sep then
        out = out:sub(#sep + 1)
    end
    return (value < 0 and "-" or "") .. out
end

-- "66 % (52 - 78)" with the bracket in grey; without a range only the value.
function Style.Range(value, low, high)
    if low == nil or high == nil then
        return tostring(value)
    end
    return tostring(value) .. " " .. Style.Paint(format(L.RANGE, low, high), Style.GREY)
end

-- An estimate from a small sample: "~1 %".
function Style.Approx(text)
    return "~" .. tostring(text)
end
