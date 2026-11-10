-- HUD session time and value (Story 10.6): the row under the numbers with the time since the
-- session's first cast and the vendor value of its catch, the time at the end of the compact
-- line, and the 30-second redraw while a session is open.
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")
local fmboot = require("spec.helpers.fmboot")

describe("FishingMastery HUD session time and value", function()
    describe("model and view", function()
        local ns

        before_each(function()
            ns = addon.load({
                "Locale.lua",
                "LocaleStats.lua",
                "LocaleUI.lua",
                "LocaleJournal.lua",
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
                "Look.lua",
                "HudModel.lua",
                "SummaryModel.lua",
                "RowTip.lua",
                "Getaway.lua",
                "HudCardModel.lua",
                "Frames.lua",
                "Controls.lua",
                "HudCard.lua",
                "HudCardFish.lua",
            }, nil, "FishingMastery")
        end)

        local PRICES = { [6303] = 1, [6358] = 4, [6289] = nil }

        local function build(items, minutes)
            local session = {
                start = 1000,
                last = 1000 + minutes * 60,
                casts = 3,
                catches = 3,
                counts = { catch = 3 },
                active = 0,
                items = items,
            }
            local model = ns.HudModel.Build({ session = session, now = session.last, rank = 50 })
            return ns.HudCardModel.Build({
                model = model,
                info = function(id)
                    return { sellPrice = PRICES[id] }
                end,
            })
        end

        local function plain(text)
            return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        end

        it("writes the time since the first cast and the catch's vendor value", function()
            local card = build({ [6303] = 30, [6358] = 25 }, 25)
            assert.are.same({ "25 min", "1s 30c", false }, {
                card.session.time,
                card.session.value,
                card.session.grey,
            })
            assert.are.same({ "1 h 05 min", "-", true }, {
                build({}, 65).session.time,
                build({}, 65).session.value,
                build({}, 65).session.grey,
            })
            -- An item without a price (not loaded) adds nothing; only unpriced items: "-".
            assert.are.equal(
                "1s 30c",
                build({ [6303] = 30, [6358] = 25, [6289] = 9 }, 1).session.value
            )
            assert.are.equal("-", build({ [6289] = 9 }, 1).session.value)
            assert.truthy(plain(build({}, 25).compact):find("  |  25 min$"))
        end)

        it("draws the row under the numbers, the value grey without a priced item", function()
            local env = fakeui.new()
            local card = ns.HudCard.Create(env, env.UIParent)
            ns.HudCard.Draw(card, build({ [6303] = 2 }, 4), "card")
            assert.are.same({ "4 min", "2c" }, {
                card.sessionTime:GetText(),
                card.sessionValue:GetText(),
            })
            assert.are.same(ns.Style.WHITE, card.sessionValue.color)
            local _, _, _, _, rowY = card.sessionTime:GetPoint()
            local _, _, _, _, dividerY = card.dividers[2]:GetPoint()
            assert.is_true(rowY < dividerY) -- under the second divider
            ns.HudCard.Draw(card, build({}, 4), "card")
            assert.are.same(ns.Style.GREY, card.sessionValue.color)
            -- The Settings preview sample has the row too.
            local sample = ns.HudCardModel.Sample()
            assert.are.same({ "4 min", "35s 20c" }, { sample.session.time, sample.session.value })
        end)
    end)

    describe("boot", function()
        local w

        before_each(function()
            w = fmboot.new()
            w.boot(nil, nil)
            w.fire("PLAYER_ENTERING_WORLD", true, false)
        end)

        after_each(function()
            w.cleanup()
        end)

        it("redraws every 30 seconds while a session is open and stops after it", function()
            local hud = w.ns.hud
            w.catch(5000, 9)
            local card = hud.card
            assert.are.equal("0 min", card.sessionTime:GetText())
            assert.is_true(hud.clocking) -- one session clock pending
            w.catch(5020, 9) -- a cast in between schedules no second clock
            assert.is_true(hud.clocking)
            w.runTimers(5000 + 9 + 150) -- the clock fires: the time moves without a cast
            assert.are.equal("2 min", card.sessionTime:GetText())
            assert.is_true(hud.clocking) -- and schedules the next one
            w.runTimers(5000 + 9 + 150 + w.ns.Session.IDLE + 60) -- the session ends idle
            w.runTimers(w.clock + 31) -- the last clock fires on a closed session
            assert.is_false(hud.frame:IsShown())
            assert.is_false(hud.clocking) -- none scheduled again
            assert.are.equal(0, w.ns.Guard.errors)
        end)
    end)
end)
