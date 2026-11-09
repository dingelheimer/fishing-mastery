-- Fish tab builders (JournalTable.lua) on the generated data: list rows with every column filled
-- for caught and not-caught fish (dimmed icon, grey cells), the group and caught filters, a
-- plain-text search (pattern characters are literal), the progress line, and the detail pane
-- (JournalDetail.lua): pairs, the places and recipes tables with own shares and known marks,
-- season, time of day, and new-in-Forever and quest-only marks.
local addon = require("spec.helpers.addon")
local tiplines = require("spec.helpers.tiplines")

local AREA_NAMES = {
    [14] = "Durotar",
    [367] = "Sen'jin Village",
    [33] = "Stranglethorn Vale",
    [297] = "Jaguero Isle",
}
local ITEMS =
    { [6291] = "Raw Brilliant Smallfish", [13755] = "Winter Squid", [21071] = "Raw Sagefish" }

describe("FishingMastery journal table", function()
    local ns, JournalTable, areas, index

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleUI.lua",
            "Style.lua",
            "LocaleStats.lua",
            "LocaleJournal.lua",
            "Data\\Zones.lua",
            "Data\\Journal.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Options.lua",
            "OptionsControls.lua",
            "Totals.lua",
            "Season.lua",
            "Stats.lua",
            "HudModel.lua",
            "StatsTables.lua",
            "Area.lua",
            "JournalModel.lua",
            "RecipeModel.lua",
            "JournalTable.lua",
            "JournalDetail.lua",
        }, nil, "FishingMastery")
        JournalTable = ns.JournalTable
        areas = ns.Area.New(ns.Zones, function(id)
            return AREA_NAMES[id]
        end)
        index = ns.JournalModel.Index(ns.Journal, ns.Zones, areas)
    end)

    local function model(items)
        return ns.JournalModel.Build({
            index = index,
            view = { items = items or {} },
            classOf = function(id)
                if id == 21071 then
                    return 7, 8
                end
            end,
        })
    end

    local shares = {}
    local function input()
        return {
            info = function(id)
                return { name = ITEMS[id] or ("Item " .. id), icon = 1000 + id }
            end,
            areas = areas,
            mapName = function(map)
                return ({ [1411] = "Durotar", [1413] = "The Barrens" })[map]
            end,
            areaName = function(area)
                return AREA_NAMES[area]
            end,
            spellName = function(spell)
                return ({ [7751] = "Brilliant Smallfish" })[spell]
            end,
            recipe = function(spell)
                return ns.RecipeModel.Find(ns.RecipeModel.Build(ns.Journal, nil), spell)
            end,
            known = function(spell)
                return spell == 7751
            end,
            ownShare = function(area, id)
                local s = shares[area]
                if s then
                    return s[id] or 0, s.n
                end
            end,
            formatDate = function(t)
                return "date " .. t
            end,
            formatMonthDay = function(month, day)
                return day .. "/" .. month
            end,
            monthName = function(month)
                return "M" .. month
            end,
            inSeason = function(season)
                return season.season == "winter"
            end,
            hourOffset = -1,
            thresholds = ns.Stats.Thresholds(),
        }
    end

    local CAUGHT = {
        [6291] = {
            n = 4,
            qty = 5,
            first = 100,
            firstMap = 1411,
            firstSub = "Sen'jin Village",
            best = 1411,
        },
        [21071] = { n = 1, qty = 1, first = 200, firstMap = 1413, firstSub = "", best = 1413 },
    }

    local function byId(rows)
        local out = {}
        for _, row in ipairs(rows) do
            out[row.id] = row
        end
        return out
    end

    it("fills every column for caught and not-caught fish", function()
        local rows =
            byId(JournalTable.Rows(model(CAUGHT), input(), { group = "all", show = "all" }))
        local fish = rows[6291]
        assert.are.same({ "Raw Brilliant Smallfish", "Fish", "4", "Durotar", "1-25" }, fish.cells)
        assert.are.same({ 7291 }, fish.icons)
        assert.are.same({ false }, fish.dim)
        assert.is_nil(fish.grey)
        local squid = rows[13755]
        assert.are.equal("Winter Squid", squid.cells[1])
        assert.are.same({ 14755 }, squid.icons)
        assert.are.same({ true }, squid.dim) -- not caught: dimmed icon
        assert.are.same({}, squid.colors) -- grey row, no quality color
        assert.are.same({ { text = "winter", kind = "season" } }, squid.tags)
        assert.are.same({ "Fish", "not caught" }, { squid.cells[2], squid.cells[3] })
        assert.are.equal("205-300", squid.cells[5])
        assert.are_not.equal("-", squid.cells[4]) -- best Classic place
        assert.is_true(squid.grey[1] and squid.grey[5])
        local sagefish = rows[21071]
        assert.are.same({ "The Barrens", "-" }, { sagefish.cells[4], sagefish.cells[5] })
        assert.are.equal(89, #JournalTable.Rows(model(CAUGHT), input(), {}))
    end)

    it("filters by group, caught or not, and a plain-text search", function()
        local m, i = model(CAUGHT), input()
        assert.are.equal(35, #JournalTable.Rows(m, i, { group = "trophy" }))
        assert.are.equal(2, #JournalTable.Rows(m, i, { show = "caught" }))
        assert.are.equal(87, #JournalTable.Rows(m, i, { show = "missing" }))
        local found = JournalTable.Rows(m, i, { search = "SMALLFISH" })
        assert.are.same({ 6291 }, { found[1].id, found[2] and found[2].id })
        assert.are.equal(0, #JournalTable.Rows(m, i, { search = "%[(" }))
        local selected = JournalTable.Rows(m, i, { search = "squid", selected = 13755 })
        assert.is_true(selected[1].selected)
    end)

    it("writes the header bar with every group, new-in-Forever, and pending items", function()
        local m = model(CAUGHT)
        local bar = JournalTable.Bar(m)
        assert.are.same({ 1, 28, "Fish 1 / 28" }, { bar.caught, bar.total, bar.text })
        assert.are.same({
            { label = "Fish", value = "1 / 28 + 1 new in Forever" },
            { label = "Trophy fish", value = "0 / 35" },
            { label = "Containers", value = "0 / 18" },
            { label = "Quest fish", value = "0 / 7" },
        }, bar.lines)
        assert.is_nil(bar.pending)
        m.pending = 2
        bar = JournalTable.Bar(m)
        assert.truthy(bar.pending:find("Loading item data for 2 caught items", 1, true))
    end)

    local function detail(entry, inp)
        return tiplines.lines(ns.JournalDetail.Draw(entry, inp or input()))
    end

    local function text(entry, inp)
        return table.concat(detail(entry, inp), "\n")
    end

    local function entriesOf(items)
        local out = {}
        for _, e in ipairs(model(items).entries) do
            out[e.id] = e
        end
        return out
    end

    it("details a caught fish in pairs with the places and recipes as tables", function()
        shares = { [367] = { n = 10, [6291] = 4 }, [814] = { n = 2, [6291] = 1 } }
        local lines = detail(entriesOf(CAUGHT)[6291])
        assert.are.same({
            "|T7291:14:14|t Raw Brilliant Smallfish",
            "Fish",
            " ",
            "Caught = 4 (5 items)",
            "First catch = date 100",
            "First water = Sen'jin Village, Durotar",
            "Most caught = Durotar",
            "Catchable = at any skill",
            " ",
            "Where it bites | Classic | Yours",
        }, { unpack(lines, 1, 10) })
        local t = table.concat(lines, "\n")
        -- Subzone names only in the table; own shares in percent, grey counts below 10 casts.
        assert.truthy(t:find("\nSen'jin Village | %d+ %% | 40 %%\n"))
        assert.truthy(t:find("\n814 | %d+ %% | 1/2\n")) -- area 814 has no name in this stub
        assert.truthy(t:find("\n%+%d+ more places\n"))
        assert.truthy(t:find("Used in | Skill | \nBrilliant Smallfish | Cooking | known", 1, true))
        assert.is_nil(t:find("Season", 1, true))
        for _, line in ipairs(lines) do
            assert.is_true(#line <= 60, line) -- no sentences
        end
    end)

    it("details a not-caught seasonal fish, a quest fish, and a new fish", function()
        local entries = entriesOf(CAUGHT)
        local squid = text(entries[13755])
        assert.truthy(squid:find("Winter Squid", 1, true))
        assert.truthy(squid:find("Fish, winter\n", 1, true))
        assert.truthy(squid:find("Caught = not yet", 1, true))
        assert.truthy(squid:find("Catchable from = 205\nNo getaways from = 300", 1, true))
        assert.truthy(squid:find("Recipe 18240 | Cooking | ", 1, true))
        assert.truthy(squid:find("Season = winter, from 23/9\nLasts = 178 days", 1, true))
        assert.truthy(text(entries[16967]):find("Bites only during its quest", 1, true))
        local sagefish = text(entries[21071])
        assert.truthy(sagefish:find("New in Forever", 1, true))
        assert.truthy(sagefish:find("Skill = unknown", 1, true))
        assert.truthy(sagefish:find("Where it bites = no Classic data", 1, true))
        assert.are.same({ "Click a fish to see its details." }, detail(nil))
    end)

    it("tags the season now, own catches by month, and the day/night fish by hour", function()
        local entries = entriesOf({
            [13755] = { n = 3, qty = 3, first = 100, months = { [10] = 1, [1] = 2 } },
            [13759] = { n = 4, qty = 4, first = 100, hours = { [0] = 1, [19] = 3 } },
        })
        local squid = text(entries[13755])
        assert.truthy(squid:find("Now = in season", 1, true))
        assert.truthy(squid:find("By month = M1 2, M10 1", 1, true))
        local bass = text(entries[13756])
        assert.truthy(bass:find("Now = not in season", 1, true))
        assert.falsy(bass:find("By month", 1, true))
        local snapper = text(entries[13759])
        assert.truthy(snapper:find("Bites = at night (guides)", 1, true))
        assert.truthy(snapper:find("Your catches = 4 of 30 to confirm", 1, true))
        assert.truthy(snapper:find("By server hour = 18:00 3, 23:00 1", 1, true))
        local salmon = text(entries[13760])
        assert.truthy(salmon:find("Bites = by day (guides)\nYour catches = 0 of 30", 1, true))
        assert.falsy(salmon:find("By server hour", 1, true))

        entries[13759].hours = { [20] = 30 }
        assert.truthy(text(entries[13759]):find("Your catches = 30 to check against", 1, true))
        local plain = input()
        plain.inSeason = function() end -- no server time
        assert.falsy(text(entries[13755], plain):find("Now =", 1, true))
    end)
end)
