-- Style kit of the UI overhaul (Story 9.1): the pure Style helpers, the Tip builder on a fake
-- GameTooltip (pairs, ranges, hints, Shift details and the redraw on a Shift change), and the
-- table style of StatsList (stripes, number cells, alignment, icons, colors, tags, grey cells,
-- legend, sort arrow, hover, Tip tooltips).
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")

local FILES = { "Locale.lua", "LocaleUI.lua", "Guard.lua", "Style.lua", "Tip.lua", "StatsList.lua" }

local function load()
    return addon.load(FILES, nil, "FishingMastery")
end

-- A fake env with a ScrollBox that draws every row of its data provider at once.
local function listEnv()
    local env = fakeui.new()
    env.CreateScrollBoxListLinearView = function()
        return {
            SetElementExtent = function() end,
            SetElementInitializer = function(view, _, init)
                view.init = init
            end,
        }
    end
    env.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(box, _, view)
            box.SetDataProvider = function(_, provider)
                box.drawn = {}
                for i, data in ipairs(provider.rows) do
                    box.pool = box.pool or {}
                    local row = box.pool[i] or env.CreateFrame("Frame", nil, box)
                    box.pool[i] = row
                    view.init(row, data)
                    box.drawn[i] = row
                end
            end
        end,
    }
    env.CreateDataProvider = function(rows)
        return { rows = rows }
    end
    return env
end

