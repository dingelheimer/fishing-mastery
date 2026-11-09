-- Classic reference next to own catches (ZoneRef.lua) on the generated zone data: the list that
-- applies in an area, the own group per area, the comparison rows (Classic estimate, season and
-- quest flags, own share, fish not in the Classic data), the note (partial lists, places without
-- data), the selected Zones row, and the HUD zone line.
local addon = require("spec.helpers.addon")
local tiplines = require("spec.helpers.tiplines")

local NAMES = { [297] = "Jaguero Isle", [367] = "Sen'jin Village", [305] = "North Tide's Run" }

describe("FishingMastery zone reference", function()
    local ns, ZoneRef, Area

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
            "Options.lua",
            "OptionsControls.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "RowTip.lua",
            "Getaway.lua",
            "StatsView.lua",
            "StatsTables.lua",
            "ZoneTable.lua",
            "ZoneRef.lua",
            "Area.lua",
        }, nil, "FishingMastery")
        ZoneRef = ns.ZoneRef
        Area = ns.Area.New(ns.Zones, function(id)
            return NAMES[id]
        end)
    end)

    local function info(id)
        return { name = "Item " .. id }
    end

    local function group(items, catches, casts)
        return {
            casts = casts or catches,
            outcomes = { catch = catches },
            items = items,
            active = 60,
        }
    end

    -- Durotar (map 1411): open water, Sen'jin Village (own list), Razor Hill (no own data).
    local function view()
        return {
            subs = {
                [1411] = {
                    [""] = group({ [6303] = 8 }, 8),
                    ["Razor Hill"] = group({ [6303] = 3, [6358] = 1 }, 4),
                    ["Sen'jin Village"] = group({ [6291] = 5 }, 5),
                },
                [9999] = { [""] = group({ [6303] = 2 }, 2) },
            },
        }
    end

    it("finds the list that applies in an area", function()
        local rows, entry, listArea = Area:List(367)
        assert.are.equal(ns.Zones.lists[1], rows)
        assert.are.equal(367, listArea)
        assert.are.equal(1, entry.list)
        -- A subzone without its own list uses the zone's.
        assert.are.equal(14, Area:ListArea(14))
        assert.is_nil(Area:List(nil))
        assert.is_true(Area:Uses(14, 14))
        assert.is_false(Area:Uses(367, 14))
        assert.is_false(Area:Uses(nil, nil))
    end)

    it("sums the own catches of an area and of places without data", function()
        local zone = ZoneRef.Own(view(), Area, 1411, 14)
        assert.are.same({ [6303] = 11, [6358] = 1 }, zone.items) -- open water + Razor Hill
        assert.are.equal(12, zone.outcomes.catch)
        local senjin = ZoneRef.Own(view(), Area, 1411, 367)
        assert.are.same({ [6291] = 5 }, senjin.items)
        local unknown = ZoneRef.Own(view(), Area, 9999, nil)
        assert.are.same({ [6303] = 2 }, unknown.items)
    end)

    it("compares the Classic list with own shares and marks fish not in it", function()
        local rows = ZoneRef.Rows(Area:List(14), ZoneRef.Own(view(), Area, 1411, 14), {
            info = info,
        })
        -- Durotar: 6303 98 %, 6356 2 %, then 6358 caught but not listed.
        assert.are.same({ "Item 6303", "98 %", "", "92 %", "11" }, rows[1].cells)
        assert.are.same({ "Item 6356", "2 %", "", "-", "0" }, rows[2].cells)
        assert.are.same({ "Item 6358", "not in Classic data", "", "8 %", "1" }, rows[3].cells)
        assert.are.equal("Classic estimate = 98 %", tiplines.lines(rows[1].tip)[2])
        assert.are.equal("not in Classic data", tiplines.lines(rows[3].tip)[3])
    end)

    it("flags seasons, quest rows, extra rolls, and decimal chances", function()
        local rows = ZoneRef.Rows(Area:List(297), group({}, 0), { info = info })
        local byId = {}
        for _, row in ipairs(rows) do
            byId[row.key] = row
        end
        assert.are.equal("Winter", byId["13755"].cells[3])
        assert.are.equal("Summer", byId["13756"].cells[3])
        assert.truthy(tiplines.text(byId["13755"].tip):find("Rolls on its own", 1, true))
        assert.are.equal("58.4 %", byId["8365"].cells[2])
        assert.are.equal("0.06 %", byId["6311"].cells[2])
        rows = ZoneRef.Rows(Area:List(148), group({}, 0), { info = info }) -- Darkshore
        local quest
        for _, row in ipairs(rows) do
            if row.key == "6717" then
                quest = row
            end
        end
        assert.are.equal("Quest only", quest.cells[3])
    end)

    it("marks an own share whose range excludes the Classic estimate", function()
        local own = group({ [6303] = 10, [6356] = 30 }, 40)
        local rows = ZoneRef.Rows(Area:List(14), own, { info = info })
        local tip = tiplines.text(rows[1].tip) -- 6303: 25 % own vs 98 %
        assert.truthy(tip:find("differs from the Classic estimate", 1, true))
    end)

    it("writes the note for partial lists and places without data", function()
        local rows, entry = Area:List(130) -- Silverpine, 45.4 % not covered
        local note = ZoneRef.Note("Silverpine Forest", rows, entry, group({}, 62))
        assert.are.equal(
            "Silverpine Forest: Classic estimate next to your 62 catches here. "
                .. "The Classic data covers only 55 % of a catch.",
            note
        )
        assert.are.equal(
            "Forever Isle: No reference data (new in Forever). Your 2 catches only.",
            ZoneRef.Note("Forever Isle", nil, nil, group({}, 2))
        )
        local own = ZoneRef.Rows(nil, group({ [6303] = 2 }, 2), { info = info })
        assert.are.same({ "Item 6303", "-", "", "2/2", "2" }, own[1].cells)
    end)

    it("builds the comparison of a selected Zones row", function()
        local input = {
            info = info,
            areas = Area,
            mapName = function(map)
                return ({ [1411] = "Durotar" })[map]
            end,
        }
        local zoneRows = ns.ZoneTable.Rows(view(), input)
        local byName = {}
        for _, row in ipairs(zoneRows) do
            byName[row.name] = row
        end
        local detail = ZoneRef.Detail(view(), byName["Sen'jin Village"], input)
        assert.truthy(detail.note:find("^Sen'jin Village: Classic estimate next to your 5 catches"))
        assert.are.equal(8, #detail.rows) -- the 8 listed fish, 6291 among them
        -- Razor Hill has no own data: the Durotar list and the zone's catches.
        detail = ZoneRef.Detail(view(), byName["Razor Hill"], input)
        assert.truthy(detail.note:find("^Durotar: Classic estimate next to your 12 catches"))
        detail = ZoneRef.Detail(view(), nil, input)
        assert.are.equal(0, #detail.rows)
    end)

    it("counts the fish of a list still missing, without quest rows", function()
        -- Quest-only rows are not expected fish.
        local missing, total = ZoneRef.Missing(Area:List(148), {})
        assert.are.equal(#Area:List(148) - 1, total)
        assert.are.equal(total, missing)
    end)
end)
