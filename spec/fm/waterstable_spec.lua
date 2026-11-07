-- Waters tab builder (WatersTable.lua) on the generated zone data: the color bands at their edges,
-- the subzone base override (Jaguero Isle 205 in Stranglethorn Vale 130), one row per area with
-- subzones under their zone and dungeons last, own casts and catches per resolved area, places
-- without reference data, the "fishable now" filter, and the sort by skill.
local addon = require("spec.helpers.addon")

local NAMES = {
    [14] = "Durotar",
    [367] = "Sen'jin Village",
    [33] = "Stranglethorn Vale",
    [297] = "Jaguero Isle",
}

describe("FishingMastery waters table", function()
    local ns, WatersTable, areas

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleJournal.lua",
            "Data\\Zones.lua",
            "Data\\Journal.lua",
            "Area.lua",
            "JournalModel.lua",
            "WatersTable.lua",
        }, nil, "FishingMastery")
        WatersTable = ns.WatersTable
        areas = ns.Area.New(ns.Zones, function(id)
            return NAMES[id]
        end)
    end)

    local function input(skill, view)
        local index = ns.JournalModel.Index(ns.Journal, ns.Zones, areas)
        return {
            zones = ns.Zones,
            areas = areas,
            view = view or { maps = {}, subs = {} },
            skill = skill,
            groupOf = index.groupOf,
            areaName = function(area)
                return NAMES[area] or ("Area " .. area)
            end,
            mapName = function(map)
                return ({ [1949] = "Mount Hyjal" })[map]
            end,
        }
    end

    local function byKey(rows)
        local out = {}
        for i, row in ipairs(rows) do
            row.index = i
            out[row.key] = row
        end
        return out
    end

    it("colors a water by the effective skill at the band edges", function()
        local Band = WatersTable.Band
        assert.are.same(
            { "red", "orange", "orange", "green" },
            { Band(129, 130), Band(130, 130), Band(224, 130), Band(225, 130) }
        )
        assert.are.equal("green", Band(25, -70))
        assert.is_nil(Band(nil, 130))
        assert.is_nil(Band(150, nil))
    end)

    it("lists every area with subzones under their zone and the subzone base", function()
        local rows = WatersTable.Rows(input(210), {})
        assert.are.equal(136, #rows)
        local rows2 = byKey(rows)
        local stv, jaguero = rows2["33"], rows2["297"]
        assert.are.same({ "orange", 130 }, { stv.band, stv.base })
        assert.are.same({ "orange", 205 }, { jaguero.band, jaguero.base })
        assert.are.equal("    Jaguero Isle", jaguero.cells[1])
        assert.are.same({ "205", "300" }, { jaguero.cells[2], jaguero.cells[3] })
        assert.is_true(jaguero.index > stv.index)
        local durotar = rows2["14"]
        assert.are.same(
            { "Durotar", "1", "25" },
            { durotar.cells[1], durotar.cells[2], durotar.cells[3] }
        )
        assert.are.equal("green", durotar.band)
        assert.are.same(WatersTable.COLORS.green, durotar.color)
        assert.truthy(rows[#rows].cells[1]:find("(dungeon)", 1, true))
        assert.are.equal("1", durotar.cells[4]) -- Raw Slitherskin Mackerel (98 %)
        local unknown = WatersTable.Rows(input(nil), {})[1]
        assert.is_nil(unknown.band)
        assert.is_nil(unknown.color)
    end)

    it("counts own casts per resolved area and lists places without data", function()
        local view = {
            maps = { [1411] = { casts = 5, catches = 3 }, [1949] = { casts = 2, catches = 1 } },
            subs = {
                [1411] = {
                    ["Sen'jin Village"] = { casts = 3, outcomes = { catch = 2 } },
                    [""] = { casts = 2, outcomes = { catch = 1 } },
                },
            },
        }
        local rows = byKey(WatersTable.Rows(input(50, view), {}))
        assert.are.same({ "5", "3" }, { rows["14"].cells[5], rows["14"].cells[6] })
        assert.are.same({ "3", "2" }, { rows["367"].cells[5], rows["367"].cells[6] })
        local none = rows.map1949
        assert.are.same({ "Mount Hyjal (no reference data)", "-", "-", "-", "2", "1" }, none.cells)
    end)

    it("keeps only fishable waters with the filter and sorts by skill", function()
        local rows = WatersTable.Rows(input(150), { fishable = true })
        for _, row in ipairs(rows) do
            assert.is_true(row.band == "orange" or row.band == "green", row.name)
        end
        local all = #WatersTable.Rows(input(150), {})
        assert.is_true(#rows < all)
        local sorted = WatersTable.Rows(input(150), { sort = "base" })
        local last = -1000
        for _, row in ipairs(sorted) do
            if row.kind == "zone" then
                assert.is_true(row.base == nil or row.base >= last, row.name)
                last = row.base or last
            end
        end
        local selected = WatersTable.Rows(input(150), { selected = "14" })
        assert.is_true(byKey(selected)["14"].selected)
        assert.are.equal(
            "Colors for your effective skill 150: red = no catch, orange = some fish get away, "
                .. "green = no getaways (Classic model).",
            WatersTable.Legend(150)
        )
    end)
end)
