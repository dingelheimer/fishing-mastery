-- Area API check (/fm dev area, dev flag only): reads the zone and area APIs the zone data lookup
-- depends on at the player's current spot and compares the subzone text with the client's area
-- names byte for byte. Missing APIs are reported by name; nothing raises. Every run is printed
-- and appended to FishingMasteryDB.dev.area (capped) for the saved file. No names of players.
local _, ns = ...

local type, format, concat, ipairs, tostring, gmatch, floor, remove =
    type, string.format, table.concat, ipairs, tostring, string.gmatch, math.floor, table.remove
local L = ns.L
local Call = ns.Context.Call
local isSecret = issecretvalue or function()
    return false
end

local AreaCheck = {}
ns.AreaCheck = AreaCheck

AreaCheck.CAP = 30 -- runs kept in dev.area.runs; the oldest is dropped first

-- Global paths the check reads; any that is not a function is listed as missing.
AreaCheck.APIS = {
    "C_Map.GetBestMapForUnit",
    "C_Map.GetMapInfo",
    "C_Map.GetAreaInfo",
    "C_Map.GetPlayerMapPosition",
    "C_MapExplorationInfo.GetExploredAreaIDsAtPosition",
    "GetZoneText",
    "GetRealZoneText",
    "GetSubZoneText",
    "GetMinimapZoneText",
    "GetInstanceInfo",
}

-- AreaTable IDs with their English names in the Forever client export (build 1.60.1.70790).
-- Covers the owner's test spots: coasts with their own fish list, a name used in two zones
-- (Southfury River), capitals, a port, two dungeons, and Silverpine and Tirisfal waters.
AreaCheck.TEST_AREAS = {
    { 14, "Durotar" },
    { 367, "Sen'jin Village" },
    { 362, "Razor Hill" },
    { 814, "Southfury River" }, -- in Durotar
    { 815, "Southfury River" }, -- in The Barrens
    { 2320, "The Great Sea" }, -- Durotar coast
    { 17, "The Barrens" },
    { 392, "Ratchet" },
    { 1637, "Orgrimmar" },
    { 33, "Stranglethorn Vale" },
    { 297, "Jaguero Isle" },
    { 35, "Booty Bay" },
    { 12, "Elwynn Forest" },
    { 18, "Crystal Lake" },
    { 1519, "Stormwind City" },
    { 718, "Wailing Caverns" },
    { 1581, "The Deadmines" },
    { 130, "Silverpine Forest" },
    { 228, "The Sepulcher" },
    { 305, "North Tide's Run" },
    { 1338, "Lordamere Lake" },
    { 2398, "The Great Sea" }, -- Silverpine coast
    { 85, "Tirisfal Glades" },
    { 159, "Brill" },
    { 162, "Brightwater Lake" },
    { 1497, "Undercity" },
}

local function resolve(env, path)
    local value = env
    for key in gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[key]
    end
    return value
end

local function plain(value)
    if isSecret(value) then
        return nil
    end
    return value
end

local function text(value)
    value = plain(value)
    return type(value) == "string" and value or nil
end

local function number(value)
    value = plain(value)
    return type(value) == "number" and value or nil
end

local function round(value)
    return value and floor(value * 1000 + 0.5) / 1000 or nil
end

