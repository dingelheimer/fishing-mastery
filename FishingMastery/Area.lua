-- Pure logic: resolves where the player fishes to an AreaTable ID of the zone data
-- (Data/Zones.lua): a dungeon by its instance ID, else the zone of the UI map, and inside it the
-- subzone whose client name (C_Map.GetAreaInfo, in the client's language) equals the subzone
-- text byte for byte. A subzone without own data, or no subzone text, gives the zone. Places
-- without data give nil. Names are read once per zone and cached. No frame or API calls: the
-- name lookup is injected.
local _, ns = ...

local type, ipairs, setmetatable = type, ipairs, setmetatable

local Area = {}
Area.__index = Area
ns.Area = Area

-- zones: the zone data table (ns.Zones). nameOf(areaID): the client name of an area or nil.
function Area.New(zones, nameOf)
    return setmetatable({
        zones = type(zones) == "table" and zones or {},
        nameOf = nameOf,
        names = {}, -- [zone area] = { [client name] = subzone area }
    }, Area)
end

-- Subzone names of a zone, read once.
function Area:Names(zone)
    local names = self.names[zone]
    if names then
        return names
    end
    names = {}
    local children = self.zones.children and self.zones.children[zone]
    for _, id in ipairs(type(children) == "table" and children or {}) do
        local name = self.nameOf and self.nameOf(id)
        if type(name) == "string" and name ~= "" and names[name] == nil then
            names[name] = id
        end
    end
    self.names[zone] = names
    return names
end

-- Area ID for a UI map ID, subzone text, and instance ID (GetInstanceInfo, 8th return); every
-- argument may be nil. Returns areaID or nil.
function Area:Resolve(map, subzone, instance)
    local zones = self.zones
    local dungeon = type(instance) == "number"
        and zones.instanceToArea
        and zones.instanceToArea[instance]
    if dungeon then
        return dungeon
    end
    local zone = type(map) == "number" and zones.mapToArea and zones.mapToArea[map]
    if not zone then
        return nil
    end
    if type(subzone) == "string" and subzone ~= "" then
        return self:Names(zone)[subzone] or zone
    end
    return zone
end

-- The data entry of an area ({ base, list, merged, partial, zone, instance }) or nil.
function Area:Info(area)
    local areas = self.zones.areas
    return type(area) == "number" and type(areas) == "table" and areas[area] or nil
end

-- True when the area is a subzone with its own entry (not its zone's).
function Area:IsSubzone(area)
    local info = self:Info(area)
    return info ~= nil and info.zone ~= nil
end

-- Fishing base skill of an area: its own, else its zone's (a subzone without a base uses the
-- zone's, as the server does); nil for places without one.
function Area:Base(area)
    local info = self:Info(area)
    if not info then
        return nil
    end
    if type(info.base) == "number" then
        return info.base
    end
    local zone = self:Info(info.zone)
    return zone and type(zone.base) == "number" and zone.base or nil
end
