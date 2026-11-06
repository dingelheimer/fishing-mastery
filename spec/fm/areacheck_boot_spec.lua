-- Boot tests for the area API check (/fm dev area): dev flag only, every API missing (the boot
-- harness has only C_Map.GetBestMapForUnit and GetSubZoneText), every API present with the
-- byte-exact name match, secret values, raising APIs, the run cap, and clear.
local fmboot = require("spec.helpers.fmboot")

-- Globals the stubs set beyond the harness; removed after each test.
local AREA_STUBS = {
    "C_MapExplorationInfo",
    "GetZoneText",
    "GetRealZoneText",
    "GetMinimapZoneText",
    "GetInstanceInfo",
    "issecretvalue",
}

-- English names of the client export, keyed by area ID (a few test areas left out on purpose).
local NAMES = {
    [14] = "Durotar",
    [367] = "Sen'jin Village",
    [362] = "Razor Hill",
    [814] = "Southfury River",
    [815] = "Southfury River",
    [1637] = "Orgrimmar",
}

local function stubAll(w, spot)
    _G.C_Map.GetMapInfo = function(map)
        return { mapID = map, name = "Durotar", mapType = 3 }
    end
    _G.C_Map.GetAreaInfo = function(id)
        return NAMES[id]
    end
    _G.C_Map.GetPlayerMapPosition = function(map, unit)
        assert.are.equal("player", unit)
        assert.are.equal(1411, map)
        return {
            GetXY = function()
                return 0.67891, 0.12345
            end,
        }
    end
    _G.C_MapExplorationInfo = {
        GetExploredAreaIDsAtPosition = function(map, pos)
            assert.are.equal(1411, map)
            assert.are.equal("function", type(pos.GetXY))
            return spot.areas
        end,
    }
    _G.GetZoneText = function()
        return "Durotar"
    end
    _G.GetRealZoneText = function()
        return "Durotar"
    end
    _G.GetMinimapZoneText = function()
        return spot.minimap
    end
    _G.GetInstanceInfo = function()
        return "Kalimdor", "none", 0, "", 0, 0, false, 1
    end
    w.game.map = 1411
    w.game.subzone = spot.subzone
end

