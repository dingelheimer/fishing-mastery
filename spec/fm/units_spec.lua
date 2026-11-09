-- Units, spacing, and HUD dividers (Story 10.2): the active time as "4 h 44 min" with small units,
-- number and unit groups centered, the Overview legends right under their rows, and the HUD card's
-- "%" unit, its second divider, and the green tick where getaways stop.
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")

describe("FishingMastery units and spacing", function()
    it("writes the active time with small units, minutes only under an hour", function()
        local ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleUI.lua",
            "Style.lua",
            "OverviewModel.lua",
        }, nil, "FishingMastery")
        local function parts(seconds)
            local n = ns.OverviewModel.Active(seconds, 35)
            return { n.value, n.unit, n.value2, n.unit2 }
        end
        assert.are.same({ "4", "h", "44", "min" }, parts(4 * 3600 + 44 * 60 + 30))
        assert.are.same({ "1", "h", "05", "min" }, parts(3900))
        assert.are.same({ "12", "min" }, parts(12 * 60))
        assert.are.equal("in 35 sessions", ns.OverviewModel.Active(60, 35).sub)
    end)

    describe("Overview page", function()
        local w

        before_each(function()
            w = fmboot.new()
            w.boot(nil, nil)
            w.fire("PLAYER_ENTERING_WORLD", true, false)
            statsui.stub(w)
            w.catch(5000, 9)
            w.catch(5020, 12)
            _G.SlashCmdList.FM("stats")
        end)

        after_each(function()
            w.cleanup()
            statsui.cleanup()
        end)

        it("puts the legends right under the rows and centers number groups", function()
            local page, P = w.ns.stats.overview, w.ns.OverviewPage
            local _, _, _, _, y = page.outcomeLegend:GetPoint()
            assert.are.equal(P.ROW_TOP - #page.outcomeRows * P.ROW - P.LEGEND_GAP, y)
            _, _, _, _, y = page.topHint:GetPoint()
            assert.are.equal(P.ROW_TOP - #page.topRows * P.ROW - P.LEGEND_GAP, y)
            -- A minute of active time: the number moves left by half of its unit.
            local active = page.numbers[4]
            assert.truthy(active.value:GetText():find("^%d+$"))
            assert.are.same({ "min", "" }, { active.unit:GetText(), active.value2:GetText() })
            local _, _, _, x = active.value:GetPoint()
            assert.are.equal(-(P.UNIT_GAP + active.unit:GetStringWidth()) / 2, x)
            -- A count without a unit stays centered.
            _, _, _, x = page.numbers[1].value:GetPoint()
            assert.are.equal(0, x)
            assert.are.equal(0, w.ns.Guard.errors)
        end)
    end)

    describe("HUD card", function()
        local ns, env, card

        before_each(function()
            ns = addon.load({
                "Locale.lua",
                "LocaleStats.lua",
                "LocaleUI.lua",
                "Guard.lua",
                "Style.lua",
                "Tip.lua",
                "Frames.lua",
                "Look.lua",
                "Controls.lua",
                "HudCard.lua",
            }, nil, "FishingMastery")
            env = fakeui.new()
            card = ns.HudCard.Create(env, env.UIParent)
        end)

        local function model(extra)
            local m = {
                zone = "Stranglethorn Vale",
                risk = { text = "18 % get away", kind = "risk" },
                bar = { value = 151, max = 225, text = "Fishing 151 / 225", mark = 176 / 225 },
                lure = { text = "Lure +25", timer = "7:42" },
                numbers = {
                    { value = "23" },
                    { value = "66", unit = "%" },
                    { value = "71" },
                },
                compact = "line",
            }
            for k, v in pairs(extra or {}) do
                m[k] = v
            end
            return m
        end

        it("draws the success unit small and grey next to the centered number", function()
            ns.HudCard.Draw(card, model(), "card")
            local success = card.numbers[2]
            assert.are.equal("%", success.unit:GetText())
            assert.are.same(ns.Style.GREY, success.unit.color)
            assert.are.equal("", card.numbers[1].unit:GetText())
            local _, _, _, x = success.value:GetPoint()
            local column = (ns.HudCard.WIDTH - 2 * ns.HudCard.PAD) / 3
            local center = ns.HudCard.PAD + 1.5 * column - ns.HudCard.WIDTH / 2
            local unit = success.unit:GetStringWidth() + ns.HudCard.UNIT_GAP
            assert.are.equal(center - unit / 2, x)
        end)

        it("shows the second divider only with rows below the numbers", function()
            ns.HudCard.Draw(card, model(), "card")
            assert.is_true(card.dividers[1]:IsShown())
            assert.is_false(card.dividers[2]:IsShown())
            local last = { text = "Firefin Snapper", color = { 1, 1, 1 }, bite = "8.4 s" }
            ns.HudCard.Draw(card, model({ last = last }), "card")
            assert.is_true(card.dividers[2]:IsShown())
        end)

        it("draws the green tick where getaways stop, hidden without it", function()
            local m = model()
            m.bar.safe = 1
            ns.HudCard.Draw(card, m, "card")
            assert.is_true(card.safe:IsShown())
            assert.are.same(ns.Style.GREEN[1], card.safe.color[1])
            local _, _, _, x = card.safe:GetPoint()
            assert.are.equal(ns.HudCard.WIDTH - 2 * ns.HudCard.PAD - 1, x)
            ns.HudCard.Draw(card, model(), "card")
            assert.is_false(card.safe:IsShown())
        end)
    end)
end)
