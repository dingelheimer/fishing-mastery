-- Look settings (Story 10.4): "Window panels: game / warm" lays the dark warm brown of Draft 1 over
-- the main window's inset and every framed box (the Blizzard frame stays); "HUD background: game
-- tooltip / solid" puts the solid dark of Draft 5 behind the HUD card and the compact line (and
-- the Settings preview). Each tint is a texture inside the frame's border, created once and only
-- shown or hidden when a setting changes. Unnamed, insecure textures only.
local _, ns = ...

local ipairs, type = ipairs, type

local Look = {}
ns.Look = Look

Look.PANELS = { "game", "warm" }
Look.BACKGROUNDS = { "tooltip", "solid" }
Look.WARM_BODY = { 28 / 255, 21 / 255, 16 / 255, 0.92 } -- the window body of Draft 1
Look.WARM_PANEL = { 22 / 255, 16 / 255, 11 / 255, 0.92 } -- a framed box of Draft 1
Look.SOLID = { 17 / 255, 20 / 255, 25 / 255, 0.96 } -- the HUD card of Draft 5
Look.EDGE = 3 -- pixels inside the template's border

Look.panels, Look.background = "warm", "tooltip" -- the defaults (owner's pick, Story 10.4)
local tints, backings = {}, {}

local function texture(frame, color, shown)
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", Look.EDGE, -Look.EDGE)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Look.EDGE, Look.EDGE)
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
    tex:SetShown(shown)
    return tex
end

-- A warm tint inside a window inset or box (color: WARM_BODY or WARM_PANEL).
function Look.Tint(frame, color)
    local tex = texture(frame, color, Look.panels == "warm")
    tints[#tints + 1] = tex
    frame.lookTint = tex
    return tex
end

-- A solid backing inside a HUD view.
function Look.Backing(frame)
    local tex = texture(frame, Look.SOLID, Look.background == "solid")
    backings[#backings + 1] = tex
    frame.lookBacking = tex
    return tex
end

-- Shows or hides every tint ("game" or "warm").
function Look.SetPanels(mode)
    Look.panels = mode
    for _, tex in ipairs(tints) do
        tex:SetShown(mode == "warm")
    end
end

-- Shows or hides every HUD backing ("tooltip" or "solid").
function Look.SetBackground(mode)
    Look.background = mode
    for _, tex in ipairs(backings) do
        tex:SetShown(mode == "solid")
    end
end

-- Both looks from the saved settings (at login, before any frame is built, and on a change).
function Look.Apply(settings)
    if type(settings) ~= "table" then
        return
    end
    Look.SetPanels(ns.Options.Get(settings, "uiPanels"))
    Look.SetBackground(ns.Options.Get(settings, "hudBackground"))
end
