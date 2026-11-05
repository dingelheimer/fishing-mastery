-- Pure logic: existence checks and scans over an environment table (_G in game).
-- Values are only read, never called. Secret keys and values are skipped or kept as values
-- for the serializer to mark; they are never compared or indexed.
local _, ns = ...

local type, pairs, pcall, sort, find, sub = type, pairs, pcall, table.sort, string.find, string.sub
local gmatch = string.gmatch
local isSecret = issecretvalue or function()
    return false
end

local Scan = {}
ns.Scan = Scan

local function index(tbl, key)
    return tbl[key]
end

-- Returns the value at a dotted path such as "C_Spell.GetSpellInfo", or nil.
function Scan.Resolve(env, path)
    local value = env
    for part in gmatch(path, "[^%.]+") do
        if isSecret(value) or type(value) ~= "table" then
            return nil
        end
        local ok, child = pcall(index, value, part)
        if not ok then
            return nil
        end
        value = child
    end
    return value
end

-- Type name for the scan result: "function", "table", "nil", other types, or "<secret>".
local function typeOf(value)
    if isSecret(value) then
        return "<secret>"
    end
    return type(value)
end

-- Returns { [name] = typeName } for every name in the list.
function Scan.Existence(env, names)
    local result = {}
    for i = 1, #names do
        result[names[i]] = typeOf(Scan.Resolve(env, names[i]))
    end
    return result
end

-- Returns { [key] = typeName } for the string keys of a table (e.g. a C_* namespace), or nil.
function Scan.Members(tbl)
    if isSecret(tbl) or type(tbl) ~= "table" then
        return nil
    end
    local result = {}
    for key, value in pairs(tbl) do
        if not isSecret(key) and type(key) == "string" then
            result[key] = typeOf(value)
        end
    end
    return result
end

-- Collects string-keyed entries for which predicate(name, value) is true, sorted by name.
-- Returns { items = { { name, value } }, total = matches, cut = matches above the cap }.
function Scan.Collect(tbl, predicate, cap)
    local names, values = {}, {}
    if not isSecret(tbl) and type(tbl) == "table" then
        for key, value in pairs(tbl) do
            if not isSecret(key) and type(key) == "string" and predicate(key, value) then
                names[#names + 1] = key
                values[key] = value
            end
        end
    end
    sort(names)
    local items = {}
    local limit = cap or #names
    for i = 1, #names do
        if i > limit then
            break
        end
        items[i] = { name = names[i], value = values[names[i]] }
    end
    return { items = items, total = #names, cut = #names - #items }
end

-- Predicate: the name contains one of the given substrings (case-sensitive) and the value has
-- the given type (any type when valueType is nil).
function Scan.NameContains(parts, valueType)
    return function(name, value)
        if valueType and (isSecret(value) or type(value) ~= valueType) then
            return false
        end
        for i = 1, #parts do
            if find(name, parts[i], 1, true) then
                return true
            end
        end
        return false
    end
end

-- Predicate: the name starts with the prefix.
function Scan.NameStartsWith(prefix)
    return function(name)
        return sub(name, 1, #prefix) == prefix
    end
end

-- Splits a list into consecutive slices of at most size elements.
function Scan.Chunk(list, size)
    local chunks = {}
    for i = 1, #list, size do
        local chunk = {}
        for j = i, i + size - 1 do
            if list[j] == nil then
                break
            end
            chunk[#chunk + 1] = list[j]
        end
        chunks[#chunks + 1] = chunk
    end
    return chunks
end
