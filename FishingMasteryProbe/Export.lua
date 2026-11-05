-- Pure logic: the log as compact text for /fmp export. One JSON array per line:
-- [t, step, q, kind, data]. Pages keep the edit box text small enough for the client.
local _, ns = ...

local type, pairs, ipairs, tostring, format = type, pairs, ipairs, tostring, string.format
local concat, sort, gsub, byte = table.concat, table.sort, string.gsub, string.byte
local huge = math.huge

local Export = {}
ns.Export = Export

Export.FORMAT = "fmp-export-1"
Export.PAGE_CHARS = 200000 -- characters per page shown in the copy window

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

-- JSON string. "|" is written as | so the client edit box shows no escape sequences.
local function encodeString(value)
    return '"'
        .. gsub(value, '[%c"\\|]', function(c)
            return ESCAPES[c] or format("\\u%04x", byte(c))
        end)
        .. '"'
end

local function isArray(value)
    local n = #value
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key > n or key % 1 ~= 0 then
            return false
        end
    end
    return true
end

local encode

local function encodeTable(value, depth)
    if depth > 12 then
        return '"<depth>"'
    end
    local parts = {}
    if isArray(value) then
        for i = 1, #value do
            parts[i] = encode(value[i], depth + 1)
        end
        return "[" .. concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for i, key in ipairs(keys) do
        parts[i] = encodeString(tostring(key)) .. ":" .. encode(value[key], depth + 1)
    end
    return "{" .. concat(parts, ",") .. "}"
end

-- Compact JSON for logged (already sanitized) data; other types become strings.
function encode(value, depth)
    local kind = type(value)
    if value == nil then
        return "null"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        if value ~= value or value == huge or value == -huge then
            return encodeString(tostring(value))
        end
        return format("%.14g", value)
    elseif kind == "string" then
        return encodeString(value)
    elseif kind == "table" then
        return encodeTable(value, depth or 0)
    end
    return encodeString("<" .. kind .. ">")
end
Export.Encode = encode

function Export.Line(entry)
    return "["
        .. concat({
            encode(entry.t),
            encode(entry.step),
            encode(entry.q),
            encode(entry.kind),
            encode(entry.data),
        }, ",")
        .. "]"
end

local function header(store, page, pages)
    return encode({
        format = Export.FORMAT,
        session = store.sessionId,
        version = store.probeVersion,
        entries = #store.entries,
        dropped = store.dropped,
        cap = store.cap,
        page = page,
        pages = pages,
    })
end

-- Splits the log into pages of at most pageChars characters (a single longer line gets its own
-- page). Every page starts with a header line. Returns a list of page texts.
function Export.Pages(store, pageChars)
    pageChars = pageChars or Export.PAGE_CHARS
    local groups, current, size = {}, {}, 0
    for _, entry in ipairs(store.entries) do
        local line = Export.Line(entry)
        if #current > 0 and size + #line + 1 > pageChars then
            groups[#groups + 1] = current
            current, size = {}, 0
        end
        current[#current + 1] = line
        size = size + #line + 1
    end
    groups[#groups + 1] = current
    local pages = {}
    for i, lines in ipairs(groups) do
        pages[i] = header(store, i, #groups) .. "\n" .. concat(lines, "\n")
    end
    return pages
end
