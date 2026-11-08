-- Cast context read from the game at a cast start: server time, map, subzone text, fishing rank
-- and skill modifier, and the lure enchant. Reads from an injected environment (_G in game).
local _, ns = ...

local type, pcall, select, unpack, maxn = type, pcall, select, unpack, table.maxn
local isSecret = issecretvalue or function()
    return false
end

local Context = {}
ns.Context = Context

Context.FISHING_INDEX = 4 -- position of Fishing in the GetProfessions returns
Context.RANK = 3 -- GetProfessionInfo: skillLevel
Context.MAX = 4 -- GetProfessionInfo: maxSkillLevel (the trainer rank cap)
Context.MODIFIER = 8 -- GetProfessionInfo: skillModifier (lure +25 on live)
Context.ENCHANT_ID = 4 -- GetWeaponEnchantInfo: mainHandEnchantID

local function plain(value)
    if isSecret(value) then
        return nil
    end
    return value
end

-- Calls env[name] or env[namespace][name] protected; returns its results or nothing.
function Context.Call(env, path, ...)
    local fn = env
    for part in path:gmatch("[^.]+") do
        fn = type(fn) == "table" and fn[part] or nil
    end
    if type(fn) ~= "function" then
        return nil
    end
    local results = { pcall(fn, ...) }
    if not results[1] then
        return nil
    end
    return unpack(results, 2, maxn(results))
end

local function number(value)
    value = plain(value)
    return type(value) == "number" and value or nil
end

-- Fishing rank, skill modifier, and rank cap, or nil when Fishing is not learned.
function Context.Fishing(env)
    local index = number(select(Context.FISHING_INDEX, Context.Call(env, "GetProfessions")))
    if not index then
        return nil, nil, nil
    end
    local info = { Context.Call(env, "GetProfessionInfo", index) }
    return number(info[Context.RANK]), number(info[Context.MODIFIER]), number(info[Context.MAX])
end

-- Client name of the Fishing skill (GetProfessionInfo name), or nil when Fishing is not learned.
function Context.FishingName(env)
    local index = number(select(Context.FISHING_INDEX, Context.Call(env, "GetProfessions")))
    local name = index and plain((Context.Call(env, "GetProfessionInfo", index)))
    return type(name) == "string" and name ~= "" and name or nil
end

Context.MAIN_HAND = 16
Context.POLE = { 2, 20 } -- item class and subclass of fishing poles (C_Item.GetItemInfoInstant)

-- True when a fishing pole is in the main hand.
function Context.HasPole(env)
    local id = number(Context.Call(env, "GetInventoryItemID", "player", Context.MAIN_HAND))
    if not id then
        return false
    end
    local info = { Context.Call(env, "C_Item.GetItemInfoInstant", id) }
    return plain(info[6]) == Context.POLE[1] and plain(info[7]) == Context.POLE[2]
end

-- Lure enchant ID on the main hand, or nil without a lure.
function Context.Lure(env)
    local info = { Context.Call(env, "GetWeaponEnchantInfo") }
    if plain(info[1]) ~= true then
        return nil
    end
    return number(info[Context.ENCHANT_ID])
end

-- Lure enchant ID and seconds left on the main hand, or nil without a lure.
function Context.LureTime(env)
    local info = { Context.Call(env, "GetWeaponEnchantInfo") }
    if plain(info[1]) ~= true then
        return nil
    end
    local ms = number(info[2])
    return number(info[Context.ENCHANT_ID]), ms and ms / 1000 or nil
end

-- Localized name of a uiMapID from C_Map.GetMapInfo, or nil.
function Context.MapName(env, map)
    if type(map) ~= "number" then
        return nil
    end
    local info = Context.Call(env, "C_Map.GetMapInfo", map)
    local name = type(info) == "table" and plain(info.name) or nil
    return type(name) == "string" and name or nil
end

-- Client name of an AreaTable ID from C_Map.GetAreaInfo (client language), or nil.
function Context.AreaName(env, area)
    if type(area) ~= "number" then
        return nil
    end
    local name = plain((Context.Call(env, "C_Map.GetAreaInfo", area)))
    return type(name) == "string" and name ~= "" and name or nil
end

-- Instance map ID inside an instance (GetInstanceInfo, 8th return), nil in the open world.
function Context.Instance(env)
    local info = { Context.Call(env, "GetInstanceInfo") }
    local kind = plain(info[2])
    if type(kind) ~= "string" or kind == "none" then
        return nil
    end
    return number(info[8])
end

-- The UI map the player is on now, or nil.
function Context.CurrentMap(env)
    return number((Context.Call(env, "C_Map.GetBestMapForUnit", "player")))
end

-- The area the player stands in now (Area resolver), or nil without data.
function Context.CurrentArea(env, areas)
    if not areas then
        return nil
    end
    local subzone = plain((Context.Call(env, "GetSubZoneText")))
    return areas:Resolve(
        number((Context.Call(env, "C_Map.GetBestMapForUnit", "player"))),
        type(subzone) == "string" and subzone or nil,
        Context.Instance(env)
    )
end

-- Context for one cast; every field is a number or plain string, or nil when unavailable.
function Context.Read(env)
    local rank, modifier = Context.Fishing(env)
    local subzone = plain((Context.Call(env, "GetSubZoneText")))
    return {
        time = number((Context.Call(env, "GetServerTime"))),
        map = number((Context.Call(env, "C_Map.GetBestMapForUnit", "player"))),
        subzone = type(subzone) == "string" and subzone ~= "" and subzone or nil,
        rank = rank,
        modifier = modifier,
        lure = Context.Lure(env),
    }
end
