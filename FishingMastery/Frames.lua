-- Frame helpers shared by the windows: template fallback, saved position, movable frames, and
-- guarded buttons. Adapted from FishingMasteryProbe/Window.lua. Frames are unnamed (no globals).
local _, ns = ...

local pcall, type = pcall, type

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

-- Places the frame at store[key] (FishingMasteryCharDB.ui) or in the screen center.
function Frames.RestorePosition(frame, env, store, key)
    frame:ClearAllPoints()
    local pos = store[key]
    if type(pos) == "table" and type(pos.point) == "string" and type(pos.x) == "number" then
        frame:SetPoint(pos.point, env.UIParent, pos.relativePoint or pos.point, pos.x, pos.y or 0)
    else
        frame:SetPoint("CENTER", env.UIParent, "CENTER", 0, 0)
    end
end

-- Movable and clamped; the position is saved in store[key] on drag stop.
function Frames.MakeMovable(frame, store, key)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript(
        "OnDragStop",
        ns.Guard.Wrap("frame:drag", function(self)
            self:StopMovingOrSizing()
            local point, _, relativePoint, x, y = self:GetPoint(1)
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
