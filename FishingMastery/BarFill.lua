-- Bar fills in the draft palette (Story 10.1): a color texture with a slight vertical gradient,
-- darker at the bottom, through Texture:SetGradient with CreateColor objects (the Mainline
-- signature; checked on live with /fm dev ui). A flat fill when either is missing or the call
-- fails. Insecure textures only.
local _, ns = ...

local type, pcall = type, pcall
local Style = ns.Style

local BarFill = {}
ns.BarFill = BarFill

BarFill.SHADE = 0.75 -- the bottom color is the bar color times this

-- A flat color; clears the per-corner tint a gradient left on a reused texture.
function BarFill.Flat(texture, color)
    if type(texture.SetVertexColor) == "function" then
        texture:SetVertexColor(1, 1, 1, 1)
    end
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- Paints texture in color ({ r, g, b[, a] }); returns "gradient" or "flat".
function BarFill.Paint(env, texture, color)
    local a = color[4] or 1
    local create = env.CreateColor
    if type(create) == "function" and type(texture.SetGradient) == "function" then
        local low = Style.Shade(color, BarFill.SHADE)
        local ok = pcall(function()
            texture:SetColorTexture(1, 1, 1, 1)
            texture:SetGradient(
                "VERTICAL",
                create(low[1], low[2], low[3], a),
                create(color[1], color[2], color[3], a)
            )
        end)
        if ok then
            return "gradient"
        end
    end
    BarFill.Flat(texture, color)
    return "flat"
end
