-- Pure logic: reads an export page (Export.lua format) back. The page is parsed as data only and
-- validated completely (version, checksum, every field) before anything is merged; days the
-- character already has are skipped, so importing a page twice changes nothing.
local _, ns = ...

local type, ipairs, pcall, error, unpack = type, ipairs, pcall, error, unpack
local tostring, tonumber, sort = tostring, tonumber, table.sort
local gsub, gmatch, match = string.gsub, string.gmatch, string.match

local Codec, Records, Totals, Export = ns.Codec, ns.Records, ns.Totals, ns.Export

local Import = {}
ns.Import = Import

local GUID_PATTERN = "^Player%-%d+%-%x+$"

local function fail(message)
    error(message, 0)
end

local function parseChar(rest, scope)
    local guid, name, part, subzones = match(rest, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if not guid or (guid ~= "-" and not match(guid, GUID_PATTERN)) then
        fail("bad character line")
    end
    if scope == "all" and guid == "-" then
        fail("character without GUID in a full backup")
    end
    local entry = { guid = guid ~= "-" and guid or nil, subzones = {}, days = {} }
    entry.name = name ~= "-" and Export.Unescape(name) or nil
    entry.part = part ~= "-" and Export.Unescape(part) or nil
    for zone in gmatch(subzones, "[^/]+") do
        entry.subzones[#entry.subzones + 1] = Export.Unescape(zone)
    end
    return entry
end

local function parse(text)
    if type(text) ~= "string" then
        fail("no text")
    end
    text = gsub(gsub(gsub(text, "\r\n?", "\n"), "^%s+", ""), "%s+$", "")
    local header, body = match(text, "^([^\n]*)\n(.*)$")
    if not header then
        fail("missing header")
    end
    local version, scope, page, pages, checksum =
        match(header, "^FMX|(%d+)|(%a+)|(%d+)|(%d+)|(%x+)$")
    if not version then
        fail("not a Fishing Mastery export")
    end
    if tonumber(version) ~= Export.VERSION then
        fail("unsupported version " .. version)
    end
    if scope ~= "char" and scope ~= "all" then
        fail("unknown scope " .. scope)
    end
    if Export.Checksum(body) ~= checksum then
        fail("checksum mismatch (text changed or incomplete)")
    end
    local staged = { scope = scope, page = tonumber(page), pages = tonumber(pages), chars = {} }
    local current
    for line in gmatch(body .. "\n", "([^\n]*)\n") do
        local kind, rest = match(line, "^(%u)|(.*)$")
        if kind == "C" then
            current = parseChar(rest, scope)
            staged.chars[#staged.chars + 1] = current
        elseif kind == "D" and current then
            local day, casts = Codec.Decode(rest)
            if not day then
                fail("bad history chunk: " .. casts)
            end
            for _, cast in ipairs(casts) do
                if cast.sub and not current.subzones[cast.sub] then
                    fail("bad subzone index")
                end
            end
            current.days[#current.days + 1] = { day = day, casts = casts }
        else
            fail("unexpected line")
        end
    end
    if scope == "char" and #staged.chars ~= 1 then
        fail("a character export holds one character")
    end
    return staged
end

-- Validates an export page completely. Returns the staged data, or nil and the reason.
function Import.Parse(text)
    local ok, result = pcall(parse, text)
    if not ok then
        return nil, tostring(result)
    end
    return result
end

local function existingDays(entry)
    local days = {}
    for _, chunk in ipairs(entry.days) do
        days[Export.ChunkDay(chunk)] = true
    end
    for _, cast in ipairs(entry.casts) do
        days[Codec.Day(cast.t or 0)] = true
    end
    return days
end

-- Imported casts per day, days in first-seen order.
local function groupByDay(imported)
    local byDay, dayList = {}, {}
    for _, item in ipairs(imported.days) do
        local list = byDay[item.day]
        if not list then
            list = {}
            byDay[item.day] = list
            dayList[#dayList + 1] = item.day
        end
        for _, cast in ipairs(item.casts) do
            list[#list + 1] = cast
        end
    end
    return byDay, dayList
end

-- Adds the whole days the target does not have yet; a day already present is skipped. Builds new
-- lists and assigns them at the end. Returns { days, casts, skipped }.
local function mergeChar(target, imported)
    local result = { days = 0, casts = 0, skipped = 0 }
    local have = existingDays(target)
    local copy = { subzones = { unpack(target.subzones) } }
    -- { day, index, chunk }: sorting by day, then index, keeps the order within a day.
    local entries = {}
    for i, chunk in ipairs(target.days) do
        entries[i] = { Export.ChunkDay(chunk), i, chunk }
    end
    local byDay, dayList = groupByDay(imported)
    for _, day in ipairs(dayList) do
        if have[day] then
            result.skipped = result.skipped + 1
        else
            local casts = byDay[day]
            for _, cast in ipairs(casts) do
                if cast.sub then
                    cast.sub = Records.SubzoneIndex(copy, imported.subzones[cast.sub])
                end
            end
            for _, chunk in ipairs(Codec.Encode(day, casts)) do
                entries[#entries + 1] = { day, #entries + 1, chunk }
            end
            result.days, result.casts = result.days + 1, result.casts + #casts
        end
    end
    if result.days > 0 then
        sort(entries, function(a, b)
            if a[1] ~= b[1] then
                return a[1] < b[1]
            end
            return a[2] < b[2]
        end)
        local chunks = {}
        for i, entry in ipairs(entries) do
            chunks[i] = entry[3]
        end
        target.days, target.subzones = chunks, copy.subzones
        target.totals = Totals.Rebuild(target)
    end
    return result
end

-- Merges a staged import into db. A "char" export goes into db.chars[key]; an "all" export into
-- the characters with the same GUID (created when missing). prepare(entry) adds missing tables.
-- Returns { days, casts, skipped, chars }.
function Import.Merge(db, staged, key, prepare)
    local summary = { days = 0, casts = 0, skipped = 0, chars = 0 }
    for _, imported in ipairs(staged.chars) do
        local guid = staged.scope == "char" and key or imported.guid
        if guid then
            local entry = db.chars[guid]
            if not entry then
                entry = { name = imported.name, part = imported.part }
                db.chars[guid] = entry
            end
            prepare(entry)
            local result = mergeChar(entry, imported)
            summary.days = summary.days + result.days
            summary.casts = summary.casts + result.casts
            summary.skipped = summary.skipped + result.skipped
            summary.chars = summary.chars + 1
        end
    end
    return summary
end
