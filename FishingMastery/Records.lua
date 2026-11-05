-- Pure logic: builds the saved cast record from a finished attempt and its context, and keeps
-- the per-character subzone text table. Records hold IDs and numbers only (plus the outcome
-- name); Story 2.4 packs them into day chunks.
local _, ns = ...

local type, ipairs, setmetatable = type, ipairs, setmetatable

local Records = {}
ns.Records = Records

-- Reverse subzone lookups per character table, in memory only (never saved).
local lookups = setmetatable({}, { __mode = "k" })

Records.MAX_SUBZONES = 2000 -- subzone texts kept per character; later ones are not indexed

-- Index of a subzone text in char.subzones, adding it when new. nil for no text or a full table.
-- The reverse lookup is rebuilt from the saved list once per load.
function Records.SubzoneIndex(char, text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local list = char.subzones
    local lookup = lookups[list]
    if not lookup then
        lookup = {}
        for index, value in ipairs(list) do
            lookup[value] = index
        end
        lookups[list] = lookup
    end
    local index = lookup[text]
    if not index and #list < Records.MAX_SUBZONES then
        index = #list + 1
        list[index] = text
        lookup[text] = index
    end
    return index
end

-- record: finished attempt from Attempt.lua (with ctx and loot). fallbackTime: server time
-- used when the context has none. Returns the saved cast:
-- { t, map, sub, rank, mod, lure, out, bite, click, auto, loot = { { id, qty, q } }, srcType,
-- srcId }. click: early click or getaway time in tenths after the channel start.
function Records.Build(char, record, fallbackTime)
    local ctx = record.ctx or {}
    local cast = {
        t = ctx.time or fallbackTime,
        map = ctx.map,
        sub = Records.SubzoneIndex(char, ctx.subzone),
        rank = ctx.rank,
        mod = ctx.modifier,
        lure = ctx.lure,
        out = record.outcome,
        bite = record.biteTenths,
        click = record.clickTenths,
        auto = record.autoLoot,
    }
    local loot = record.loot
    if record.outcome == "catch" and type(loot) == "table" then
        local items = {}
        for i, item in ipairs(loot.items or {}) do
            items[i] = { id = item.id, qty = item.qty, q = item.q }
        end
        cast.loot = items
        cast.srcType = loot.srcType
        cast.srcId = loot.srcId
    end
    return cast
end
