-- Pure logic: the journal entries from the generated journal and zone data and a StatsView view of
-- the player's catches (Journal research doc; owner decisions 2026-11-06). Entries cover the four
-- journal groups only (fish, trophy, container, quest). A not-caught entry carries the same
-- information as a caught one plus caught = false. Caught items that are not in the Classic data
-- become "new in Forever" entries, grouped by their Forever item class (Story 5.1: 7/8 fish, 15/4
-- container; anything else cannot be told apart and is left out). No frame or API calls.
local _, ns = ...

local type, pairs, ipairs, sort, min = type, pairs, ipairs, table.sort, math.min

local JournalModel = {}
ns.JournalModel = JournalModel

JournalModel.GROUPS = { "fish", "trophy", "container", "quest" }
JournalModel.PLACES = 5 -- places kept per entry, best Classic share first
JournalModel.SAFE = 95 -- getaways stop at base + SAFE (Zone Data research)
JournalModel.SCOPES = { account = true, character = true }
-- Forever item class/subclass of new items -> journal group (Story 5.1 evidence).
JournalModel.FOREVER_CLASSES = { ["7/8"] = "fish", ["15/4"] = "container" }

local JOURNAL = {}
for _, group in ipairs(JournalModel.GROUPS) do
    JOURNAL[group] = true
end

local function tbl(value)
    return type(value) == "table" and value or {}
end

local function placeBefore(a, b)
    if a.chance ~= b.chance then
        return a.chance > b.chance
    end
    if a.subzone ~= b.subzone then
        return a.subzone -- a subzone is the more exact place
    end
    return a.area < b.area
end