-- Normalized player position on the map and the area IDs the client reports there.
local function position(env, map)
    if not map then
        return nil
    end
    local pos = Call(env, "C_Map.GetPlayerMapPosition", map, "player")
    if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then
        return nil
    end
    local x, y = Call(pos, "GetXY", pos)
    local here = { x = round(number(x)), y = round(number(y)), areas = {} }
    local ids = Call(env, "C_MapExplorationInfo.GetExploredAreaIDsAtPosition", map, pos)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        id = number(id)
        if id then
            here.areas[#here.areas + 1] = { id = id }
        end
    end
    return here
end

-- Fills name and match flags: subzone (same bytes as GetSubZoneText) and zone (as GetZoneText).
local function name(env, entry, run)
    entry.name = text(Call(env, "C_Map.GetAreaInfo", entry.id))
    if entry.name then
        entry.subzone = entry.name == run.subzone or nil
        entry.zone = entry.name == run.zone or nil
    end
end

local function listNames(list, filter)
    local parts = {}
    for _, entry in ipairs(list) do
        if filter(entry) then
            local marks = (entry.subzone and " =sub" or "") .. (entry.zone and " =zone" or "")
            parts[#parts + 1] = format("%d %s%s", entry.id, entry.name or "?", marks)
        end
    end
    return #parts > 0 and concat(parts, ", ") or "-"
end

-- One run at the current spot; returns the saved entry.
function AreaCheck.Read(env, at)
    local run = { at = at, missing = {} }
    for _, path in ipairs(AreaCheck.APIS) do
        if type(resolve(env, path)) ~= "function" then
            run.missing[#run.missing + 1] = path
        end
    end
    run.map = number(Call(env, "C_Map.GetBestMapForUnit", "player"))
    local info = run.map and Call(env, "C_Map.GetMapInfo", run.map)
    run.mapName = type(info) == "table" and text(info.name) or nil
    run.mapType = type(info) == "table" and number(info.mapType) or nil
    run.zone = text(Call(env, "GetZoneText"))
    run.realZone = text(Call(env, "GetRealZoneText"))
    run.subzone = text(Call(env, "GetSubZoneText"))
    run.minimap = text(Call(env, "GetMinimapZoneText"))
    local instance = { Call(env, "GetInstanceInfo") }
    run.instanceType = text(instance[2])
    run.instanceID = number(instance[8])
    run.here = position(env, run.map)
    for _, entry in ipairs(run.here and run.here.areas or {}) do
        name(env, entry, run)
    end
    run.tests = {}
    for i, test in ipairs(AreaCheck.TEST_AREAS) do
        local entry = { id = test[1] }
        name(env, entry, run)
        entry.english = entry.name == test[2] or nil
        run.tests[i] = entry
    end
    return run
end

local function show(value)
    return value and format("%q", value) or "nil"
end

-- Chat lines for one run.
function AreaCheck.Lines(run)
    local named, english = 0, 0
    for _, entry in ipairs(run.tests) do
        named = named + (entry.name and 1 or 0)
        english = english + (entry.english and 1 or 0)
    end
    local here = run.here
    return {
        format(L.AREA_MAP, tostring(run.map), show(run.mapName), tostring(run.mapType)),
        format(
            L.AREA_TEXT,
            show(run.zone),
            show(run.realZone),
            show(run.subzone),
            show(run.minimap)
        ),
        format(L.AREA_INSTANCE, tostring(run.instanceType), tostring(run.instanceID)),
        format(
            L.AREA_HERE,
            here and tostring(here.x) or "-",
            here and tostring(here.y) or "-",
            listNames(here and here.areas or {}, function()
                return true
            end)
        ),
        format(
            L.AREA_TESTS,
            named,
            #run.tests,
            english,
            listNames(run.tests, function(entry)
                return entry.subzone or entry.zone
            end)
        ),
        format(L.AREA_MISSING, #run.missing > 0 and concat(run.missing, ", ") or "-"),
        format(L.AREA_RESOLVED, tostring(run.resolved)),
    }
end

-- deps: { env, db, serverTime }. Reads the current spot, prints it, appends it to dev.area.runs.
function AreaCheck.Run(deps, action)
    local dev = ns.Stress.Dev(deps.db)
    if type(dev.area) ~= "table" or type(dev.area.runs) ~= "table" then
        dev.area = { runs = {} }
    end
    local runs = dev.area.runs
    if action == "clear" then
        dev.area = { runs = {} }
        ns.Print(L.AREA_CLEARED)
        return
    end
    local run = AreaCheck.Read(deps.env, deps.serverTime())
    run.resolved = ns.Context.CurrentArea(deps.env, ns.area)
    runs[#runs + 1] = run
    while #runs > AreaCheck.CAP do
        remove(runs, 1)
    end
    ns.Print(format(L.AREA_HEADER, #runs, AreaCheck.CAP))
    for _, line in ipairs(AreaCheck.Lines(run)) do
        ns.Print(line)
    end
    return run
end
