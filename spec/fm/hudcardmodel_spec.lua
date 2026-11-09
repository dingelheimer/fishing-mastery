-- The HUD card of Draft 5 (Story 9.8): both drafted states (safe water; risky water with a lure),
-- the suggested lure, the compact line, grey numbers for small samples, the water's fish icons,
-- the tooltip of Draft 6, and the card view (rows, height, the long water name before the tag).
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")
local tiplines = require("spec.helpers.tiplines")

describe("FishingMastery HUD card", function()
    local ns, Getaway, HudModel, HudCardModel

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleUI.lua",
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
            "HudCardModel.lua",
            "Frames.lua",
            "Controls.lua",
            "HudCard.lua",
        }, nil, "FishingMastery")
        Getaway, HudModel, HudCardModel = ns.Getaway, ns.HudModel, ns.HudCardModel
    end)

    local function plain(text)
        return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end

    -- A session model: counts, rank, modifier, skill-ups, last catch.
    local function model(counts, fields)
        local session = { start = 1000, last = 1000, casts = 0, counts = counts, active = 0 }
        for _, n in pairs(counts) do
            session.casts = session.casts + n
        end
        session.catches = counts.catch or 0
        for key, value in pairs(fields or {}) do
            session[key] = value
        end
        return HudModel.Build({
            session = session,
            now = session.last,
            rank = fields and fields.rank,
            modifier = fields and fields.modifier,
        })
    end

    local ROWS = { { 6303, 60 }, { 6358, 30 }, { 6291, 10 }, { 6717, 5, nil, nil, true } }

    local function info(id)
        return ({
            [6303] = { name = "Raw Longjaw Mud Snapper", icon = 1 },
            [6358] = { name = "Oily Blackmouth", icon = 2 },
            [6291] = { name = "Raw Brilliant Smallfish", icon = 3 },
        })[id] or {}
    end

    it("draws the card of a safe water (Draft 5, The Barrens)", function()
        local m = model(
            { catch = 8, getaway = 1 },
            { rank = 154, modifier = 0, skillStart = 152, skill = 154, lastItem = 6303 }
        )
        m.lastBite = 227
        local zone = {
            name = "The Barrens",
            risk = Getaway.Risk(nil, 154, -20),
            rows = ROWS,
            items = { [6303] = 4, [6358] = 1 },
        }
        local input = {
            model = m,
            max = 225,
            zone = zone,
            last = { name = "Raw Longjaw Mud Snapper", icon = 1, hex = "ffffffff" },
            info = info,
        }
        local card = HudCardModel.Build(input)
        assert.are.equal("The Barrens", card.zone)
        assert.are.same({ text = "no getaways", kind = "safe" }, card.risk)
        assert.are.equal("Fishing 154 / 225 +2", plain(card.bar.text))
        assert.are.same({ 154, 225 }, { card.bar.value, card.bar.max })
        assert.is_nil(card.bar.mark) -- no modifier
        assert.is_nil(card.riskLine) -- nothing gets away
        assert.are.same({ text = "No lure needed here", grey = true }, card.lure)
        assert.are.same({ "8", "8/9", "-" }, {
            card.numbers[1].value,
            card.numbers[2].value,
            card.numbers[3].value,
        })
        assert.is_true(card.numbers[2].grey and card.numbers[3].grey)
        assert.are.same(
            { text = "Raw Longjaw Mud Snapper", icon = 1, color = { 1, 1, 1 }, bite = "22.7 s" },
            card.last
        )
        -- The water's fish without the quest row: two caught, one missing.
        assert.are.equal(3, #card.fish)
        assert.are.same({ true, true, false }, {
            card.fish[1].caught,
            card.fish[2].caught,
            card.fish[3].caught,
        })
        assert.are.equal("Raw Brilliant Smallfish", card.fish[3].name)
        assert.are.equal("1 missing", card.missing)
        assert.are.equal(
            "The Barrens  |  no getaways  |  8 catches  |  8/9  |  Fishing 154 +2",
            plain(card.compact)
        )
    end)

    it("draws the card of a risky water with a lure (Draft 5, Stranglethorn Vale)", function()
        local m = model({ catch = 23, getaway = 12 }, { rank = 151, modifier = 25 })
        local risk = Getaway.Risk(nil, 176, 130)
        local card = HudCardModel.Build({
            model = m,
            max = 225,
            zone = { name = "Stranglethorn Vale", risk = risk, rows = ROWS, items = {} },
            lure = { bonus = 25, seconds = 462 },
            info = info,
        })
        local percent = math.floor(risk.model.getaway * 100 + 0.5)
        assert.are.same({ text = percent .. " % get away", kind = "risk" }, card.risk)
        assert.are.equal(176 / 225, card.bar.mark)
        assert.are.equal("with lure 176", card.riskLine.left)
        assert.are.equal("getaways stop at 225", plain(card.riskLine.right))
        assert.are.equal("Lure +25", card.lure.text)
        assert.are.equal("7:42", card.lure.timer)
        assert.are.equal(HudCardModel.LURE_ICON, card.lure.icon)
        assert.are.equal("23", card.numbers[1].value)
        assert.is_false(card.numbers[2].grey) -- 35 fair casts: full
        -- Story 10.2: "%" as a small unit, the compact line keeps "66 %", the green tick at 225.
        local success = card.numbers[2]
        assert.are.same({ "%", nil }, { success.unit, card.numbers[1].unit })
        assert.truthy(success.value:find("^%d+$"))
        assert.truthy(plain(card.compact):find("|  " .. success.value .. " %  |", 1, true))
        assert.are.equal(1, card.bar.safe) -- getaways stop at the bar's end
        assert.are.equal("3 missing", card.missing)
        assert.is_nil(card.last)
    end)

    it("draws the green tick only in risky water and only on the bar", function()
        local m = model({ catch = 3 }, { rank = 100 })
        local function safe(max, risk)
            local zone = { name = "W", risk = risk }
            return HudCardModel.Build({ model = m, max = max, zone = zone }).bar.safe
        end
        local risky = Getaway.Risk(nil, 100, 90) -- base 90: fish still get away at 100
        assert.are.equal(risky.model.stopsAt / 225, safe(225, risky))
        assert.is_nil(safe(150, risky)) -- past the bar's end (cap 150)
        assert.is_nil(safe(225, Getaway.Risk(nil, 100, 1))) -- no getaways: no tick
        assert.is_nil(HudCardModel.Build({ model = m, max = 225 }).bar.safe) -- no water line
    end)

    it(
        "suggests the smart lure's choice and leaves the water out without the water line",
        function()
            local m = model({ catch = 1 }, { rank = 60 })
            local card = HudCardModel.Build({
                model = m,
                zone = { name = "Wetlands", risk = Getaway.Risk(nil, 60, 55) },
                suggestion = { name = "Shiny Bauble", bonus = 25, icon = 7 },
            })
            assert.are.equal("Shiny Bauble +25", plain(card.lure.text))
            assert.are.same({ 7, true }, { card.lure.icon, card.lure.dim })
            assert.are.equal("your skill 60", card.riskLine.left)
            assert.are.equal("Fishing 60 / 60", plain(card.bar.text)) -- no cap known: the rank
            assert.is_nil(card.fish) -- no list
            card = HudCardModel.Build({ model = m })
            assert.are.equal("Fishing Mastery", card.zone)
            assert.are.equal("", card.risk.text)
            assert.are.same({ text = "No lure", grey = true }, card.lure)
            assert.are.equal(
                "?",
                HudCardModel.Build({
                    model = m,
                    zone = { name = "Here", risk = Getaway.Risk(nil, 60) },
                }).risk.text
            )
        end
    )

    it("writes the HUD tooltip of Draft 6", function()
        local m = model({ catch = 23, getaway = 12 }, { rank = 176, active = 1140 })
        local bands = { [175] = { hooked = 35, getaways = 10 } }
        local input = {
            model = m,
            zone = { name = "Stranglethorn Vale", risk = Getaway.Risk(bands, 176, 130) },
            suggestion = { name = "Shiny Bauble", bonus = 25 },
        }
        local lines = tiplines.lines(HudCardModel.Tip(input, function(tip)
            tip:Line("dev line")
        end))
        assert.are.equal("Stranglethorn Vale", lines[1])
        assert.are.equal("This session, 19 min", lines[2])
        assert.are.equal("Catches = 23 of 35 casts", lines[3])
        assert.truthy(lines[4]:find("^Success = 66 %% %(%d+ %- %d+%)$"))
        assert.truthy(lines[5]:find("^Per hour = "))
        assert.are.equal("Getaways here", lines[7])
        assert.truthy(lines[8]:find("^Classic, skill 176 = %d+ %%$"))
        assert.truthy(lines[9]:find("^Yours, skill 175 %- 179 = 29 %% %(%d+ %- %d+%)$"))
        assert.are.equal("None from skill = 225", lines[10])
        local text = table.concat(lines, "\n")
        assert.truthy(text:find("Best lure = Shiny Bauble +25", 1, true))
        assert.truthy(text:find("Hold Shift for how this is counted", 1, true))
        assert.are.equal("dev line", lines[#lines])
        local shifted = tiplines.text(HudCardModel.Tip(input), true)
        assert.truthy(shifted:find("Classic model: the getaway formula", 1, true))
    end)

    it("stacks the card rows and cuts a long water name before the tag", function()
        local env = fakeui.new()
        local card = ns.HudCard.Create(env, env.UIParent)
        local base = {
            zone = "The Cape of Stranglethorn",
            risk = { text = "100 % get away", kind = "risk" },
            bar = { value = 10, max = 75, text = "Fishing 10 / 75" },
            lure = { text = "No lure", grey = true },
            numbers = { { value = "1" }, { value = "1/1", grey = true }, { value = "-" } },
            compact = "line",
        }
        ns.HudCard.Draw(card, base, "card")
        local short = card.card.height
        local tag = card.tag:GetStringWidth() + ns.HudCard.TAG_GAP
        assert.are.equal(ns.HudCard.WIDTH - 2 * ns.HudCard.PAD - tag, card.zone.width)
        base.riskLine = { left = "your skill 10", right = "getaways stop at 25" }
        base.last = { text = "Raw Slitherskin Mackerel", color = { 1, 1, 1 }, bite = "9.0 s" }
        base.fish = { { id = 1, caught = true }, { id = 2, caught = false } }
        base.missing = "1 missing"
        ns.HudCard.Draw(card, base, "card")
        -- risk line, the divider under the numbers, last catch, fish
        assert.are.equal(short + 14 + 4 + 22 + 22, card.card.height)
        assert.is_true(card.fishSlots[2]:IsShown())
        assert.is_false(card.fishSlots[3]:IsShown())
        assert.is_nil(card.cardButtons) -- no buttons without actions (the Settings preview)
        ns.HudCard.Draw(card, base, "compact")
        assert.is_true(card.compact:IsShown())
        assert.is_false(card.card:IsShown())
        assert.are.equal("line", card.line:GetText())
    end)
end)