-- Static index of the bundled data (build once per login): groupOf, places per item (every area
-- with its own list, chance, subzone flag, base skill, quest-only flag), recipes per reagent.
-- areas: the Area resolver over the same zone data.
function JournalModel.Index(journal, zones, areas)
    local index = { groupOf = {}, places = {}, recipes = {}, journal = journal }
    for group, ids in pairs(tbl(journal.groups)) do
        for _, id in ipairs(ids) do
            index.groupOf[id] = group
        end
    end
    for area, info in pairs(tbl(zones.areas)) do
        local rows = info.list and tbl(zones.lists)[info.list]
        for _, row in ipairs(rows or {}) do
            local id = row[1]
            local list = index.places[id] or {}
            index.places[id] = list
            list[#list + 1] = {
                area = area,
                chance = row[2],
                subzone = info.zone ~= nil,
                base = areas:Base(area),
                quest = row[5] == 1 or nil,
            }
        end
    end
    for _, list in pairs(index.places) do
        sort(list, placeBefore)
    end
    for spell, recipe in pairs(tbl(journal.recipes)) do
        for _, reagent in ipairs(recipe[3]) do
            local list = index.recipes[reagent[1]] or {}
            index.recipes[reagent[1]] = list
            list[#list + 1] = spell
        end
    end
    for _, list in pairs(index.recipes) do
        sort(list)
    end
    return index
end

-- Character entries for StatsView.Build: every character (account, the default) or only the
-- current one (character). chars: db.chars; current: key of the logged-in character.
function JournalModel.Chars(chars, scope, current)
    local list = {}
    for key, entry in pairs(tbl(chars)) do
        if type(entry) == "table" and (scope ~= "character" or key == current) then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Lowest base skill over an item's places (first catch possible) or nil when no place has one.
local function lowestBase(places)
    local low
    for _, place in ipairs(places) do
        if type(place.base) == "number" and (not low or place.base < low) then
            low = place.base
        end
    end
    return low
end

local function newEntry(index, id, group, own, recipesOf)
    local places = index.places[id] or {}
    local top = {}
    for i = 1, min(#places, JournalModel.PLACES) do
        top[i] = places[i]
    end
    local base = lowestBase(places)
    local questOnly = group == "quest"
    for _, place in ipairs(places) do
        questOnly = questOnly or place.quest == true
    end
    local entry = {
        id = id,
        group = group,
        caught = own ~= nil and (own.n or 0) > 0,
        places = top,
        placeCount = #places,
        base = base,
        safe = base and base + JournalModel.SAFE or nil,
        recipes = (recipesOf or index.recipes)[id] or {},
        season = tbl(index.journal.seasons)[id],
        questOnly = questOnly or nil,
    }
    if own then
        entry.n, entry.qty, entry.best = own.n, own.qty, own.best
        entry.first, entry.firstMap, entry.firstSub = own.first, own.firstMap, own.firstSub
    end
    return entry
end

-- Journal group of an item the Classic data does not have, or nil. classOf(id) returns the
-- Forever item class and subclass (C_Item.GetItemInfoInstant) or nil while unknown.
local function foreverGroup(classOf, id)
    if type(classOf) ~= "function" then
        return nil
    end
    local class, subclass = classOf(id)
    if type(class) ~= "number" or type(subclass) ~= "number" then
        return nil
    end
    return JournalModel.FOREVER_CLASSES[class .. "/" .. subclass]
end

-- Journal group of an item: the bundled group when it is a journal group, else the Forever class
-- group (nil while the class is unknown or for anything else).
function JournalModel.GroupOf(index, classOf, id)
    local group = index.groupOf[id]
    if group then
        return JOURNAL[group] and group or nil
    end
    return foreverGroup(classOf, id)
end

-- input: { index (JournalModel.Index), view (StatsView view of the chosen scope), classOf,
-- recipesOf (item ID -> recipe spells, RecipeModel.ByReagent; default: the bundled recipes) }.
-- Returns { entries (group order, then caught first, then ID), progress = { [group] = { caught,
-- total (Classic), new (caught new in Forever) } }, pending (caught items with an unknown class) }.
function JournalModel.Build(input)
    local index, items = input.index, tbl(tbl(input.view).items)
    local model, order = { entries = {}, progress = {}, pending = 0 }, {}
    for i, group in ipairs(JournalModel.GROUPS) do
        order[group] = i
        model.progress[group] = { caught = 0, total = 0, new = 0 }
    end
    for id, group in pairs(index.groupOf) do
        if JOURNAL[group] then
            local entry = newEntry(index, id, group, items[id], input.recipesOf)
            local progress = model.progress[group]
            progress.total = progress.total + 1
            progress.caught = progress.caught + (entry.caught and 1 or 0)
            model.entries[#model.entries + 1] = entry
        end
    end
    for id, own in pairs(items) do
        if not index.groupOf[id] and (own.n or 0) > 0 then
            local group = foreverGroup(input.classOf, id)
            local known = type(input.classOf) == "function" and input.classOf(id) ~= nil
            if group then
                local entry = newEntry(index, id, group, own, input.recipesOf)
                entry.new = true
                model.progress[group].new = model.progress[group].new + 1
                model.entries[#model.entries + 1] = entry
            elseif not known then
                model.pending = model.pending + 1 -- class not loaded yet; build again later
            end
        end
    end
    sort(model.entries, function(a, b)
        if a.group ~= b.group then
            return order[a.group] < order[b.group]
        end
        if a.caught ~= b.caught then
            return a.caught
        end
        return a.id < b.id
    end)
    return model
end

-- Gear that closes a skill gap: { itemID } of journal gear (kind gear, usable at skill) with a
-- bonus of at least gap, smallest bonus first; when none is enough, every usable item with the
-- highest bonus (they may sit in different slots; Story 5.7 combines slots). raceBit: the
-- player's race bit (nil: any race).
function JournalModel.GearFor(journal, gap, skill, raceBit)
    local usable = {}
    for id, g in pairs(tbl(journal.gear)) do
        local bonus, need, _, races, _, _, kind = g[1], g[2], g[3], g[4], g[5], g[6], g[7]
        local raceOk = races == 0 or not raceBit or races % (raceBit * 2) >= raceBit
        if kind == "gear" and (skill or 0) >= need and raceOk then
            usable[#usable + 1] = { id = id, bonus = bonus }
        end
    end
    sort(usable, function(a, b)
        if a.bonus ~= b.bonus then
            return a.bonus < b.bonus
        end
        return a.id < b.id
    end)
    local fit = {}
    for _, g in ipairs(usable) do
        if g.bonus >= gap then
            fit[#fit + 1] = g.id
        end
    end
    if #fit == 0 and #usable > 0 then
        local top = usable[#usable].bonus
        for _, g in ipairs(usable) do
            if g.bonus == top then
                fit[#fit + 1] = g.id
            end
        end
    end
    return fit
end
