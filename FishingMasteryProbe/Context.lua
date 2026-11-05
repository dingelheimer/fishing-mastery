-- Cast context snapshot: profession info, pole, lure, auras, location, and time at a cast start.
-- Answers Q07 and Q16-Q19. Reads from an injected environment (_G in game).
local _, ns = ...

local type, pcall, ipairs, min = type, pcall, ipairs, math.min
local isSecret = issecretvalue or function()
    return false
end

local Calls, Redact = ns.Calls, ns.Redact

local Context = {}
ns.Context = Context

Context.MAIN_HAND_SLOT = 16
Context.MAX_AURAS = 40 -- per filter
Context.MAX_MAP_DEPTH = 8
Context.AURA_FIELDS = {
    "spellId",
    "duration",
    "expirationTime",
    "applications",
    "auraInstanceID",
    "isHelpful",
    "isHarmful",
    "sourceUnit",
}

local function plainTable(value)
    return value ~= nil and not isSecret(value) and type(value) == "table"
end

-- Q07: GetProfessions indices and GetProfessionInfo per index.
function Context.Professions(env)
    local list = Calls.Call(env, "GetProfessions")
    local result = { list = list, info = {} }
    if list.ok then
        for i = 1, min(list.n, 8) do
            local index = list.values[i]
            if type(index) == "number" then
                local info = Calls.Call(env, "GetProfessionInfo", index)
                info.index = index
                result.info[i] = info
            end
        end
    end
    return result
end

-- Q18/Q31: player aura spell IDs and timing; other fields (names, icons) are not kept.
function Context.Auras(env, filter)
    local auras = {}
    for i = 1, Context.MAX_AURAS do
        local exists, ok, aura =
            Calls.Invoke(env, "C_UnitAuras.GetAuraDataByIndex", "player", i, filter)
        if not exists or not ok or not plainTable(aura) then
            if isSecret(aura) then
                auras[#auras + 1] = { secret = true }
            end
            break
        end
        local entry = {}
        for _, field in ipairs(Context.AURA_FIELDS) do
            entry[field] = aura[field]
        end
        auras[#auras + 1] = entry
    end
    return auras
end

-- Q19: best map, its parent chain, rounded position, and zone texts.
function Context.Location(env)
    local exists, ok, mapID = Calls.Invoke(env, "C_Map.GetBestMapForUnit", "player")
    local location = {
        exists = exists,
        mapID = ok and mapID or nil,
        chain = {},
        zone = Calls.Call(env, "GetZoneText").values,
        subzone = Calls.Call(env, "GetSubZoneText").values,
        realZone = Calls.Call(env, "GetRealZoneText").values,
        minimapZone = Calls.Call(env, "GetMinimapZoneText").values,
    }
    local current = location.mapID
    for _ = 1, Context.MAX_MAP_DEPTH do
        if isSecret(current) or type(current) ~= "number" or current == 0 then
            break
        end
        local _, infoOk, info = Calls.Invoke(env, "C_Map.GetMapInfo", current)
        if not infoOk or not plainTable(info) then
            break
        end
        location.chain[#location.chain + 1] = {
            mapID = info.mapID,
            mapType = info.mapType,
            parentMapID = info.parentMapID,
            name = info.name,
        }
        current = info.parentMapID
    end
    if type(location.mapID) == "number" then
        local _, posOk, position =
            Calls.Invoke(env, "C_Map.GetPlayerMapPosition", location.mapID, "player")
        if posOk and plainTable(position) then
            local x, y = position.x, position.y
            if type(position.GetXY) == "function" then
                local xyOk, px, py = pcall(position.GetXY, position)
                if xyOk then
                    x, y = px, py
                end
            end
            location.x, location.y = Redact.Position(x), Redact.Position(y)
        end
    end
    return location
end

-- Full context for a cast start. Logged as its own entry so nesting stays within the
-- serializer depth cap.
function Context.Collect(env)
    return {
        professions = Context.Professions(env),
        mainHand = Calls.Call(env, "GetInventoryItemID", "player", Context.MAIN_HAND_SLOT),
        weaponEnchant = Calls.Call(env, "GetWeaponEnchantInfo"),
        buffs = Context.Auras(env, "HELPFUL"),
        debuffs = Context.Auras(env, "HARMFUL"),
        location = Context.Location(env),
        serverTime = Calls.Call(env, "GetServerTime").values,
        swimming = Calls.Call(env, "IsSwimming").values,
        mounted = Calls.Call(env, "IsMounted").values,
        indoors = Calls.Call(env, "IsIndoors").values,
        autoLoot = Calls.Call(env, "C_CVar.GetCVar", "autoLootDefault").values,
    }
end
