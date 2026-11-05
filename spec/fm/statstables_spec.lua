-- Table builders of the stats window: Fish (cells, ranges in tooltips, grey small samples, dry
-- streak and expected casts, sorting, quality filter), Zones (zones with their subzones), and the
-- Overview lines and character rows.
local addon = require("spec.helpers.addon")

local DAY = 20763 * 86400
local HOUR5 = DAY + 5 * 3600

describe("FishingMastery stats tables", function()
    local ns, StatsModel, Totals

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "Codec.lua",
            "History.lua",
            "Session.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "SummaryModel.lua",
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
        return StatsModel.View({ { totals = totals, subzones = subzones or {} } })
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

    it("builds the Fish cells with shares, best zone and hour, dates, and dry streaks", function()
        local rows = ns.StatsTables.Fish(fishView(), input())
        assert.are.equal(2, #rows)
        assert.are.equal(6303, rows[1].id) -- most caught first
        local mackerel, oily = byId(rows)[6303], byId(rows)[6358]
        assert.are.same({
            "|T133910:14:14|t |cffffffffRaw Slitherskin Mackerel|r",
            "30",
            "94 %",
            "Durotar",
            "07:00", -- UTC hour 5 shifted by the realm offset of 2
            os.date("!%Y-%m-%d", HOUR5 + 20),
            os.date("!%Y-%m-%d", HOUR5 + 32 * 20),
            "-", -- common items have no dry streak
            "-",
        }, mackerel.cells)
        assert.is_false(mackerel.grey[3])
        -- Oily Blackmouth (uncommon): 2 of 40 fair casts, expected every 20; 20 casts since.
        assert.are.equal("6 %", oily.cells[3])
        assert.are.equal("20", oily.cells[8])
        assert.are.equal("20", oily.cells[9])
        local low, high = ns.Stats.Wilson(2, 32)
        local tip = table.concat(oily.tooltip, "\n")
        assert.truthy(tip:find("Caught 2 times (2 items)", 1, true))
        assert.truthy(
            tip:find(
                string.format(
                    "Share 6 %% of catches (95 %% range %d-%d %%), 2 of 32",
                    math.floor(low * 100 + 0.5),
                    math.floor(high * 100 + 0.5)
                ),
                1,
                true
            )
        )
        assert.truthy(tip:find("Most catches at 07:00 (realm time)", 1, true))
        assert.truthy(tip:find("Expected about every 20 casts (95 % range", 1, true))
        assert.truthy(tip:find("Dry streak: 20 fair casts since the last one", 1, true))
    end)

    it("sorts by any column, filters by quality, and greys small samples", function()
        local fish = fishView()
        local rows = ns.StatsTables.Fish(fish, input({ sort = { key = "name" } }))
        assert.are.equal(6358, rows[1].id) -- Oily before Raw
        rows = ns.StatsTables.Fish(fish, input({ sort = { key = "dry", descending = true } }))
        assert.are.equal(6358, rows[1].id) -- no dry streak sorts last in both orders
        rows = ns.StatsTables.Fish(fish, input({ sort = { key = "dry" } }))
        assert.are.equal(6358, rows[1].id)
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
        assert.are.equal("2/3", row.cells[3]) -- counts only below 10
        assert.is_true(row.grey[3])
        assert.truthy(table.concat(row.tooltip, "\n"):find("2 of 3 catches (too few", 1, true))
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
        local tip = table.concat(rows[1].tooltip, "\n")
        assert.truthy(tip:find("Success rate 80 % (95 % range", 1, true))
        assert.truthy(tip:find("Raw Slitherskin Mackerel|r: Share 100 % of catches", 1, true))
    end)

    it("writes the Overview lines and one row per character", function()
        local totals = Totals.New()
        for i = 1, 40 do
            Totals.Add(
                totals,
                { t = HOUR5 + i * 20, map = 1411, out = "catch", loot = { { id = 6303 } } }
            )
        end
        local old = Totals.New()
        Totals.Add(old, { t = DAY, map = 1412, out = "getaway" })
        old.version = 3
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
            ["Player-2"] = { totals = old },
        }
        local model = StatsModel.Overview({ chars = chars, current = "Player-1", now = HOUR5 })
        local lines = table.concat(ns.OverviewTable.Lines(model, input()), "\n")
        assert.truthy(lines:find("All characters: 41 casts, 40 catches on 1 days", 1, true))
        assert.truthy(lines:find("Success rate 98 % (95 % range", 1, true))
        assert.truthy(lines:find("favorite zone Durotar", 1, true))
        local date = os.date("!%Y-%m-%d", HOUR5)
        assert.truthy(
            lines:find("Most catches in a session: 40 (Alice, " .. date .. ", Durotar)", 1, true)
        )
        assert.truthy(lines:find("Most catches per hour: 171 (Alice", 1, true))
        assert.truthy(lines:find("Longest session: 14 min active (Alice", 1, true))
        assert.truthy(lines:find("1 character(s) were counted by an older version", 1, true))

        local rows = ns.OverviewTable.Rows(model, input())
        assert.are.same({ "Alice (you)", "40", "40", "100 %", "171/h", "Durotar" }, rows[1].cells)
        assert.are.same({ "(unnamed)", "1", "0", "0/1", "-", "Mulgore" }, rows[2].cells)
        assert.is_false(rows[1].grey[4])
        assert.is_true(rows[2].grey[4])
    end)
end)
