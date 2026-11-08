-- Frame helpers shared by the windows: template fallback, saved position, movable frames, and
-- guarded buttons. Adapted from FishingMasteryProbe/Window.lua. Frames are unnamed (no globals).
local _, ns = ...

local pcall, type, ipairs = pcall, type, ipairs

local Frames = {}
ns.Frames = Frames

Frames.TEMPLATE = "BasicFrameTemplateWithInset"
Frames.BUTTON_TEMPLATE = "UIPanelButtonTemplate"

-- Creates a frame with a template, falling back to no template if it does not exist.
function Frames.Create(env, frameType, parent, template)
    local ok, frame = pcall(env.CreateFrame, frameType, nil, parent, template)
    if ok and frame then
        return frame
    end
    return env.CreateFrame(frameType, nil, parent)
end

-- Creates a frame with the first template of the list that exists (name: a global name, only for
-- frames that need one); returns the frame and the template used (nil: none existed).
function Frames.CreateFirst(env, frameType, parent, templates, name)
    for _, template in ipairs(templates) do
        local ok, frame = pcall(env.CreateFrame, frameType, name, parent, template)
        if ok and frame then
            return frame, template
        end
    end
    return env.CreateFrame(frameType, name, parent), nil
end

-- Places the frame at store[key] (FishingMasteryCharDB.ui), else at fallback
-- ({ point, x, y } on UIParent) or in the screen center.
function Frames.RestorePosition(frame, env, store, key, fallback)
    frame:ClearAllPoints()
    local pos = store[key]
    if type(pos) == "table" and type(pos.point) == "string" and type(pos.x) == "number" then
        frame:SetPoint(pos.point, env.UIParent, pos.relativePoint or pos.point, pos.x, pos.y or 0)
    elseif fallback then
        frame:SetPoint(fallback.point, env.UIParent, fallback.point, fallback.x, fallback.y)
    else
        frame:SetPoint("CENTER", env.UIParent, "CENTER", 0, 0)
    end
end

-- Movable and clamped, dragged by handle (default: the frame itself); the position is saved in
-- store[key] on drag stop.
function Frames.MakeMovable(frame, store, key, handle)
    handle = handle or frame
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    handle:SetScript(
        "OnDragStop",
        ns.Guard.Wrap("frame:drag", function()
            frame:StopMovingOrSizing()
            local point, _, relativePoint, x, y = frame:GetPoint(1)
            if type(point) == "string" and type(x) == "number" and type(y) == "number" then
                store[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
            end
        end)
    )
end

-- A button whose click runs through the guard.
function Frames.Button(env, parent, label, width, onClick)
    local button = Frames.Create(env, "Button", parent, Frames.BUTTON_TEMPLATE)
    button:SetSize(width, 22)
    button:SetText(label)
    button:SetScript("OnClick", ns.Guard.Wrap("button:" .. label, onClick))
    return button
end
