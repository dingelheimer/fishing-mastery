-- HUD lure name and tooltip (Story 10.3): the running lure's item from its bonus (bags first, the
-- only lure of that bonus otherwise, none when two share it), the card's lure row with the name,
-- the tooltip's best lure only in risky water with "on the pole", and /fm dev lure.
local addon = require("spec.helpers.addon")
local fmboot = require("spec.helpers.fmboot")
local tiplines = require("spec.helpers.tiplines")

local SHINY, NIGHTCRAWLERS, BRIGHT, ATTRACTOR, LENS, WORM = 6529, 6530, 6532, 6533, 6811, 7307

describe("FishingMastery lure name", function()
    local ns

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleUI.lua",
            "Data\\Journal.lua",
            "Guard.lua",
            "Session.lua",
            "Options.lua",
            "OptionsControls.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Totals.lua",
            "Stats.lua",
            "Style.lua",
            "Tip.lua",
            "HudModel.lua",
            "RowTip.lua",
            "Getaway.lua",
            "LureChoice.lua",
            "HudCardModel.lua",
            "HudCardTip.lua",
        }, nil, "FishingMastery")
    end)

    local function plain(text)
        return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end

    it("finds the running lure in the bags first, else the only lure of its bonus", function()
        local lures = ns.Journal.lures
        local function running(bonus, owned)
            return ns.LureChoice.Running(bonus, owned, lures)
        end
        -- One kind of +50 in the bags: that one; both kinds: the lower item ID.
        assert.are.equal(LENS, running(50, { { id = LENS, bonus = 50 } }))
        local both = { { id = LENS, bonus = 50 }, { id = NIGHTCRAWLERS, bonus = 50 } }
        assert.are.equal(NIGHTCRAWLERS, running(50, both))
        -- Nothing of that bonus owned: the only lure with it, none when two share it.
        assert.are.equal(SHINY, running(25, { { id = BRIGHT, bonus = 75 } }))
        assert.are.equal(ATTRACTOR, running(100, nil))
        assert.is_nil(running(50, {}))
        assert.is_nil(running(75, nil)) -- Bright Baubles and Flesh Eating Worm
        assert.are.equal(WORM, running(75, { { id = WORM, bonus = 75 } }))
        assert.is_nil(running(nil, both)) -- an enchant the data does not know
    end)

    local function sessionModel(rank, modifier)
        return ns.HudModel.Build({
            session = {
                start = 1000,
                last = 1000,
                casts = 35,
                catches = 23,
                counts = { catch = 23, getaway = 12 },
                active = 1140,
            },
            now = 1000,
            rank = rank,
            modifier = modifier,
        })
    end

    it("names the running lure on the card, or keeps the bonus alone", function()
        local base = { model = sessionModel(151, 25) }
        base.lure = { bonus = 25, seconds = 462, name = "Shiny Bauble", icon = 134335 }
        local row = ns.HudCardModel.Build(base).lure
        assert.are.equal("Shiny Bauble +25", plain(row.text))
        assert.are.same({ 134335, "7:42" }, { row.icon, row.timer })
        base.lure = { bonus = 50, seconds = 60 } -- two lures share +50: no name
        row = ns.HudCardModel.Build(base).lure
        assert.are.same({ "Lure +50", ns.HudCardModel.LURE_ICON }, { row.text, row.icon })
    end)

    it("shows the best lure in risky water only, with 'on the pole' when it runs", function()
        local Getaway = ns.Getaway
        local risky = { name = "Stranglethorn Vale", risk = Getaway.Risk(nil, 176, 130) }
        local safe = { name = "Durotar", risk = Getaway.Risk(nil, 176, 1) }
        local best = { name = "Shiny Bauble", bonus = 25 }
        local function text(input)
            input.model = sessionModel(176)
            return tiplines.text(ns.HudCardModel.Tip(input))
        end
        assert.truthy(
            text({ zone = risky, suggestion = best }):find(
                "Best lure = Shiny Bauble +25\n",
                1,
                true
            )
        )
        local on = text({ zone = risky, suggestion = best, lure = { bonus = 25, seconds = 60 } })
        assert.truthy(on:find("Best lure = Shiny Bauble +25 on the pole", 1, true))
        local other = text({ zone = risky, suggestion = best, lure = { bonus = 50, seconds = 60 } })
        assert.truthy(other:find("Best lure = Shiny Bauble +25\n", 1, true))
        assert.falsy(text({ zone = safe, suggestion = best }):find("Best lure", 1, true))
        assert.falsy(text({ zone = risky }):find("Best lure", 1, true)) -- none owned
    end)
end)

describe("FishingMastery /fm dev lure", function()
    local w

    before_each(function()
        w = fmboot.new()
        w.boot({ schemaVersion = 1, chars = {}, settings = { dev = true } }, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
    end)

    after_each(function()
        w.cleanup()
    end)

    it("prints and keeps the lure enchant ID with the data's bonus", function()
        _G.SlashCmdList.FM("dev lure")
        assert.truthy(w.output():find("No lure on the pole", 1, true))
        w.game.lure = 264
        _G.SlashCmdList.FM("dev lure")
        assert.truthy(w.output():find("Lure enchant 264: +50 in the data, 9:44 left", 1, true))
        local entry = _G.FishingMasteryDB.dev.lures[264]
        assert.are.same({ 50, 584 }, { entry.bonus, entry.seconds })
        w.game.lure = 9999
        _G.SlashCmdList.FM("dev lure")
        assert.truthy(w.output():find("Lure enchant 9999: unknown in the data", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