local function lastRun()
    local runs = _G.FishingMasteryDB.dev.area.runs
    return runs[#runs]
end

describe("FishingMastery area check boot", function()
    local w

    before_each(function()
        w = fmboot.new()
        w.boot({ schemaVersion = 1, chars = {}, settings = { dev = true } }, nil)
    end)

    after_each(function()
        for _, name in ipairs(AREA_STUBS) do
            _G[name] = nil
        end
        w.cleanup()
    end)

    it("is a dev command only", function()
        _G.FishingMasteryDB.settings.dev = nil
        _G.SlashCmdList.FM("dev area")
        assert.truthy(w.output():find("Unknown command: dev", 1, true))
        assert.is_nil(_G.FishingMasteryDB.dev)
    end)

    it("reports every missing API without Lua errors", function()
        w.game.map, w.game.subzone = 1411, "Sen'jin Village"
        _G.SlashCmdList.FM("dev area")
        local run = lastRun()
        assert.are.equal(w.serverTime, run.at)
        assert.are.equal(1411, run.map)
        assert.are.equal("Sen'jin Village", run.subzone)
        assert.is_nil(run.here)
        assert.are.equal(#w.ns.AreaCheck.TEST_AREAS, #run.tests)
        for _, entry in ipairs(run.tests) do
            assert.is_nil(entry.name)
        end
        assert.are.same({
            "C_Map.GetMapInfo",
            "C_Map.GetAreaInfo",
            "C_Map.GetPlayerMapPosition",
            "C_MapExplorationInfo.GetExploredAreaIDsAtPosition",
            "GetZoneText",
            "GetRealZoneText",
            "GetMinimapZoneText",
            "GetInstanceInfo",
        }, run.missing)
        local out = w.output()
        assert.truthy(out:find("Area check (run 1 of at most 30 kept", 1, true))
        assert.truthy(out:find('subzone "Sen\'jin Village"', 1, true))
        assert.truthy(out:find("Test areas: 0 of 26 named, 0 with the English name", 1, true))
        assert.truthy(out:find("Missing APIs: C_Map.GetMapInfo, C_Map.GetAreaInfo", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("reads every API and flags byte-exact name matches", function()
        stubAll(w, { subzone = "Sen'jin Village", minimap = "Sen'jin Village", areas = { 367 } })
        _G.SlashCmdList.FM("dev area")
        local run = lastRun()
        assert.are.same({}, run.missing)
        assert.are.equal("Durotar", run.mapName)
        assert.are.equal(3, run.mapType)
        assert.are.equal("none", run.instanceType)
        assert.are.equal(1, run.instanceID)
        assert.are.same({
            x = 0.679,
            y = 0.123,
            areas = { { id = 367, name = "Sen'jin Village", subzone = true } },
        }, run.here)
        local byId = {}
        for _, entry in ipairs(run.tests) do
            byId[entry.id] = entry
        end
        assert.are.same(
            { id = 367, name = "Sen'jin Village", subzone = true, english = true },
            byId[367]
        )
        assert.are.same({ id = 14, name = "Durotar", zone = true, english = true }, byId[14])
        assert.are.same({ id = 362, name = "Razor Hill", english = true }, byId[362])
        assert.are.same({ id = 297 }, byId[297])
        local out = w.output()
        assert.truthy(out:find('Map: 1411 "Durotar", type 3', 1, true))
        assert.truthy(out:find("Instance: type none, ID 1", 1, true))
        assert.truthy(out:find("Areas at 0.679, 0.123: 367 Sen'jin Village =sub", 1, true))
        assert.truthy(
            out:find(
                "Test areas: 6 of 26 named, 6 with the English name; same text: 14 Durotar =zone, "
                    .. "367 Sen'jin Village =sub",
                1,
                true
            )
        )
        assert.truthy(out:find("Missing APIs: -", 1, true))

        -- Different bytes (a typographic apostrophe) do not match.
        w.game.subzone = "Sen\226\128\153jin Village"
        _G.SlashCmdList.FM("dev area")
        assert.is_nil(lastRun().here.areas[1].subzone)
        assert.are.equal(2, #_G.FishingMasteryDB.dev.area.runs)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("handles a spot with no subzone text and a name used in two zones", function()
        stubAll(w, { subzone = "", minimap = "Durotar", areas = { 814, 14 } })
        _G.SlashCmdList.FM("dev area")
        local run = lastRun()
        assert.are.equal("", run.subzone)
        assert.are.same({ id = 814, name = "Southfury River" }, run.here.areas[1])
        assert.are.same({ id = 14, name = "Durotar", zone = true }, run.here.areas[2])

        w.game.subzone = "Southfury River"
        _G.SlashCmdList.FM("dev area")
        local tests = lastRun().tests
        assert.is_true(tests[4].subzone)
        assert.is_true(tests[5].subzone)
        assert.truthy(
            w.output():find("814 Southfury River =sub, 815 Southfury River =sub", 1, true)
        )
    end)

    it("skips secret values and raising APIs", function()
        local secret = {}
        _G.issecretvalue = function(value)
            return value == secret
        end
        -- issecretvalue is cached at file load, so reload the addon with it in place (the boot
        -- resets the harness stubs, so the area stubs follow it).
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
        stubAll(w, { subzone = "Razor Hill", minimap = "Razor Hill", areas = { "bad", 362 } })
        _G.GetZoneText = function()
            return secret
        end
        _G.C_Map.GetAreaInfo = function(id)
            if id == 14 then
                error("area failed")
            end
            return NAMES[id]
        end
        _G.GetInstanceInfo = function()
            error("no instance info")
        end
        _G.SlashCmdList.FM("dev area")
        local run = lastRun()
        assert.is_nil(run.zone)
        assert.is_nil(run.instanceType)
        assert.are.same({ { id = 362, name = "Razor Hill", subzone = true } }, run.here.areas)
        assert.is_nil(run.tests[1].name)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("keeps at most CAP runs and clears them", function()
        local cap = w.ns.AreaCheck.CAP
        for _ = 1, cap + 2 do
            _G.SlashCmdList.FM("dev area")
        end
        local runs = _G.FishingMasteryDB.dev.area.runs
        assert.are.equal(cap, #runs)
        assert.truthy(w.output():find("run 30 of at most 30 kept", 1, true))
        _G.SlashCmdList.FM("dev area clear")
        assert.are.same({ runs = {} }, _G.FishingMasteryDB.dev.area)
        assert.truthy(w.output():find("Area check runs removed.", 1, true))

        -- A broken saved table is replaced instead of raising.
        _G.FishingMasteryDB.dev.area = "broken"
        _G.SlashCmdList.FM("dev area")
        assert.are.equal(1, #_G.FishingMasteryDB.dev.area.runs)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("shows the resolved area in the check and the HUD dev line", function()
        stubAll(w, { subzone = "Sen'jin Village", minimap = "Sen'jin Village", areas = { 367 } })
        _G.SlashCmdList.FM("dev area")
        assert.are.equal(367, lastRun().resolved)
        assert.truthy(w.output():find("Area lookup: 367", 1, true))
        local Hud = w.ns.Hud
        assert.are.equal("Dev: area 367 Sen'jin Village (subzone)", Hud.DevAreaLine(_G, w.ns.area))

        w.game.subzone = "Razor Hill" -- no own data: the zone
        assert.are.equal("Dev: area 14 Durotar (zone)", Hud.DevAreaLine(_G, w.ns.area))
        -- Getaway risk at skill 11 (+ 0) in Durotar (base -70): catch 86 %; no hooked casts yet.
        assert.are.same(
            { "Getaway risk at skill 11: 14 % (Classic model; none from skill 25)" },
            Hud.DevRiskLines(_G, w.ns.area, w.ns.char, nil)
        )

        _G.GetInstanceInfo = function()
            return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36
        end
        assert.are.equal("Dev: area 1581 ? (dungeon)", Hud.DevAreaLine(_G, w.ns.area))

        w.game.map = 9999
        _G.GetInstanceInfo = nil
        assert.are.equal("Dev: no area data here", Hud.DevAreaLine(_G, w.ns.area))
        assert.are.same(
            { "Getaway risk at skill 11: unknown (no Classic base level here)" },
            Hud.DevRiskLines(_G, w.ns.area, w.ns.char, nil)
        )
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
