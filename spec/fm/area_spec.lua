-- Area lookup (Area.lua) on the generated zone data: coastal subzone, inland zone, empty
-- subzone text, unknown Forever zone, dungeon, a name used in two zones, no C_Map.GetAreaInfo,
-- the name cache, and the Zones tab rows grouped by resolved area (past records resolve through
-- the same lookup, from the map and subzone text they already hold).
local addon = require("spec.helpers.addon")

-- English client names of the subzones used below (the client export names).
local NAMES = {
    [367] = "Sen'jin Village",
    [814] = "Southfury River",
    [815] = "Southfury River",
    [2979] = "Tor'kren Farm",
    [297] = "Jaguero Isle",
    [305] = "North Tide's Run",
}

describe("FishingMastery area lookup", function()
    local ns, Area, calls

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleUI.lua",
            "Style.lua",
            "LocaleStats.lua",
            "Data\\Zones.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Session.lua",
            "Options.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "RowTip.lua",
            "StatsView.lua",
            "StatsTables.lua",
            "ZoneTable.lua",
            "Area.lua",
        }, nil, "FishingMastery")
        calls = 0
        Area = ns.Area.New(ns.Zones, function(id)
            calls = calls + 1
            return NAMES[id]
        end)
    end)

    it("finds a coastal subzone by its client name", function()
        assert.are.equal(367, Area:Resolve(1411, "Sen'jin Village")) -- Durotar
        assert.are.equal(305, Area:Resolve(1421, "North Tide's Run")) -- Silverpine
        assert.are.equal(297, Area:Resolve(1434, "Jaguero Isle")) -- Stranglethorn Vale
        assert.is_true(Area:IsSubzone(367))
        assert.are.same({ list = Area:Info(367).list, zone = 14 }, Area:Info(367))
    end)

    it("gives the zone inland, for subzones without data, and without subzone text", function()
        assert.are.equal(14, Area:Resolve(1411, "Razor Hill")) -- a village without own data
        assert.are.equal(14, Area:Resolve(1411, ""))
        assert.are.equal(14, Area:Resolve(1411, nil))
        assert.are.equal(130, Area:Resolve(1421, "The Shining Strand"))
        assert.is_false(Area:IsSubzone(14))
    end)

    it("does not know Forever zones or places without a map", function()
        assert.is_nil(Area:Resolve(9999, "Somewhere"))
        assert.is_nil(Area:Resolve(nil, "Sen'jin Village"))
        assert.is_nil(Area:Resolve("1411", nil))
        assert.is_nil(Area:Info(nil))
        assert.is_false(Area:IsSubzone(nil))
    end)

    it("finds dungeons by instance ID before the map", function()
        assert.are.equal(1581, Area:Resolve(nil, "", 36)) -- The Deadmines
        assert.are.equal(718, Area:Resolve(1413, "Wailing Caverns", 43))
        -- The open world gives the continent ID, which is no dungeon.
        assert.are.equal(14, Area:Resolve(1411, nil, 1))
    end)

    it("matches a name used in two zones inside the current zone only", function()
        assert.are.equal(814, Area:Resolve(1411, "Southfury River")) -- Durotar
        assert.are.equal(815, Area:Resolve(1413, "Southfury River")) -- The Barrens
    end)

    it("needs the exact bytes", function()
        assert.are.equal(14, Area:Resolve(1411, "Sen\226\128\153jin Village"))
        assert.are.equal(14, Area:Resolve(1411, "sen'jin village"))
    end)

    it("reads the names once per zone", function()
        Area:Resolve(1411, "Sen'jin Village")
        local first = calls
        assert.are.equal(#ns.Zones.children[14], first)
        Area:Resolve(1411, "Southfury River")
        Area:Resolve(1411, "Razor Hill")
        assert.are.equal(first, calls)
    end)

    it("falls back to the zone without C_Map.GetAreaInfo", function()
        local none = ns.Area.New(ns.Zones, function()
            return nil
        end)
        assert.are.equal(14, none:Resolve(1411, "Sen'jin Village"))
        local missing = ns.Area.New(ns.Zones, nil)
        assert.are.equal(14, missing:Resolve(1411, "Sen'jin Village"))
        assert.are.equal(1581, missing:Resolve(nil, nil, 36))
        local empty = ns.Area.New(nil, nil)
        assert.is_nil(empty:Resolve(1411, "Sen'jin Village"))
    end)

    local function group(casts, catches, item)
        return {
            casts = casts,
            active = casts * 20,
            outcomes = { catch = catches, getaway = casts - catches },
            items = { [item] = catches },
        }
    end

    local function input(areas)
        return {
            info = function()
                return {}
            end,
            mapName = function(map)
                return ({ [1411] = "Durotar", [9999] = "Forever Isle" })[map]
            end,
            areas = areas,
        }
    end

    it("groups the Zones tab by resolved area", function()
        local view = {
            subs = {
                [1411] = {
                    ["Sen'jin Village"] = group(30, 25, 6291),
                    ["Razor Hill"] = group(10, 8, 6303),
                    [""] = group(5, 5, 6303),
                },
                [9999] = { ["New Bay"] = group(4, 4, 99999) },
            },
        }
        local rows = ns.ZoneTable.Rows(view, input(Area))
        local found = {}
        for _, row in ipairs(rows) do
            found[#found + 1] = { row.cells[1], row.area }
        end
        assert.are.same({
            { "Durotar", 14 },
            { "    Sen'jin Village", 367 },
            { "    Razor Hill", 14 },
            { "    (no subzone)", 14 },
            { "Forever Isle", nil },
            { "    New Bay", nil },
        }, found)
        assert.are.equal("0001411/#367", rows[2].key:sub(3))

        -- Without a resolver the rows stay per subzone text, without areas.
        local plain = ns.ZoneTable.Rows(view, input(nil))
        assert.are.equal("    Sen'jin Village", plain[2].cells[1])
        assert.is_nil(plain[2].area)
    end)

    it("merges texts of one area into one row", function()
        -- A resolver that maps two texts to the same subzone (e.g. a renamed subzone).
        local stub = {
            Resolve = function(_, _, text)
                return (text == "Old Name" or text == "New Name") and 367 or 14
            end,
            IsSubzone = function(_, area)
                return area == 367
            end,
        }
        local view = {
            subs = { [1411] = { ["Old Name"] = group(6, 3, 1), ["New Name"] = group(4, 4, 2) } },
        }
        local rows = ns.ZoneTable.Rows(view, input(stub))
        assert.are.equal(2, #rows)
        assert.are.same({ "    New Name", "10" }, { rows[2].cells[1], rows[2].cells[2] })
        assert.are.equal(367, rows[2].area)
    end)
end)
