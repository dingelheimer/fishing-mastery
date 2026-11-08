-- Column sets of the Statistics tables (Story 9.4): the Fish table of Draft 2 and at most seven
-- columns per table, everything else in the row tooltips; every column fits the 772 px the page
-- leaves for a list.
local fmboot = require("spec.helpers.fmboot")

describe("FishingMastery statistics columns", function()
    local w

    before_each(function()
        w = fmboot.new()
        w.boot(nil, nil)
    end)

    after_each(function()
        w.cleanup()
    end)

    local function keys(columns)
        local list = {}
        for i, column in ipairs(columns) do
            list[i] = column.key
        end
        return list
    end

    it("shows the Fish columns of Draft 2 with icon and tags", function()
        local columns = w.ns.StatsTables.FISH_COLUMNS
        assert.are.same({ "name", "n", "share", "expected", "dry", "best" }, keys(columns))
        assert.is_true(columns[1].icon)
        assert.is_true(columns[1].tags)
        for i = 2, 5 do
            assert.is_true(columns[i].right) -- numbers right-aligned
        end
    end)

    it("keeps the Journal tables within their lists", function()
        local ns = w.ns
        local lists = {
            fish = { ns.JournalTable.COLUMNS, ns.JournalTabs.LIST_WIDTH - 20 },
            waters = { ns.WatersTable.COLUMNS, 772 },
            recipes = { ns.RecipeTable.COLUMNS, 772 },
            gear = { ns.GearTable.COLUMNS, 772 },
        }
        for name, list in pairs(lists) do
            local width = 0
            for _, column in ipairs(list[1]) do
                width = width + column.width
            end
            assert.is_true(#list[1] <= 7, name)
            assert.is_true(width <= list[2], name .. " " .. width)
        end
        assert.is_true(ns.JournalTable.COLUMNS[1].icon and ns.JournalTable.COLUMNS[1].tags)
        assert.is_true(ns.RecipeTable.COLUMNS[1].icon and ns.GearTable.COLUMNS[1].icon)
    end)

    it("keeps every Statistics table at seven columns or fewer, within the page width", function()
        local ns = w.ns
        local tables = {
            fish = ns.StatsTables.FISH_COLUMNS,
            zones = ns.ZoneTable.COLUMNS,
            zoneRef = ns.ZoneRef.COLUMNS,
            failures = ns.FailureTable.COLUMNS,
            bites = ns.BiteTable.COLUMNS,
            sessions = ns.SessionTable.COLUMNS,
            compare = ns.CompareTable.COLUMNS,
        }
        for name, columns in pairs(tables) do
            assert.is_true(#columns <= 7, name)
            local width = 0
            for _, column in ipairs(columns) do
                width = width + column.width
            end
            assert.is_true(width <= 772, name .. " " .. width)
        end
    end)
end)
