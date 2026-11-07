-- The HUD zone line's data at the current spot: the resolved area and its client name (the map
-- name without data), the getaway risk at the effective skill (Getaway.lua) with the own rate of
-- this area, and the own catches where the area's Classic list applies (ZoneRef.lua). Also the
-- dev flag readout of the area lookup. Reads the game through Context; the numbers come from the
-- character's totals.
local _, ns = ...

local format = string.format
local L, Context, Getaway, ZoneRef = ns.L, ns.Context, ns.Getaway, ns.ZoneRef

local HudZone = {}
ns.HudZone = HudZone

local mapNames = {} -- [map] = client name or false, read once per login

local function mapName(env, map)
    if map == nil then
        return nil
    end
    if mapNames[map] == nil then
        mapNames[map] = Context.MapName(env, map) or false
    end
    return mapNames[map] or nil
end

-- { area, name, rows (Classic list or nil), items (own catches there), risk (nil without a
-- fishing rank), text and fish (the two HUD lines), tips (risk lines for the tooltip) }. char:
-- the character entry; areas: the Area resolver (nil: no zone data loaded).
function HudZone.Read(env, areas, char, t)
    local map = Context.CurrentMap(env)
    local area = Context.CurrentArea(env, areas)
    local view = ns.StatsView.Build({ char or {} })
    local rank, modifier = Context.Fishing(env)
    local risk
    if rank then
        local bands = area and Getaway.ByArea(view, areas)[area]
        risk = Getaway.Risk(bands, rank + (modifier or 0), areas and areas:Base(area), t)
    end
    local rows, listArea
    if areas then
        rows, _, listArea = areas:List(area)
    end
    local own = ZoneRef.Own(view, areas, map, rows and listArea or nil)
    local zone = {
        area = area,
        name = Context.AreaName(env, area) or mapName(env, map),
        rows = rows or nil,
        items = own.items,
        risk = risk,
    }
    zone.text, zone.fish = ZoneRef.HudLine(zone)
    zone.tips = risk and Getaway.Lines(risk) or {}
    return zone
end

-- Dev flag only: the area the lookup resolves at the current spot, for the in-game check.
function HudZone.DevAreaLine(env, areas)
    local area = Context.CurrentArea(env, areas)
    if not area then
        return L.HUD_DEV_NO_AREA
    end
    local info = areas:Info(area) or {}
    local kind = info.instance and L.HUD_DEV_DUNGEON
        or info.zone and L.HUD_DEV_SUBZONE
        or L.HUD_DEV_ZONE
    return format(L.HUD_DEV_AREA, area, Context.AreaName(env, area) or "?", kind)
end
