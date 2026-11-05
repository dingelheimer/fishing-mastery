-- Pure logic: turns any Lua value into plain data that is safe to store in SavedVariables.
-- Secret values become "<secret:type>" and are never compared, indexed, or measured.
local _, ns = ...

local type, pairs, tostring, select = type, pairs, tostring, select
local strsub = string.sub
local huge = math.huge
local isSecret = issecretvalue or function()
    return false
end

local Serializer = {}
ns.Serializer = Serializer

Serializer.DEFAULTS = {
    maxDepth = 6, -- nested tables deeper than this become "<depth>"
    maxString = 500, -- longer strings are cut and marked "<cut:LENGTH>"
    maxKeys = 200, -- further keys of one table are counted in "__cut"
}

local function withDefaults(opts)
    if opts == nil then
        return Serializer.DEFAULTS
    end
    local merged = {}
    for key, value in pairs(Serializer.DEFAULTS) do
        local override = opts[key]
        if override == nil then
            merged[key] = value
        else
            merged[key] = override
        end
    end
    return merged
end

local function secretMarker(value)
    return "<secret:" .. type(value) .. ">"
end

local function cutString(value, opts)
    local length = #value
    if length > opts.maxString then
        return strsub(value, 1, opts.maxString) .. "<cut:" .. length .. ">"
    end
    return value
end

-- Keys must stay unique, so markers for unusual keys carry a running index.
local function sanitizeKey(key, opts, index)
    if isSecret(key) then
        return secretMarker(key) .. "#" .. index
    end
    local keyType = type(key)
    if keyType == "string" then
        return cutString(key, opts)
    elseif keyType == "number" then
        if key == huge or key == -huge then
            return "<" .. tostring(key) .. ">#" .. index
        end
        return key
    elseif keyType == "boolean" then
        return "<" .. tostring(key) .. ">"
    end
    return "<" .. keyType .. ">#" .. index
end

local function sanitize(value, opts, depth, seen)
    if isSecret(value) then
        return secretMarker(value)
    end
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" then
        return value
    elseif valueType == "number" then
        if value ~= value then
            return "<nan>"
        elseif value == huge then
            return "<inf>"
        elseif value == -huge then
            return "<-inf>"
        end
        return value
    elseif valueType == "string" then
        return cutString(value, opts)
    elseif valueType == "table" then
        if seen[value] then
            return "<cycle>"
        end
        if depth >= opts.maxDepth then
            return "<depth>"
        end
        seen[value] = true
        local out, count, skipped = {}, 0, 0
        for key, child in pairs(value) do
            if count >= opts.maxKeys then
                skipped = skipped + 1
            else
                count = count + 1
                out[sanitizeKey(key, opts, count)] = sanitize(child, opts, depth + 1, seen)
            end
        end
        if skipped > 0 then
            out.__cut = skipped
        end
        seen[value] = nil
        return out
    end
    return "<" .. valueType .. ">"
end

-- Returns a plain-data copy of value.
function Serializer.Sanitize(value, opts)
    return sanitize(value, withDefaults(opts), 0, {})
end

-- Sanitizes a vararg list and keeps nil positions: { n = count, [i] = value }.
function Serializer.Pack(...)
    local count = select("#", ...)
    local opts = Serializer.DEFAULTS
    local out = { n = count }
    for i = 1, count do
        out[i] = sanitize((select(i, ...)), opts, 1, {})
    end
    return out
end
