-- Fills in item quality that the loot window did not give: from C_Item.GetItemInfo when the item
-- is cached, otherwise after C_Item.RequestLoadItemDataByID and ITEM_DATA_LOAD_RESULT.
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
Items.MAX_PENDING = 200 -- loot entries waiting for item data

local function quality(env, id)
    local value = select(Items.QUALITY, Call(env, "C_Item.GetItemInfo", id))
    if isSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

function Items.New(env)
    return setmetatable({ env = env, pending = {}, count = 0 }, Items)
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
        self.pending[entry.id] = list
        Call(self.env, "C_Item.RequestLoadItemDataByID", entry.id)
    end
    list[#list + 1] = entry
    self.count = self.count + 1
end

-- ITEM_DATA_LOAD_RESULT(itemID, success): fills every waiting entry of that item.
function Items:OnLoaded(itemID, success)
    if isSecret(itemID) then
        return
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
