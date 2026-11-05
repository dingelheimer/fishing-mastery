-- A small fake of the WoW frame API: only the methods the probe window uses exist, so a call to
-- a method the window should not need fails the test.
local M = {}

local Region = {}
Region.__index = Region

function Region:SetPoint(point, relativeTo, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
end
function Region:ClearAllPoints()
    self.points = {}
end
function Region:GetPoint(index)
    local p = self.points[index or 1]
    if p then
        return p[1], p[2], p[3], p[4], p[5]
    end
end
function Region:SetWidth(width)
    self.width = width
end
function Region:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end
function Region:Show()
    local was = self.shown
    self.shown = true
    if not was and self.scripts and self.scripts.OnShow then
        self.scripts.OnShow(self)
    end
end
function Region:Hide()
    local was = self.shown
    self.shown = false
    if was and self.scripts and self.scripts.OnHide then
        self.scripts.OnHide(self)
    end
end
function Region:IsShown()
    return self.shown
end

local FontString = setmetatable({}, { __index = Region })
FontString.__index = FontString

function FontString:SetText(text)
    self.text = text
end
function FontString:GetText()
    return self.text
end
function FontString:SetJustifyH(value)
    self.justifyH = value
end
function FontString:SetWordWrap(value)
    self.wordWrap = value
end
function FontString:SetTextColor(r, g, b)
    self.color = { r, g, b }
end

local Texture = setmetatable({}, { __index = Region })
Texture.__index = Texture

function Texture:SetAllPoints(relativeTo)
    self.allPoints = relativeTo
end
function Texture:SetColorTexture(r, g, b, a)
    self.color = { r, g, b, a }
end
function Texture:SetTexture(texture)
    self.texture = texture
end
function Texture:SetSize(width, height)
    self.width, self.height = width, height
end

-- Line (Frame:CreateLine): records its end points, thickness, and color.
local Line = setmetatable({}, { __index = Region })
Line.__index = Line

function Line:SetStartPoint(point, relativeTo, x, y)
    self.start = { point, relativeTo, x, y }
end
function Line:SetEndPoint(point, relativeTo, x, y)
    self.finish = { point, relativeTo, x, y }
end
function Line:SetThickness(thickness)
    self.thickness = thickness
end
function Line:SetColorTexture(r, g, b, a)
    self.color = { r, g, b, a }
end

local Frame = setmetatable({}, { __index = Region })
Frame.__index = Frame

function Frame:SetScale(scale)
    self.scale = scale
end
function Frame:GetScale()
    return self.scale or 1
end
function Frame:CreateTexture(_, layer)
    local texture = setmetatable({ points = {}, shown = true, layer = layer }, Texture)
    self.textures = self.textures or {}
    self.textures[#self.textures + 1] = texture
    return texture
end

function Frame:SetSize(width, height)
    self.width, self.height = width, height
end
function Frame:CreateLine(_, layer)
    local line = setmetatable({ points = {}, shown = true, layer = layer }, Line)
    self.lines = self.lines or {}
    self.lines[#self.lines + 1] = line
    return line
end
function Frame:SetScript(name, fn)
    self.scripts[name] = fn
end
function Frame:GetScript(name)
    return self.scripts[name]
end
function Frame:SetMovable(value)
    self.movable = value
end
function Frame:EnableMouse(value)
    self.mouse = value
end
function Frame:SetClampedToScreen(value)
    self.clamped = value
end
function Frame:RegisterForDrag(button)
    self.dragButton = button
end
function Frame:SetFrameStrata(strata)
    self.strata = strata
end
function Frame:SetToplevel(value)
    self.toplevel = value
end
-- Event methods for Core's event frames (used by the boot spec).
function Frame:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
    return true
end
function Frame:UnregisterEvent(event)
    if self.events then
        self.events[event] = nil
    end
end
-- Test helper: delivers an event the way the client calls OnEvent.
function Frame:Fire(event, ...)
    if self.events and self.events[event] and self.scripts.OnEvent then
        self.scripts.OnEvent(self, event, ...)
    end
end
function Frame:StartMoving()
    self.moving = true
end
function Frame:StopMovingOrSizing()
    self.moving = false
end
function Frame:CreateFontString(_, layer, font)
    local fs = setmetatable({ points = {}, shown = true, layer = layer, font = font }, FontString)
    self.fontStrings[#self.fontStrings + 1] = fs
    return fs
end
-- Button and edit box methods (only valid on "Button" and "EditBox" frames).
local TEXT_FRAMES = { Button = true, EditBox = true }
function Frame:SetText(text)
    assert(TEXT_FRAMES[self.frameType], "SetText on a frame without text")
    self.text = text
    if self.frameType == "EditBox" and self.scripts.OnTextChanged then
        self.scripts.OnTextChanged(self, false)
    end
end
function Frame:GetText()
    return self.text
end
function Frame:SetEnabled(value)
    self.enabled = value and true or false
end
function Frame:IsEnabled()
    return self.enabled
end
function Frame:SetID(id)
    self.id = id
end
function Frame:GetID()
    return self.id
end
-- Test helper: a click as the player would do it (ignored when hidden or disabled).
function Frame:Click()
    if self.shown and self.enabled and self.scripts.OnClick then
        self.scripts.OnClick(self, "LeftButton")
        return true
    end
    return false
end

-- Edit box methods (only valid on "EditBox" frames).
local function editBox(self, method)
    assert(self.frameType == "EditBox", method .. " on a non-edit-box frame")
end
function Frame:SetMultiLine(value)
    editBox(self, "SetMultiLine")
    self.multiLine = value
end
function Frame:SetAutoFocus(value)
    editBox(self, "SetAutoFocus")
    self.autoFocus = value
end
function Frame:SetMaxLetters(value)
    editBox(self, "SetMaxLetters")
    self.maxLetters = value
end
function Frame:SetFontObject(font)
    editBox(self, "SetFontObject")
    self.fontObject = font
end
function Frame:SetCursorPosition(position)
    editBox(self, "SetCursorPosition")
    self.cursor = position
end
function Frame:SetFocus()
    editBox(self, "SetFocus")
    self.focused = true
end
function Frame:ClearFocus()
    editBox(self, "ClearFocus")
    self.focused = false
end
function Frame:HighlightText()
    editBox(self, "HighlightText")
    self.highlighted = true
end
-- Test helper: the player types or pastes into the edit box. Like the client, the edit box
-- stores a typed "|" as "||" (an escaped pipe).
function Frame:Type(text)
    editBox(self, "Type")
    self.text = (text:gsub("|", "||"))
    if self.scripts.OnTextChanged then
        self.scripts.OnTextChanged(self, true)
    end
end
-- Scroll frame method (only valid on "ScrollFrame" frames).
function Frame:SetScrollChild(child)
    assert(self.frameType == "ScrollFrame", "SetScrollChild on a non-scroll frame")
    self.scrollChild = child
end

-- Secure button methods (only valid on "Button" frames).
function Frame:SetAttribute(key, value)
    assert(self.frameType == "Button", "SetAttribute on a non-button frame")
    self.attributes = self.attributes or {}
    self.attributes[key] = value
end
function Frame:GetAttribute(key)
    return self.attributes and self.attributes[key]
end
function Frame:RegisterForClicks(...)
    self.clicks = { ... }
end
-- Test helper: a key press on a secure button, as the binding would deliver it.
function Frame:PressKey(down)
    if self.scripts.PostClick then
        self.scripts.PostClick(self, "LeftButton", down)
    end
end

-- The only frame name the probe may create (SetOverrideBindingClick needs a name).
M.ALLOWED_NAMES = { FishingMasteryProbeTestButton = true }

-- Returns an env with CreateFrame and UIParent. opts.missingTemplates: { [name] = true }.
function M.new(opts)
    opts = opts or {}
    local env = { frames = {}, sounds = {} }
    env.UIParent =
        setmetatable({ points = {}, scripts = {}, fontStrings = {}, shown = true }, Frame)
    function env.CreateFrame(frameType, name, parent, template)
        assert(name == nil or M.ALLOWED_NAMES[name], "named frames create globals")
        if template and opts.missingTemplates and opts.missingTemplates[template] then
            error("Couldn't find inherited node: " .. template)
        end
        local frame = setmetatable({
            frameType = frameType,
            parent = parent,
            template = template,
            points = {},
            scripts = {},
            fontStrings = {},
            shown = true,
            enabled = true,
            name = name,
        }, Frame)
        env.frames[#env.frames + 1] = frame
        if name then
            env[name] = frame
        end
        return frame
    end
    -- GameTooltip: records the lines of the last tooltip.
    env.GameTooltip = {
        lines = {},
        SetOwner = function(tip, owner, anchor)
            tip.owner, tip.anchor, tip.lines = owner, anchor, {}
        end,
        SetText = function(tip, text)
            tip.lines = { text }
        end,
        AddLine = function(tip, text)
            tip.lines[#tip.lines + 1] = text
        end,
        Show = function(tip)
            tip.shown = true
        end,
        Hide = function(tip)
            tip.shown = false
        end,
    }
    return env
end

-- Finds the frames of a type, in creation order.
function M.frames(env, frameType)
    local list = {}
    for _, frame in ipairs(env.frames) do
        if frame.frameType == frameType then
            list[#list + 1] = frame
        end
    end
    return list
end

-- Finds a button by its label.
function M.button(env, label)
    for _, frame in ipairs(env.frames) do
        if frame.frameType == "Button" and frame.text == label then
            return frame
        end
    end
    error("no button " .. label)
end

-- The shared frame prototype: specs may add a method for one test and remove it afterwards.
M.Frame = Frame

return M
