-- Pure logic: export text of the fishing history (Import.lua reads it back). Every page stands
-- alone:
--   FMX|<version>|<scope>|<page>|<pages>|<checksum>
--   C|<guid>|<name>|<part>|<subzone>/<subzone>/...   one per character on the page
--   D|<day chunk>                                    that character's chunks (Codec format)
-- scope "char" (for sharing) writes "-" for GUID and names; scope "all" (backup) keeps them.
-- A page never splits a day. The checksum covers every line after the header.
local _, ns = ...

local ipairs, pairs, tonumber, concat, sort = ipairs, pairs, tonumber, table.concat, table.sort
local byte, char, format, gsub, match =
    string.byte, string.char, string.format, string.gsub, string.match

local Codec = ns.Codec

local Export = {}
ns.Export = Export

Export.VERSION = 1
Export.PAGE_SIZE = 200000 -- characters per page (one edit box)

-- 32-bit polynomial hash as 8 hex digits (no bit library needed).
function Export.Checksum(text)
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + byte(text, i)) % 4294967296
    end
    return format("%08x", hash)
end

local function escape(text)
    return (gsub(text, "[%%|/\r\n]", function(c)
        return format("%%%02X", byte(c))
    end))
end

function Export.Unescape(text)
    return (gsub(text, "%%(%x%x)", function(hex)
        return char(tonumber(hex, 16))
    end))
end

function Export.ChunkDay(chunk)
    return tonumber(match(chunk, "^(%d+)|")) or -1
end

-- Chunks of a character including the open day, packed on the fly (the entry is unchanged).
local function chunksOf(entry)
    local list = {}
    for _, chunk in ipairs(entry.days or {}) do
        list[#list + 1] = chunk
    end
    local group, groupDay = {}, nil
    local function flush()
        for _, chunk in ipairs(#group > 0 and Codec.Encode(groupDay, group) or {}) do
            list[#list + 1] = chunk
        end
    end
    for _, cast in ipairs(entry.casts or {}) do
        local day = Codec.Day(cast.t or 0)
        if day ~= groupDay then
            flush()
            group, groupDay = {}, day
        end
        group[#group + 1] = cast
    end
    flush()
    return list
end

-- "D|" lines grouped by day with their total size.
local function dayGroups(chunks)
    local groups, last = {}, nil
    for _, chunk in ipairs(chunks) do
        local day = Export.ChunkDay(chunk)
        if day ~= last then
            groups[#groups + 1] = { size = 0 }
            last = day
        end
        local group = groups[#groups]
        group[#group + 1] = "D|" .. chunk
        group.size = group.size + #chunk + 3
    end
    return groups
end

local function charLine(key, entry, scope)
    local subzones = {}
    for i, text in ipairs(entry.subzones or {}) do
        subzones[i] = escape(text)
    end
    if scope == "char" then
        return "C|-|-|-|" .. concat(subzones, "/")
    end
    local name, part = escape(entry.name or "-"), escape(entry.part or "-")
    return "C|" .. key .. "|" .. name .. "|" .. part .. "|" .. concat(subzones, "/")
end

-- Export pages. scope "char": only db.chars[key], without GUID or names; "all": every character.
function Export.Build(db, scope, key, pageSize)
    pageSize = pageSize or Export.PAGE_SIZE
    local keys = {}
    if scope == "char" then
        keys[1] = key
    else
        for guid in pairs(db.chars) do
            keys[#keys + 1] = guid
        end
        sort(keys)
    end
    local bodies, lines, size = {}, {}, 0
    local function newPage()
        if #lines > 0 then
            bodies[#bodies + 1] = lines
        end
        lines, size = {}, 0
    end
    for _, guid in ipairs(keys) do
        local entry = db.chars[guid]
        local cLine = charLine(guid, entry, scope)
        local started = false
        for _, group in ipairs(dayGroups(chunksOf(entry))) do
            if size + group.size > pageSize and #lines > 0 then
                newPage()
                started = false
            end
            if not started then
                lines[#lines + 1] = cLine
                size, started = size + #cLine + 1, true
            end
            for _, line in ipairs(group) do
                lines[#lines + 1] = line
            end
            size = size + group.size
        end
        if not started then
            lines[#lines + 1] = cLine
            size = size + #cLine + 1
        end
    end
    newPage()
    local pages = {}
    for i, body in ipairs(bodies) do
        local text = concat(body, "\n")
        local header =
            format("FMX|%d|%s|%d|%d|%s", Export.VERSION, scope, i, #bodies, Export.Checksum(text))
        pages[i] = header .. "\n" .. text
    end
    return pages
end