describe("FishingMastery style kit", function()
    local ns

    before_each(function()
        ns = load()
    end)

    describe("Style", function()
        it("formats whole numbers with thousands separators", function()
            local n = ns.Style.Number
            assert.are.equal("0", n(0))
            assert.are.equal("999", n(999))
            assert.are.equal("1,284", n(1284))
            assert.are.equal("1,234,567", n(1234567))
            assert.are.equal("-12,000", n(-12000))
            assert.are.equal("3.5", n(3.5))
            assert.are.equal("5 %", n("5 %"))
            assert.are.equal("", n(nil))
        end)

        it("paints text and writes ranges with a grey bracket", function()
            local Style = ns.Style
            assert.are.equal("ffffd100", Style.Hex(Style.GOLD))
            assert.are.equal("|cffffffffx|r", Style.Paint("x", Style.WHITE))
            assert.are.equal("66 % |cff8c8c8c(52 - 78)|r", Style.Range("66 %", 52, 78))
            assert.are.equal("71", Style.Range("71", nil, nil))
            assert.are.equal("~1 %", Style.Approx("1 %"))
        end)
    end)

    describe("Tip", function()
        local env, owner

        before_each(function()
            env = fakeui.new()
            owner = env.CreateFrame("Frame")
        end)

        local function draw(tip)
            tip:Title("Stranglethorn Vale", ns.Style.GOLD)
            tip:Pair("Catches", "23 of 35 casts")
            tip:Pair("Success", ns.Style.Range("66 %", 52, 78))
            tip:Gap()
            tip:Header("Getaways here")
            tip:Pair("Yours", "29 %", ns.Style.ORANGE)
            tip:Gap()
            tip:Hint("Left-click: open")
            tip:Details({ "Brackets: where the true value most likely lies." })
        end

        it("draws a title, gold label pairs, gaps, a header, and a green hint", function()
            ns.Tip.Open(env, owner, draw)
            local tip = env.GameTooltip
            assert.is_true(tip.shown)
            assert.are.equal(owner, tip.owner)
            assert.are.same({
                "Stranglethorn Vale",
                "Catches = 23 of 35 casts",
                "Success = 66 % |cff8c8c8c(52 - 78)|r",
                " ",
                "Getaways here",
                "Yours = 29 %",
                " ",
                "Left-click: open",
                " ",
                "Hold Shift for how this is counted",
            }, tip.lines)
            assert.are.same(ns.Style.GOLD, tip.colors[1])
            assert.are.same({ ns.Style.GOLD, ns.Style.WHITE }, tip.colors[2])
            assert.are.same({ ns.Style.GOLD, ns.Style.ORANGE }, tip.colors[6])
            assert.are.same(ns.Style.GREEN, tip.colors[8])
            assert.are.same(ns.Style.GREY, tip.colors[10])
            for i = 1, #tip.lines do
                assert.is_falsy(tip.wraps[i])
            end
        end)

        it("shows the details only while Shift is held and redraws on a Shift change", function()
            ns.Tip.Open(env, owner, draw)
            local watcher = env.frames[#env.frames]
            assert.is_true(watcher.events.MODIFIER_STATE_CHANGED)
            env.shift = true
            watcher:Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
            local tip = env.GameTooltip
            assert.are.equal(
                "Brackets: where the true value most likely lies.",
                tip.lines[#tip.lines]
            )
            assert.is_true(tip.wraps[#tip.lines])
            -- Another key, or a tooltip the owner no longer holds, draws nothing new.
            env.shift = false
            watcher:Fire("MODIFIER_STATE_CHANGED", "LCTRL", 0)
            assert.are.equal(
                "Brackets: where the true value most likely lies.",
                tip.lines[#tip.lines]
            )
            ns.Tip.Close(env, owner)
            watcher:Fire("MODIFIER_STATE_CHANGED", "RSHIFT", 0)
            assert.is_false(tip.shown)
            assert.are.equal(0, ns.Guard.errors)
        end)

        it("turns a pair before any title into one line", function()
            ns.Tip.Open(env, owner, function(tip)
                tip:Gap()
                tip:Pair("Caught", 3)
            end)
            assert.are.same({ "Caught: 3" }, env.GameTooltip.lines)
        end)
    end)

    describe("StatsList table style", function()
        local env, parent, list
        local COLUMNS = {
            { key = "name", label = "Fish", width = 200, icon = true, tags = true },
            { key = "n", label = "Caught", width = 70, right = true },
            { key = "share", label = "Share", width = 70, right = true },
        }

        before_each(function()
            env = listEnv()
            parent = env.CreateFrame("Frame")
        end)

        local function rows()
            return {
                {
                    cells = { "Raw Sagefish", 1284, "15 %" },
                    icons = { "icon-sagefish" },
                    colors = { { 0.12, 1, 0 } },
                },
                {
                    cells = { "Raw Glossy Mightfish", 7, "~1 %" },
                    tags = { { text = "summer", kind = "season" } },
                    grey = { [3] = true },
                    tip = function(tip)
                        tip:Title("Raw Glossy Mightfish")
                        tip:Pair("Caught", 7)
                    end,
                },
                {
                    cells = { "Raw Nightfin Snapper", 3, "-" },
                    tags = { { text = "night", kind = "night" } },
                },
            }
        end

        it(
            "draws striped rows, numbers with separators, alignment, icons, colors, and tags",
            function()
                list = ns.StatsList.Create(env, parent, COLUMNS, function() end)
                list:SetRows(rows(), false, { key = "n", descending = true })
                local first, second, third = list.box.drawn[1], list.box.drawn[2], list.box.drawn[3]
                assert.is_false(first.stripe:IsShown())
                assert.is_true(second.stripe:IsShown())
                assert.is_false(third.stripe:IsShown())
                assert.are.equal("1,284", first.cells[2]:GetText())
                assert.are.equal("RIGHT", first.cells[2].justifyH)
                assert.are.equal("LEFT", first.cells[1].justifyH)
                assert.are.equal("icon-sagefish", first.icons[1].texture)
                assert.is_true(first.icons[1]:IsShown())
                assert.is_false(second.icons[1]:IsShown())
                assert.are.same({ 0.12, 1, 0 }, first.cells[1].color)
                assert.are.same(ns.Style.GREY, second.cells[3].color)
                assert.are.same(ns.Style.WHITE, second.cells[2].color)
                assert.is_false(first.tags[1].text:IsShown())
                assert.are.equal("summer", second.tags[1].text:GetText())
                assert.are.same(ns.Style.SEASON, second.tags[1].text.color)
                assert.are.equal("night", third.tags[1].text:GetText())
                assert.are.same(ns.Style.NIGHT, third.tags[1].text.color)
            end
        )

        it("puts the sort arrow on the sorted column and flips it", function()
            local sorted = {}
            list = ns.StatsList.Create(env, parent, COLUMNS, function(key)
                sorted[#sorted + 1] = key
            end)
            list:SetRows(rows(), false, { key = "n", descending = true })
            assert.is_false(list.headers[1].arrow:IsShown())
            assert.is_true(list.headers[2].arrow:IsShown())
            assert.are.same(ns.StatsList.ARROW_DOWN, list.headers[2].arrow.coords)
            list:SetRows(rows(), false, { key = "n", descending = false })
            assert.are.same(ns.StatsList.ARROW_UP, list.headers[2].arrow.coords)
            assert.are.equal("Caught", list.headers[2]:GetText())
            assert.are.equal("RIGHT", list.headers[2].fontString.justifyH)
            list.headers[3]:Click()
            assert.are.same({ "share" }, sorted)
        end)

        it("highlights the hovered row and opens Tip tooltips", function()
            list = ns.StatsList.Create(env, parent, COLUMNS)
            list:SetRows(rows())
            local row = list.box.drawn[2]
            row.scripts.OnEnter(row)
            assert.is_true(row.hover:IsShown())
            assert.are.same({ "Raw Glossy Mightfish", "Caught = 7" }, env.GameTooltip.lines)
            row.scripts.OnLeave(row)
            assert.is_false(row.hover:IsShown())
            assert.is_false(env.GameTooltip.shown)
            assert.are.equal(0, ns.Guard.errors)
        end)

        it("shows a legend under the list and gives its space back when removed", function()
            list = ns.StatsList.Create(env, parent, COLUMNS)
            local function bottom()
                return select(5, list.box:GetPoint(2))
            end
            assert.are.equal(0, bottom())
            list:SetLegend("~ grey: few casts")
            assert.are.equal("~ grey: few casts", list.legendText:GetText())
            assert.are.equal(ns.StatsList.LEGEND_HEIGHT, bottom())
            list:SetLegend(nil)
            assert.is_false(list.legendText:IsShown())
            assert.are.equal(0, bottom())
        end)
    end)
end)
