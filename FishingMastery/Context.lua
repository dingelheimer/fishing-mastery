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

-- Fishing rank and skill modifier, or nil when Fishing is not learned.
function Context.Fishing(env)
    local index = number(select(Context.FISHING_INDEX, Context.Call(env, "GetProfessions")))
    if not index then
        return nil, nil
    end
    local info = { Context.Call(env, "GetProfessionInfo", index) }
    return number(info[Context.RANK]), number(info[Context.MODIFIER])
end

-- Lure enchant ID on the main hand, or nil without a lure.
function Context.Lure(env)
    local info = { Context.Call(env, "GetWeaponEnchantInfo") }
    if plain(info[1]) ~= true then
        return nil
    end
    return number(info[Context.ENCHANT_ID])
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
