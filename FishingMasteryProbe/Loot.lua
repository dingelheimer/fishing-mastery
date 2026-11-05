-- Loot and item info reading: slot data at LOOT_READY and item details for looted items.
-- Answers Q09, Q10, Q24, Q30, and Q32. Reads from an injected environment (_G in game).
local _, ns = ...

local type, select, tonumber, min, match = type, select, tonumber, math.min, string.match
local isSecret = issecretvalue or function()
    return false
end

local Calls, Redact = ns.Calls, ns.Redact

local Loot = {}
ns.Loot = Loot

Loot.MAX_SLOTS = 30
Loot.MAX_SOURCES = 8 -- source GUID/quantity pairs kept per slot

-- Item ID from an item link ("|Hitem:12345:..."), or nil.
function Loot.ItemID(link)
    if isSecret(link) or type(link) ~= "string" then
        return nil
    end
    return tonumber(match(link, "item:(%d+)"))
end

-- GetLootSourceInfo returns guid1, quantity1, guid2, quantity2, ...; GUIDs are reduced.
local function sources(...)
    local list = {}
    local count = select("#", ...)
    for i = 1, min(count, Loot.MAX_SOURCES * 2), 2 do
        local guid, quantity = select(i, ...)
        list[#list + 1] = { source = Redact.SourceGuid(guid), quantity = quantity }
    end
    return list
end

-- Returns the source list and a status: "ok", "missing" (no API), or the error message.
local function packSources(exists, ok, ...)
    if not exists then
        return nil, "missing"
    end
    if not ok then
        return nil, (...)
    end
    return sources(...), "ok"
end

-- Everything readable about the open loot window. Returns the record and the item IDs found.
function Loot.Collect(env)
    local numCall = Calls.Call(env, "GetNumLootItems")
    local count = numCall.ok and numCall.values[1] or 0
    if isSecret(count) or type(count) ~= "number" then
        count = 0
    end
    local record = {
        isFishingLoot = Calls.Call(env, "IsFishingLoot"),
        numItems = numCall,
        slots = {},
        slotsCut = count > Loot.MAX_SLOTS and count - Loot.MAX_SLOTS or nil,
    }
    local itemIDs = {}
    for slot = 1, min(count, Loot.MAX_SLOTS) do
        local _, linkOk, link = Calls.Invoke(env, "GetLootSlotLink", slot)
        local itemID = linkOk and Loot.ItemID(link) or nil
        local list, status = packSources(Calls.Invoke(env, "GetLootSourceInfo", slot))
        record.slots[slot] = {
            info = Calls.Call(env, "GetLootSlotInfo", slot),
            slotType = Calls.Call(env, "GetLootSlotType", slot),
            link = linkOk and link or nil,
            itemID = itemID,
            sources = list,
            sourcesStatus = status,
        }
        if itemID then
            itemIDs[#itemIDs + 1] = itemID
        end
    end
    return record, itemIDs
end

-- True when the record's IsFishingLoot call answered true, false when it answered false.
function Loot.IsFishing(record)
    local call = record.isFishingLoot
    if not call.ok then
        return nil
    end
    local value = call.values[1]
    if type(value) ~= "boolean" then
        return nil
    end
    return value
end

-- Q24: item details; `cached` tells whether the data was available at once.
function Loot.ItemInfo(env, itemID)
    local info = Calls.Call(env, "C_Item.GetItemInfo", itemID)
    local name = info.ok and info.values[1] or nil
    return {
        itemID = itemID,
        cached = type(name) == "string",
        info = info,
        sellPrice = info.ok and info.values[11] or nil,
    }
end
