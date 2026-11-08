-- Table builders of the stats window: Fish (cells, ranges in tooltips, grey small samples, dry
-- streak and expected casts, sorting, quality filter), Zones (zones with their subzones), and the
-- record lines of the Sessions tab.
local addon = require("spec.helpers.addon")
local tiplines = require("spec.helpers.tiplines")

local DAY = 20763 * 86400
local HOUR5 = DAY + 5 * 3600

describe("FishingMastery stats tables", function()
    local ns, StatsModel, Totals

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleUI.lua",
            "Style.lua",
            "LocaleStats.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Session.lua",
            "Options.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "RowTip.lua",
            "SummaryModel.lua",
            "StatsView.lua",
            "StatsModel.lua",
            "StatsTables.lua",
            "ZoneTable.lua",
            "OverviewTable.lua",
        }, nil, "FishingMastery")
        StatsModel, Totals = ns.StatsModel, ns.Totals
    end)

    local ITEMS = {
        [6303] = {
            name = "Raw Slitherskin Mackerel",
            icon = 133910,
            quality = 1,
            hex = "ffffffff",
        },
        [6358] = { name = "Oily Blackmouth", icon = 133891, quality = 2, hex = "ff1eff00" },
    }

    local function input(extra)
        local result = {
            info = function(id)
                return ITEMS[id] or {}
            end,
            mapName = function(map)
                return ({ [1411] = "Durotar", [1412] = "Mulgore" })[map]
            end,
            formatDate = function(t)
                return os.date("!%Y-%m-%d", t)
            end,
            hourOffset = 2,
        }
        for key, value in pairs(extra or {}) do
            result[key] = value
        end
        return result
    end

    local function view(casts, subzones)
        local totals = Totals.New()
        for _, cast in ipairs(casts) do
            Totals.Add(totals, cast)
        end
        return ns.StatsView.Build({ { totals = totals, subzones = subzones or {} } })
    end

    -- 40 fair casts 20 s apart at UTC hour 5 in Durotar: Oily Blackmouth on casts 5 and 20,
    -- Mackerel on the other first 32, then 8 getaways.
    local function fishView()
        local casts = {}
        for i = 1, 40 do
            local cast = { t = HOUR5 + i * 20, map = 1411, out = "getaway" }
            if i <= 32 then
                local id = (i == 5 or i == 20) and 6358 or 6303
                cast.out, cast.loot = "catch", { { id = id, qty = 1 } }
            end
            casts[i] = cast
        end
        return view(casts)
    end

    local function byId(rows)
        local map = {}
        for _, row in ipairs(rows) do
            map[row.id] = row
        end
        return map
    end

    it("builds the six Fish cells with icon, quality color, tag, and the row tooltip", function()
        local tags = { [6358] = { text = "night", kind = "night" } }
        local rows = ns.StatsTables.Fish(
            fishView(),
            input({
                tag = function(id)
                    return tags[id]
                end,
            })
        )
        assert.are.equal(2, #rows)
        assert.are.equal(6303, rows[1].id) -- most caught first
        local mackerel, oily = byId(rows)[6303], byId(rows)[6358]
        -- 30 of 40 fair casts: about every 1.3 casts; 8 fair casts since its last catch (32).
        assert.are.same(
            { "Raw Slitherskin Mackerel", "30", "94 %", "1.3 casts", "8", "Durotar" },
            mackerel.cells
        )
        assert.are.same({ 133910 }, mackerel.icons)
        assert.are.same({ { 1, 1, 1 } }, mackerel.colors)
        assert.are.same({}, mackerel.tags)
        assert.is_false(mackerel.grey[3])
        assert.is_false(mackerel.grey[4])
        -- Oily Blackmouth: 2 of 40 fair casts, about every 20; 20 casts since; night tag.
        assert.are.same({ "Oily Blackmouth", "2", "6 %", "20 casts", "20", "Durotar" }, oily.cells)
        assert.are.same({ { text = "night", kind = "night" } }, oily.tags)
        assert.are.same({ 0x1e / 255, 1, 0 }, oily.colors[1])
        local low, high = ns.Stats.Wilson(2, 32)
        local lines = tiplines.lines(oily.tip)
        assert.are.equal("Oily Blackmouth", lines[1])
        assert.are.equal("Caught = 2", lines[2])
        assert.are.equal(
            string.format(
                "Share of catches = 6 %% (%d - %d)",
                math.floor(low * 100 + 0.5),
                math.floor(high * 100 + 0.5)
            ),
            lines[3]
        )
        assert.truthy(lines[4]:find("^About every = 20 casts %(%d+%.?%d* %- %d+%)$"))
        assert.are.equal("Dry streak = 20 casts", lines[5])
        assert.are.equal("Most often at = 07:00 realm time", lines[6]) -- UTC 5 + realm offset 2
        assert.are.equal(
            "First / last = "
                .. os.date("!%Y-%m-%d", HOUR5 + 5 * 20)
                .. " / "
                .. os.date("!%Y-%m-%d", HOUR5 + 20 * 20),
            lines[7]
        )
        assert.are.same({ " ", "Hold Shift for how this is counted" }, { lines[8], lines[9] })
        assert.are.equal(9, #lines) -- at most 8 lines before the Shift hint
        local shifted = tiplines.text(oily.tip, true)
        assert.truthy(shifted:find("Brackets: where the true value most likely lies", 1, true))
        assert.are.equal("1 kinds, 30 catches", ns.StatsTables.Kinds({ mackerel }))
        assert.are.equal("2 kinds, 32 catches", ns.StatsTables.Kinds(rows))
    end)

    it("sorts by any column, filters by quality, and greys small samples", function()
        local fish = fishView()
        local rows = ns.StatsTables.Fish(fish, input({ sort = { key = "name" } }))
        assert.are.equal(6358, rows[1].id) -- Oily before Raw
        rows = ns.StatsTables.Fish(fish, input({ sort = { key = "dry", descending = true } }))
        assert.are.equal(6358, rows[1].id) -- 20 fair casts since its last catch
        rows = ns.StatsTables.Fish(fish, input({ sort = { key = "dry" } }))
        assert.are.equal(6303, rows[1].id) -- 8
        rows = ns.StatsTables.Fish(fish, input({ sort = { key = "expected" } }))
        assert.are.equal(6303, rows[1].id) -- about every 1.3 casts before 20
        rows = ns.StatsTables.Fish(fish, input({ quality = 2 }))
        assert.are.equal(1, #rows)
        assert.are.equal(6358, rows[1].id)

        local small = view({
            { t = DAY, map = 1411, out = "catch", loot = { { id = 6303 } } },
            { t = DAY + 20, map = 1411, out = "catch", loot = { { id = 6303 } } },
            { t = DAY + 40, map = 1411, out = "catch", loot = { { id = 6359 } } },
        })
        rows = ns.StatsTables.Fish(small, input())
        local row = byId(rows)[6303]
        assert.are.equal("-", row.cells[3]) -- counts only below 10: in the tooltip
        assert.is_true(row.grey[3])
        assert.are.equal("Share of catches = 2 of 3", tiplines.lines(row.tip)[3])
        -- An item without cached data shows its ID until the name loads.
        assert.are.equal("Item 6359", byId(rows)[6359].cells[1])
    end)

    it("lists every zone with its subzones, most casts first", function()
        local casts = {}
        for i = 1, 15 do -- Durotar: 12 catches in subzone 1, then 3 getaways in subzone 2
            local cast = { t = DAY + i * 20, map = 1411, sub = i <= 12 and 1 or 2, out = "getaway" }
            if i <= 12 then
                cast.out, cast.loot = "catch", { { id = 6303 } }
            end
            casts[i] = cast
        end
        casts[16] = { t = DAY + 3600, map = 1412, out = "catch", loot = { { id = 6358 } } }
        casts[17] = { t = DAY + 3620, map = 1412, out = "catch", loot = { { id = 6358 } } }
        local rows =
            ns.ZoneTable.Rows(view(casts, { "Darkspear Strand", "Sen'jin Village" }), input())
        local names = {}
        for i, row in ipairs(rows) do
            names[i] = row.cells[1]
        end
        -- Mulgore was fished only without a subzone text: no subzone row.
        assert.are.same(
            { "Durotar", "    Darkspear Strand", "    Sen'jin Village", "Mulgore" },
            names
        )
        -- Durotar: 12 catches in 14 gaps of 20 s plus 60 s = 340 s active.
        assert.are.same({ "Durotar", "15", "127/h", "1", "|T133910:14:14|t 100 %" }, rows[1].cells)
        assert.is_true(rows[1].grey[3]) -- 15 fair casts: greyed
        assert.are.equal("180/h", rows[2].cells[3]) -- 12 catches in 240 s
        assert.are.equal("-", rows[3].cells[3]) -- 3 casts: too few for a rate
        assert.are.equal("0", rows[3].cells[4])
        assert.are.equal("-", rows[4].cells[3])
        local lines = tiplines.lines(rows[1].tip)
        assert.are.same({ "Durotar", "Casts = 15" }, { lines[1], lines[2] })
        assert.truthy(lines[3]:find("^Success rate = 80 %% %(%d+ %- %d+%)$"))
        assert.are.equal("Most caught here", lines[6])
        assert.are.equal("Raw Slitherskin Mackerel = ~100 %", lines[7]) -- 12 catches: few
    end)

    it("writes a share above 0 that rounds to 0 as <1 %", function()
        local casts = {}
        for i = 1, 300 do
            casts[i] = {
                t = DAY + i * 20,
                map = 1411,
                out = "catch",
                loot = { { id = i == 1 and 6358 or 6303 } },
            }
        end
        local rows = byId(ns.StatsTables.Fish(view(casts), input()))
        assert.are.equal("<1 %", rows[6358].cells[3]) -- 1 of 300
        assert.are.equal("100 %", rows[6303].cells[3]) -- 299 of 300 rounds up
        assert.truthy(tiplines.lines(rows[6358].tip)[3]:find("^Share of catches = <1 %% %("))
    end)

    it("writes the record lines of a scope", function()
        local totals = Totals.New()
        for i = 1, 40 do
            Totals.Add(
                totals,
                { t = HOUR5 + i * 20, map = 1411, out = "catch", loot = { { id = 6303 } } }
            )
        end
        local chars = {
            ["Player-1"] = {
                name = "Alice",
                totals = totals,
                sessions = {
                    {
                        start = HOUR5,
                        last = HOUR5 + 800,
                        ended = HOUR5 + 800,
                        endReason = "idle",
                        casts = 40,
                        catches = 40,
                        active = 780,
                        counts = { catch = 40 },
                        zones = { 1411 },
                    },
                },
            },
        }
        local model = StatsModel.Overview({ chars = chars, current = "Player-1", now = HOUR5 })
        local date = os.date("!%Y-%m-%d", HOUR5)
        assert.are.same({
            "Most catches in a session: 40 (Alice, " .. date .. ", Durotar)",
            "Most catches per hour: 171 (Alice, " .. date .. ", Durotar)",
            "Longest session: 14 min active (Alice, " .. date .. ", Durotar)",
        }, ns.OverviewTable.Records(model, input()))
        model = StatsModel.Overview({ chars = {}, now = HOUR5 })
        assert.are.same({}, ns.OverviewTable.Records(model, input()))
    end)
end)
