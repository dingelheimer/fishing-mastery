-- Bar palette of Draft 1 (Story 10.1): BarFill paints a vertical gradient through CreateColor and
-- SetGradient or falls back to a flat fill, and the Overview and the charts take the bar colors
-- (gold, orange getaway charts, grey small samples, a soft white range whisker).
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")

describe("FishingMastery bar palette", function()
    local ns, env

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleUI.lua",
            "Guard.lua",
            "Style.lua",
            "Tip.lua",
            "BarFill.lua",
            "HudModel.lua",
            "ChartModel.lua",
            "OverviewModel.lua",
            "BarChart.lua",
        }, nil, "FishingMastery")
        env = fakeui.new()
    end)

    local function near(expected, actual)
        assert.is_true(math.abs(expected - actual) < 1e-9, tostring(actual))
    end

    it("has the draft's bar colors next to the unchanged text colors", function()
        local S = ns.Style
        local function rgb(c)
            return { math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), c[3] * 255 }
        end
        assert.are.same({ 81, 197, 81 }, rgb(S.BAR_GREEN))
        assert.are.same({ 240, 202, 92 }, rgb(S.BAR_GOLD))
        assert.are.same({ 225, 129, 60 }, rgb(S.BAR_ORANGE))
        assert.are.same({ 1, 0.82, 0 }, S.GOLD)
        local O = ns.OverviewModel.OUTCOMES
        assert.are.same(
            { S.BAR_GREEN, S.BAR_ORANGE, S.BAR_GOLD, S.BAR_GOLD },
            { O[1].color, O[2].color, O[3].color, O[4].color }
        )
    end)

    it("paints a gradient, darker at the bottom, when the client has it", function()
        local tex = env.CreateFrame("Frame"):CreateTexture()
        assert.are.equal("gradient", ns.BarFill.Paint(env, tex, ns.Style.BAR_GOLD))
        assert.are.same({ 1, 1, 1, 1 }, tex.color)
        local orientation, low, high = tex.gradient[1], tex.gradient[2], tex.gradient[3]
        assert.are.equal("VERTICAL", orientation)
        near(ns.Style.BAR_GOLD[1], high.r)
        near(ns.Style.BAR_GOLD[3] * ns.BarFill.SHADE, low.b)
        assert.are.equal(1, low.a)
    end)

    it("falls back to a flat fill and clears an old gradient", function()
        local tex = env.CreateFrame("Frame"):CreateTexture()
        ns.BarFill.Paint(env, tex, ns.Style.BAR_GOLD)
        env.CreateColor = nil -- a client without color objects
        assert.are.equal("flat", ns.BarFill.Paint(env, tex, ns.Style.BAR_ORANGE))
        assert.is_nil(tex.gradient)
        assert.are.same({ 1, 1, 1, 1 }, tex.vertex)
        local c = ns.Style.BAR_ORANGE
        assert.are.same({ c[1], c[2], c[3], 1 }, tex.color)

        env.CreateColor = function()
            return {}
        end
        tex.SetGradient = function()
            error("bad color type") -- a different signature on the client
        end
        assert.are.equal("flat", ns.BarFill.Paint(env, tex, ns.Style.BAR_GREEN))
        assert.are.equal(ns.Style.BAR_GREEN[1], tex.color[1])
    end)

    it("colors chart bars gold, getaway charts orange, small samples grey", function()
        local chart = ns.BarChart.Create(env, env.CreateFrame("Frame"), 400, 200)
        local function bars(model)
            chart:Draw("Chart", model)
            local out = {}
            for _, tex in ipairs(chart.textures.list) do
                if tex:IsShown() and tex.gradient then
                    out[#out + 1] = tex.gradient[3]
                end
            end
            return out
        end
        local model = ns.ChartModel.Build({
            { label = "1", value = 4, text = "4" },
            { label = "2", value = 2, text = "2", grey = true },
        }, false)
        local drawn = bars(model)
        assert.are.equal(2, #drawn)
        near(ns.Style.BAR_GOLD[1], drawn[1].r)
        near(ns.Style.BAR_GREY[1], drawn[2].r)
        model.kind = "getaway"
        drawn = bars(model)
        near(ns.Style.BAR_ORANGE[2], drawn[1].g)

        -- Range whiskers are flat soft white; pooled textures lose the bar's gradient.
        local ranged = ns.ChartModel.Build({
            { label = "1", value = 0.4, low = 0.3, high = 0.5, text = "40 %" },
        }, true)
        chart:Draw("Ranges", ranged)
        local whiskers = 0
        for _, tex in ipairs(chart.textures.list) do
            if tex:IsShown() and tex.color and tex.color[4] == 0.6 then
                whiskers = whiskers + 1
                assert.is_nil(tex.gradient)
            end
        end
        assert.are.equal(3, whiskers)
    end)
end)
