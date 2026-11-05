-- Item data from the client cache: fills in item quality that the loot window did not give, and
-- gives name, icon, quality, and sell price for the UI. Uncached items are requested once with
-- C_Item.RequestLoadItemDataByID and filled in on ITEM_DATA_LOAD_RESULT.
local _, ns = ...

local type, ipairs, setmetatable, select = type, ipairs, setmetatable, select
local isSecret = issecretvalue or function()
    return false
end

local Call = ns.Context.Call

local Items = {}
Items.__index = Items
ns.Items = Items

Items.QUALITY = 3 -- C_Item.GetItemInfo: itemQuality
Items.SELL_PRICE = 11 -- C_Item.GetItemInfo: sellPrice (copper)
Items.MAX_PENDING = 200 -- loot entries waiting for item data
Items.MAX_WAITERS = 50 -- callbacks waiting for item data

local function plainNumber(value)
    if isSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

local function quality(env, id)
    return plainNumber((select(Items.QUALITY, Call(env, "C_Item.GetItemInfo", id))))
end

function Items.New(env)
    return setmetatable({ env = env, pending = {}, count = 0, waiters = {}, waiting = 0 }, Items)
end

local function request(self, id)
    if not self.pending[id] and not self.waiters[id] then
        Call(self.env, "C_Item.RequestLoadItemDataByID", id)
    end
end

-- { name, icon, quality, sellPrice } of an item; name and sellPrice are nil while the item is not
-- cached. onLoad (optional) runs once when the data of an uncached item arrives.
function Items:Info(id, onLoad)
    if type(id) ~= "number" then
        return {}
    end
    local env = self.env
    local info = { Call(env, "C_Item.GetItemInfo", id) }
    local name = info[1]
    local icon = Call(env, "C_Item.GetItemIconByID", id)
    local result = {
        name = not isSecret(name) and type(name) == "string" and name or nil,
        icon = plainNumber(icon),
        quality = plainNumber(info[Items.QUALITY]),
        sellPrice = plainNumber(info[Items.SELL_PRICE]),
    }
    if not result.name and onLoad and self.waiting < Items.MAX_WAITERS then
        request(self, id)
        local list = self.waiters[id] or {}
        self.waiters[id] = list
        list[#list + 1] = onLoad
        self.waiting = self.waiting + 1
    end
    return result
end

-- Fills entry.q now, or remembers the entry until the item data has loaded.
function Items:Fill(entry)
    if entry.q then
        return
    end
    entry.q = quality(self.env, entry.id)
    if entry.q or self.count >= Items.MAX_PENDING then
        return
    end
    local list = self.pending[entry.id]
    if not list then
        list = {}
        request(self, entry.id)
        self.pending[entry.id] = list
    end
    list[#list + 1] = entry
    self.count = self.count + 1
end

-- ITEM_DATA_LOAD_RESULT(itemID, success): fills every waiting entry of that item and runs the
-- waiting callbacks.
function Items:OnLoaded(itemID, success)
    if isSecret(itemID) then
        return
    end
    local waiters = self.waiters[itemID]
    if waiters then
        self.waiters[itemID] = nil
        self.waiting = self.waiting - #waiters
        for _, fn in ipairs(waiters) do
            fn(itemID, success)
        end
    end
    local list = self.pending[itemID]
    if not list then
        return
    end
    self.pending[itemID] = nil
    self.count = self.count - #list
    local q = success and quality(self.env, itemID) or nil
    for _, entry in ipairs(list) do
        entry.q = q
    end
end
