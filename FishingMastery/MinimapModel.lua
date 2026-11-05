-- Pure logic: where the own minimap button sits for an angle (degrees, 0 = right,
-- counterclockwise), on the edge of a round minimap or of the shape GetMinimapShape names (square
-- corners are followed along the edge), and the cursor's angle around the center while dragging.
-- No frame or API calls.
local _, ns = ...

local cos, sin, rad, deg, atan2, sqrt, min, max, type =
    math.cos, math.sin, math.rad, math.deg, math.atan2, math.sqrt, math.min, math.max, type

local MinimapModel = {}
ns.MinimapModel = MinimapModel

MinimapModel.EDGE = 5 -- pixels outside the minimap edge
MinimapModel.CORNER_INSET = 10 -- pull-in of the diagonal on square corners

-- Round corners per shape, by quarter: tr (top right), tl, br, bl. Shapes not listed are round.
local SQUARE = { tr = false, tl = false, br = false, bl = false }
MinimapModel.SHAPES = {
    SQUARE = SQUARE,
    ["CORNER-TOPLEFT"] = { tr = false, tl = true, br = false, bl = false },
    ["CORNER-TOPRIGHT"] = { tr = true, tl = false, br = false, bl = false },
    ["CORNER-BOTTOMLEFT"] = { tr = false, tl = false, br = false, bl = true },
    ["CORNER-BOTTOMRIGHT"] = { tr = false, tl = false, br = true, bl = false },
    ["SIDE-LEFT"] = { tr = false, tl = true, br = false, bl = true },
    ["SIDE-RIGHT"] = { tr = true, tl = false, br = true, bl = false },
    ["SIDE-TOP"] = { tr = true, tl = true, br = false, bl = false },
    ["SIDE-BOTTOM"] = { tr = false, tl = false, br = true, bl = true },
    ["TRICORNER-TOPLEFT"] = { tr = true, tl = true, br = false, bl = true },
    ["TRICORNER-TOPRIGHT"] = { tr = true, tl = true, br = true, bl = false },
    ["TRICORNER-BOTTOMLEFT"] = { tr = false, tl = true, br = true, bl = true },
    ["TRICORNER-BOTTOMRIGHT"] = { tr = true, tl = false, br = true, bl = true },
}

-- The quarter of a direction (x, y).
local function quarter(x, y)
    if y >= 0 then
        return x >= 0 and "tr" or "tl"
    end
    return x >= 0 and "br" or "bl"
end

-- Offset (x, y) of the button center from the minimap center for an angle; width and height are
-- the minimap's; shape is GetMinimapShape's result (nil = round).
function MinimapModel.Offset(angle, width, height, shape)
    local x, y = cos(rad(angle)), sin(rad(angle))
    local w, h = width / 2 + MinimapModel.EDGE, height / 2 + MinimapModel.EDGE
    local corners = type(shape) == "string" and MinimapModel.SHAPES[shape] or nil
    if not corners or corners[quarter(x, y)] then
        return x * w, y * h
    end
    local dw = sqrt(2 * w * w) - MinimapModel.CORNER_INSET
    local dh = sqrt(2 * h * h) - MinimapModel.CORNER_INSET
    return max(-w, min(x * dw, w)), max(-h, min(y * dh, h))
end

-- Angle (0-360) of the point (px, py) around the center (cx, cy).
function MinimapModel.Angle(cx, cy, px, py)
    return deg(atan2(py - cy, px - cx)) % 360
end

-- A saved angle, or the default when it is not a number.
function MinimapModel.Saved(store)
    local entry = type(store) == "table" and store.minimap
    local angle = type(entry) == "table" and entry.angle
    if type(angle) == "number" then
        return angle % 360
    end
    return ns.Options.DEFAULTS.ui.minimapAngle
end
