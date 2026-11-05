-- Pure logic: a character's fishing history. Packed day chunks live in char.days (oldest first,
-- append-only); the open day's casts live in char.casts until they are packed at logout or on
-- a day change. Broken chunks found by the load check move to char.quarantine.
local _, ns = ...

local type, ipairs, tremove, HUGE = type, ipairs, table.remove, math.huge

local Codec = ns.Codec

local History = {}
ns.History = History

-- Packs the open casts into chunks appended to char.days (one group per day, in order) and
-- empties the open list. Earlier chunks are never touched. Returns the number of new chunks.
function History.Pack(char)
    local open = char.casts
    if #open == 0 then
        return 0
    end
    local added, group, groupDay = 0, {}, nil
    local function flush()
        if #group > 0 then
            for _, chunk in ipairs(Codec.Encode(groupDay, group)) do
                char.days[#char.days + 1] = chunk
                added = added + 1
            end
        end
    end
    for _, cast in ipairs(open) do
        local day = Codec.Day(cast.t or 0)
        if day ~= groupDay then
            flush()
            group, groupDay = {}, day
        end
        group[#group + 1] = cast
    end
    flush()
    char.casts = {}
    return added
end

-- Packs the open day first when a cast at time t belongs to a later day.
function History.PackIfNewDay(char, t)
    local first = char.casts[1]
    if first and Codec.Day(first.t or 0) ~= Codec.Day(t or 0) then
        return History.Pack(char)
    end
    return 0
end

History.CHECK_CHUNKS = 10 -- chunks per load check step (about 17 ms in the client)

-- A load check in steps: { days, index, now, result = { chunks, casts, quarantined } }.
-- Decoding every chunk at login took 1.4 s for 200,000 casts on live (Story 2.6), so the addon
-- checks a few chunks per frame after login instead.
function History.NewCheck(char, now)
    return {
        days = char.days,
        index = 1,
        now = now,
        result = { chunks = 0, casts = 0, quarantined = 0 },
    }
end

-- Decodes up to maxChunks more chunks. Broken chunks move to char.quarantine as
-- { chunk, error, found }; the rest stays. A replaced days list (import) restarts the check.
-- Optional hooks: check.onCasts(casts) gets the casts of every valid chunk, check.onRestart()
-- runs when the check starts over. Returns true when every chunk has been checked.
function History.CheckStep(char, check, maxChunks)
    if char.days ~= check.days then
        check.days, check.index = char.days, 1
        check.result = { chunks = 0, casts = 0, quarantined = check.result.quarantined }
        if check.onRestart then
            check.onRestart()
        end
    end
    local days, result = check.days, check.result
    local budget = maxChunks or History.CHECK_CHUNKS
    while check.index <= #days and budget > 0 do
        budget = budget - 1
        local i = check.index
        local day, casts = Codec.Decode(days[i])
        if day then
            result.chunks = result.chunks + 1
            result.casts = result.casts + #casts
            check.index = i + 1
            if check.onCasts then
                check.onCasts(casts)
            end
        else
            local quarantine = char.quarantine
            quarantine[#quarantine + 1] = { chunk = days[i], error = casts, found = check.now }
            tremove(days, i)
            result.quarantined = result.quarantined + 1
        end
    end
    return check.index > #days
end

-- Decodes every chunk at once. Returns { chunks, casts, quarantined }.
function History.Check(char, now)
    local check = History.NewCheck(char, now)
    History.CheckStep(char, check, HUGE)
    return check.result
end

-- Quarantine entries not reported yet; marks them reported.
function History.TakeUnreported(char)
    local list = {}
    for _, entry in ipairs(char.quarantine) do
        if type(entry) == "table" and not entry.reported then
            entry.reported = true
            list[#list + 1] = entry
        end
    end
    return list
end

-- Iterator over every cast, oldest first: packed chunks (decoded one at a time, on demand),
-- then the open casts. Broken chunks are skipped.
function History.Iterate(char)
    local days, open = char.days, char.casts
    local chunkIndex, casts, castIndex, openIndex = 0, nil, 0, 0
    return function()
        while true do
            if casts and castIndex < #casts then
                castIndex = castIndex + 1
                return casts[castIndex]
            end
            if chunkIndex < #days then
                chunkIndex = chunkIndex + 1
                local day, decoded = Codec.Decode(days[chunkIndex])
                casts, castIndex = day and decoded or nil, 0
            elseif openIndex < #open then
                openIndex = openIndex + 1
                return open[openIndex]
            else
                return nil
            end
        end
    end
end
