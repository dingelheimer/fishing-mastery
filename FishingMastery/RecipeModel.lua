-- Pure logic: the recipes of the journal. The 23 bundled Classic recipes that use a journal item
-- (Data/Journal.lua; owner decision 4: every profession) are merged with the recipes read from the
-- player's own profession windows (RecipeRead.lua), which are stored once per account in
-- FishingMasteryDB.recipes. A stored recipe that is bundled keeps the bundled ranks and source and
-- takes the product and reagents read in game; one that is not bundled is new in Forever ("read in
-- game"). The store holds IDs and counts only: [spell] = { s = profession skill line (0: unknown),
-- p = product item (0: none), r = { { itemID, count } } }. No frame or API calls.
local _, ns = ...

local type, pairs, ipairs, sort = type, pairs, ipairs, table.sort

local RecipeModel = {}
ns.RecipeModel = RecipeModel

RecipeModel.CAP = 300 -- stored recipes per account (a cooking line has about 141)
RecipeModel.REAGENTS = 8 -- reagents kept per stored recipe
-- Profession order in the list; other skill lines follow by ID.
RecipeModel.ORDER = { [185] = 1, [171] = 2, [356] = 3 }

local function isId(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

local function isCount(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

-- The account store (FishingMasteryDB.recipes), created or repaired on first use.
function RecipeModel.Store(db)
    if type(db.recipes) ~= "table" then
        db.recipes = {}
    end
    return db.recipes
end

local function count(store)
    local n = 0
    for _ in pairs(store) do
        n = n + 1
    end
    return n
end

-- Valid reagent list of a read recipe, or nil when it has none.
local function reagents(list)
    local out = {}
    for _, reagent in ipairs(type(list) == "table" and list or {}) do
        if type(reagent) == "table" and isId(reagent.id) and isCount(reagent.count) then
            if #out < RecipeModel.REAGENTS then
                out[#out + 1] = { reagent.id, reagent.count }
            end
        end
    end
    return #out > 0 and out or nil
end

local function same(a, b)
    if type(a) ~= "table" or a.s ~= b.s or a.p ~= b.p or #a.r ~= #b.r then
        return false
    end
    for i, reagent in ipairs(b.r) do
        local other = a.r[i]
        if type(other) ~= "table" or other[1] ~= reagent[1] or other[2] ~= reagent[2] then
            return false
        end
    end
    return true
end

-- Stores the read recipes that use a journal item. read: { { id (spell), profession, product,
-- reagents = { { id, count } } } }; isJournal(itemID) tells a journal item. Returns the number of
-- recipes that were new to the store and the number of changed ones.
function RecipeModel.Merge(store, read, isJournal)
    local added, changed, size = 0, 0, count(store)
    for _, recipe in ipairs(type(read) == "table" and read or {}) do
        local list = type(recipe) == "table" and isId(recipe.id) and reagents(recipe.reagents)
        local uses = false
        for _, reagent in ipairs(list or {}) do
            uses = uses or isJournal(reagent[1]) == true
        end
        if uses then
            local row = {
                s = isId(recipe.profession) and recipe.profession or 0,
                p = isId(recipe.product) and recipe.product or 0,
                r = list,
            }
            local old = store[recipe.id]
            if old == nil and size < RecipeModel.CAP then
                store[recipe.id], size, added = row, size + 1, added + 1
            elseif old ~= nil and not same(old, row) then
                store[recipe.id], changed = row, changed + 1
            end
        end
    end
    return added, changed
end

local function stored(row)
    if type(row) ~= "table" or type(row.r) ~= "table" then
        return nil
    end
    local list = {}
    for _, reagent in ipairs(row.r) do
        if type(reagent) == "table" and isId(reagent[1]) and isCount(reagent[2]) then
            list[#list + 1] = { reagent[1], reagent[2] }
        end
    end
    return #list > 0 and list or nil
end

local function before(a, b)
    local oa, ob = RecipeModel.ORDER[a.profession] or 99, RecipeModel.ORDER[b.profession] or 99
    if oa ~= ob then
        return oa < ob
    end
    if a.profession ~= b.profession then
        return (a.profession or 0) < (b.profession or 0)
    end
    if (a.learn ~= nil) ~= (b.learn ~= nil) then
        return a.learn ~= nil -- bundled recipes with a learn skill first
    end
    if a.learn ~= b.learn then
        return a.learn < b.learn
    end
    return a.spell < b.spell
end

-- Recipe entries: { spell, profession (nil: unknown), product, reagents = { { itemID, count } },
-- low, high (color ranks), learn, source, item (recipe item), read (seen in game), forever (not
-- bundled), food = { bonus, level, source } }. Profession order, then learn skill, then spell.
function RecipeModel.Build(journal, store)
    local list, food = {}, type(journal.food) == "table" and journal.food or {}
    store = type(store) == "table" and store or {}
    local function finish(entry)
        local f = food[entry.product]
        if f then
            entry.food = { bonus = f[1], level = f[2], source = f[3] }
        end
        list[#list + 1] = entry
    end
    for spell, r in pairs(type(journal.recipes) == "table" and journal.recipes or {}) do
        local row = store[spell]
        local read = stored(row)
        finish({
            spell = spell,
            profession = r[1],
            product = read and isId(row.p) and row.p or r[2],
            reagents = read or r[3],
            low = r[4],
            high = r[5],
            learn = r[6],
            source = r[7],
            item = r[8] ~= 0 and r[8] or nil,
            read = read ~= nil,
        })
    end
    for spell, row in pairs(store) do
        local read = isId(spell)
            and not (journal.recipes and journal.recipes[spell])
            and stored(row)
        if read then
            finish({
                spell = spell,
                profession = isId(row.s) and row.s or nil,
                product = isId(row.p) and row.p or nil,
                reagents = read,
                read = true,
                forever = true,
            })
        end
    end
    sort(list, before)
    return list
end

-- Item ID -> spell IDs of the recipes that use it (sorted), for the Fish tab.
function RecipeModel.ByReagent(list)
    local by = {}
    for _, entry in ipairs(list) do
        for _, reagent in ipairs(entry.reagents) do
            local spells = by[reagent[1]] or {}
            by[reagent[1]] = spells
            if spells[#spells] ~= entry.spell then
                spells[#spells + 1] = entry.spell
            end
        end
    end
    for _, spells in pairs(by) do
        sort(spells)
    end
    return by
end

-- The entry of a spell in a Build list, or nil.
function RecipeModel.Find(list, spell)
    for _, entry in ipairs(list) do
        if entry.spell == spell then
            return entry
        end
    end
end
