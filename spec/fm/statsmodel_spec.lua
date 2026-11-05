-- StatsModel: one-character and merged views of the totals, the favorite zone, and the Overview
-- model with per-character numbers and session records.
local addon = require("spec.helpers.addon")

local DAY = 20763 * 86400

describe("FishingMastery StatsModel", function()
    local ns, StatsModel, Totals

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "Codec.lua",
            "History.lua",
            "Session.lua",
            "Totals.lua",
            "Stats.lua",
            "StatsModel.lua",
        }, nil, "FishingMastery")
        StatsModel, Totals = ns.StatsModel, ns.Totals
    end)

    -- A character entry with totals counted from casts and the given subzone texts.
    local function char(name, casts, subzones, sessions)
        local totals = Totals.New()
        for _, cast in ipairs(casts) do
            Totals.Add(totals, cast)
        end
        subzones, sessions = subzones or {}, sessions or {}
        return { name = name, totals = totals, subzones = subzones, sessions = sessions }
    end

    local function catch(t, map, sub, id, qty)
        local loot = { { id = id, qty = qty or 1 } }
        return { t = t, map = map, sub = sub, out = "catch", loot = loot }
    end

    local function alice()
        return char("Alice", {
            catch(DAY + 3600, 1411, 1, 6303),
            catch(DAY + 3620, 1411, 1, 6303),
            { t = DAY + 3640, map = 1411, sub = 2, out = "getaway" },
            catch(DAY + 3660, 1411, 2, 6358, 2),
            { t = DAY + 3700, map = 1411, out = "cancel" },
        }, { "Darkspear Strand", "Sen'jin Village" })
    end

    local function bob()
        return char("Bob", {
            catch(DAY + 86400 + 100, 1412, 1, 6303),
            catch(DAY + 86400 + 130, 1412, 1, 6303),
            catch(DAY + 86400 + 160, 1411, 1, 6303),
        }, { "Sen'jin Village" })
    end

    it("builds a one-character view with subzones by name and the dry-streak counter", function()
        local view = StatsModel.View({ alice() })
        assert.are.same({ catch = 3, getaway = 1, cancel = 1 }, view.outcomes)
        -- Gaps 20 + 20 + 20 + 40 and 60 for the last cast.
        assert.are.equal(160, view.active)
        assert.are.equal(1, view.dayCount)
        assert.are.equal(2, view.species)
        assert.are.equal(4, view.fair) -- 3 catches and a getaway; the cancel is not fair
        assert.are.equal(2, view.items[6303].fair)
        assert.are.equal(1411, view.items[6358].best)
        local names = {}
        for name in pairs(view.subs[1411]) do
            names[#names + 1] = name
        end
        table.sort(names)
        assert.are.same({ "", "Darkspear Strand", "Sen'jin Village" }, names)
        assert.are.equal(2, view.subs[1411]["Darkspear Strand"].casts)
        assert.are.equal(1, view.subs[1411][""].casts) -- the cancel had no subzone
        assert.are.equal(0, view.stale)
    end)

    it("merges characters: subzones by text, items by first, last, and best zone", function()
        local a, b = alice(), bob()
        local view = StatsModel.View({ a, b })
        assert.are.equal(6, view.outcomes.catch)
        assert.are.equal(2, view.dayCount)
        local mackerel = view.items[6303]
        assert.are.equal(5, mackerel.n)
        assert.are.equal(DAY + 3600, mackerel.first)
        assert.are.equal(DAY + 86400 + 160, mackerel.last)
        -- 1411 has 3 (Alice 2, Bob 1), 1412 has 2.
        assert.are.equal(1411, mackerel.best)
        assert.is_nil(mackerel.fair) -- dry streaks only for one character
        assert.is_nil(view.fair)
        -- Bob's subzone 1 is "Sen'jin Village", Alice's subzone 2: one row.
        local senjin = view.subs[1411]["Sen'jin Village"]
        assert.are.equal(3, senjin.casts) -- Alice's getaway and catch, Bob's catch
        assert.are.equal(2, senjin.outcomes.catch)
        assert.are.equal(2, view.subs[1412]["Sen'jin Village"].casts)
    end)

    it("counts characters with totals from an older version as stale", function()
        local old = char("Old", { catch(DAY, 1411, nil, 6303) })
        old.totals.version = 3
        old.totals.subs = nil
        local view = StatsModel.View({ alice(), old })
        assert.are.equal(1, view.stale)
        assert.are.equal(4, view.outcomes.catch) -- the old totals still count where they can
    end)

    it("picks the favorite zone by catches, then casts, then a known map", function()
        assert.are.equal(1411, StatsModel.Favorite(StatsModel.View({ alice() })))
        local view = {
            maps = {
                [0] = { casts = 50, catches = 40 },
                [1412] = { casts = 9, catches = 3 },
                [1411] = { casts = 10, catches = 3 },
            },
        }
        assert.are.equal(1411, StatsModel.Favorite(view))
        assert.are.equal(0, StatsModel.Favorite({ maps = { [0] = { casts = 1, catches = 0 } } }))
        assert.is_nil(StatsModel.Favorite({ maps = {} }))
    end)

    it("builds the Overview with the account, every character, and records", function()
        local a, b = alice(), bob()
        -- 30 fair casts at 15 s gaps for the per-hour record; a smaller session with more
        -- catches per hour that has too few casts to count.
        a.sessions = {
            {
                start = 1000,
                last = 1435,
                ended = 1435,
                endReason = "idle",
                casts = 30,
                catches = 27,
                active = 435,
                counts = { catch = 27, getaway = 3 },
                zones = { 1411 },
            },
        }
        b.sessions = {
            {
                start = 5000,
                last = 5030,
                ended = 5030,
                endReason = "idle",
                casts = 3,
                catches = 3,
                active = 30,
                counts = { catch = 3 },
                zones = { 1412 },
            },
        }
        local chars = { ["Player-1"] = a, ["Player-2"] = b, ["Player-3"] = { name = "Empty" } }
        local model = StatsModel.Overview({ chars = chars, current = "Player-2", now = 9000 })
        assert.are.equal(8, model.account.casts)
        assert.are.equal(6, model.account.catches)
        assert.are.equal(1411, model.account.favorite)
        assert.are.equal(2, #model.characters) -- a character without casts is left out
        assert.are.equal("Alice", model.characters[1].name) -- most casts first
        assert.is_true(model.characters[2].current)
        assert.are.equal(3, model.characters[2].summary.catches)
        local records = model.records
        assert.are.equal(27, records.catches.value)
        assert.are.equal("Alice", records.catches.name)
        assert.are.equal(1411, records.catches.map)
        -- 27 catches in 435 + 60 s (idle end adds the cap): 196.4 per hour.
        assert.is_true(math.abs(records.perHour.value - 27 * 3600 / 495) < 1e-9)
        assert.are.equal(495, records.active.value)
    end)
end)
