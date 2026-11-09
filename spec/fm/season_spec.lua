-- Season windows, realm offset, and the hour histogram (Season.lua, Totals.Civil), and the month
-- counts per item (Totals, StatsView).
local addon = require("spec.helpers.addon")

local HOUR, DAY = 3600, 86400

describe("FishingMastery seasons and day/night", function()
    local ns, Season, J

    before_each(function()
        ns = addon.load({
            "Locale.lua",
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
            "Getaway.lua",
            "StatsView.lua",
            "StatsTables.lua",
            "ZoneTable.lua",
            "ZoneRef.lua",
            "Hud.lua",
        }, { Commands = { Register = function() end } }, "FishingMastery")
        Season, J = ns.Season, ns.Journal
    end)

    -- Server time of a date at an hour (UTC).
    local function at(year, month, day, hour)
        return Season.Days(year, month, day) * DAY + (hour or 0) * HOUR
    end

    it("converts between day numbers and dates", function()
        assert.are.equal(0, Season.Days(1970, 1, 1))
        local dates = { { 2024, 2, 29 }, { 2026, 11, 7 }, { 2000, 3, 1 }, { 2100, 12, 31 } }
        for _, date in ipairs(dates) do
            assert.are.same(date, { ns.Totals.Civil(Season.Days(date[1], date[2], date[3])) })
        end
        assert.are.equal(Season.Days(2024, 3, 1) - 1, Season.Days(2024, 2, 29))
    end)

    it("keeps the Classic season windows at their edges (20/21 Mar, 23/24 Sep)", function()
        local winter, summer = J.seasons[13755], J.seasons[13756]
        -- Winter from 23 Sep 01:00 for 178 days: to 20 Mar 01:00 in a year without 29 Feb.
        assert.is_false(Season.InSeason(winter, at(2026, 9, 23, 0)))
        assert.is_true(Season.InSeason(winter, at(2026, 9, 23, 1)))
        assert.is_true(Season.InSeason(winter, at(2027, 1, 15, 12)))
        assert.is_true(Season.InSeason(winter, at(2027, 3, 20, 0)))
        assert.is_false(Season.InSeason(winter, at(2027, 3, 20, 1)))
        assert.is_false(Season.InSeason(winter, at(2027, 3, 21, 12)))
        -- Summer from 21 Mar 01:00 for 187 days: to 24 Sep 01:00.
        assert.is_false(Season.InSeason(summer, at(2027, 3, 21, 0)))
        assert.is_true(Season.InSeason(summer, at(2027, 3, 21, 1)))
        assert.is_true(Season.InSeason(summer, at(2027, 9, 23, 12))) -- one day with both
        assert.is_true(Season.InSeason(winter, at(2027, 9, 23, 12)))
        assert.is_true(Season.InSeason(summer, at(2027, 9, 24, 0)))
        assert.is_false(Season.InSeason(summer, at(2027, 9, 24, 1)))
        -- Neither between 20 Mar 01:00 and 21 Mar 01:00.
        local gap = at(2027, 3, 20, 12)
        assert.are.same(
            { false, false },
            { Season.InSeason(winter, gap), Season.InSeason(summer, gap) }
        )
        -- Realm time: UTC 23:30 on 20 Mar is 00:30 on 21 Mar at +1 (summer not yet), 02:30 at +3.
        local late = at(2027, 3, 20, 23) + 1800
        assert.is_false(Season.InSeason(summer, late, 1))
        assert.is_true(Season.InSeason(summer, late, 3))
    end)

    it("finds the realm offset and counts catches by realm hour", function()
        assert.are.equal(0, Season.Offset(nil, 100))
        assert.are.equal(1, Season.Offset(13, at(2026, 11, 7, 12)))
        assert.are.equal(-8, Season.Offset(4, at(2026, 11, 7, 12)))
        assert.are.equal(-1, Season.Offset(23, at(2026, 11, 7, 0)))
        local hours, total = Season.Hours({ [0] = 2, [5] = 1, [23] = 4, x = 9 }, -1)
        assert.are.equal(7, total)
        assert.are.same({ 2, 1, 4, 0 }, { hours[23], hours[4], hours[22], hours[0] })
        local empty, none = Season.Hours(nil, 0)
        assert.are.same({ 0, 0 }, { none, empty[12] })
    end)

    it("counts an item's catches by month and merges them across characters", function()
        local a, b = ns.Totals.New(), ns.Totals.New()
        local function catch(totals, t)
            ns.Totals.Add(totals, { t = t, map = 1411, out = "catch", loot = { { id = 13755 } } })
        end
        catch(a, at(2026, 1, 31, 23))
        catch(a, at(2026, 2, 1, 0))
        catch(b, at(2026, 2, 14, 8))
        assert.are.same({ [1] = 1, [2] = 1 }, a.items[13755].months)
        local view =
            ns.StatsView.Build({ { totals = a, subzones = {} }, { totals = b, subzones = {} } })
        assert.are.same({ [1] = 1, [2] = 2 }, view.items[13755].months)
    end)
end)
