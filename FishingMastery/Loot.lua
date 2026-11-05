-- Loot window reading at a fishing catch: item ID, quantity, and quality per slot, and the loot
-- source type and object ID. Reads from an injected environment (_G in game).
local _, ns = ...

local type, tonumber, match, min = type, tonumber, string.match, math.min
local isSecret = issecretvalue or function()
    return false
end

local Call = ns.Context.Call

local Loot = {}
ns.Loot = Loot

Loot.MAX_SLOTS = 10
Loot.QUANTITY = 3 -- GetLootSlotInfo: quantity
Loot.QUALITY = 5 -- GetLootSlotInfo: quality (confirmed on live)

local function plain(value)
    if isSecret(value) then
        return nil
    end
    return value
end

-- Item ID from an item link ("|Hitem:12345:..."), or nil.
function Loot.ItemID(link)
    link = plain(link)
    if type(link) ~= "string" then
        return nil
    end
    return tonumber(match(link, "item:(%d+)"))
end

-- Source type and object ID from a GUID such as "GameObject-0-1-2-3-35591-0000ABCD".
-- Only the type and the object ID are kept; the rest identifies a spawn or server.
function Loot.Source(guid)
    guid = plain(guid)
    if type(guid) ~= "string" then
        return nil, nil
    end
    local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if not kind or kind == "Player" then
        return nil, nil
    end
    return kind, tonumber(id)
end

-- { items = { { id, qty, q } }, srcType, srcId } for the open loot window. Slots without an
-- item link (coins, currency) are skipped.
function Loot.Read(env)
    local count = plain((Call(env, "GetNumLootItems")))
    count = type(count) == "number" and min(count, Loot.MAX_SLOTS) or 0
    local loot = { items = {} }
    for slot = 1, count do
        local id = Loot.ItemID((Call(env, "GetLootSlotLink", slot)))
        if id then
            local info = { Call(env, "GetLootSlotInfo", slot) }
            local qty, q = plain(info[Loot.QUANTITY]), plain(info[Loot.QUALITY])
            loot.items[#loot.items + 1] = {
                id = id,
                qty = type(qty) == "number" and qty or 1,
                q = type(q) == "number" and q or nil,
            }
            if not loot.srcType then
                loot.srcType, loot.srcId = Loot.Source((Call(env, "GetLootSourceInfo", slot)))
            end
        end
    end
    return loot
end
