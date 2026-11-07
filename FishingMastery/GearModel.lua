-- Pure logic: the Gear tab model from the bundled journal data (Data/Journal.lua) and what the
-- game reports for the player. Sections: poles, other gear, lures, buff food, fishing ranks, and
-- enchants. Each item has its bundled bonus, the bonus read from its tooltip, what it needs, its
-- source, and where the player has it. The bonus the game applies (skill modifier minus the
-- active lure) is set against the equipped items, and the best setup adds the highest owned bonus
-- per slot and the best lure in the bags to the rank. No frame or API calls.
local _, ns = ...

local type, pairs, ipairs, sort, find, match, tonumber, sub =
    type, pairs, ipairs, table.sort, string.find, string.match, tonumber, string.sub

local GearModel = {}
ns.GearModel = GearModel

GearModel.SECTIONS = { "pole", "gear", "lure", "food", "rank", "enchant" }
GearModel.SLOTS = { "pole", "line", "head", "feet", "hands" } -- best setup, in this order
GearModel.ALLIANCE = 77 -- race mask: Human, Dwarf, Night Elf, Gnome
GearModel.HORDE = 178 -- race mask: Orc, Undead, Tauren, Troll

local function tbl(value)
    return type(value) == "table" and value or {}
end

-- True when a race mask (0: all races) allows the race bit (nil: unknown, allowed).
function GearModel.RaceOk(races, raceBit)
    return races == 0 or not raceBit or races % (raceBit * 2) >= raceBit
end

-- Fishing bonus in tooltip lines: "+N" on the first line that names the skill and, when prefix is
-- given, starts with it ("Equip:"). nil when the lines or the skill name are missing; false when
-- no line has a number. The text is matched as data only.
function GearModel.TipBonus(lines, skillName, prefix)
    if type(lines) ~= "table" or type(skillName) ~= "string" then
        return nil
    end
    for _, line in ipairs(lines) do
        local named = type(line) == "string" and find(line, skillName, 1, true)
        if named and (type(prefix) ~= "string" or sub(line, 1, #prefix) == prefix) then
            local n = match(line, "%+%s*(%d+)")
            if n then
                return tonumber(n)
            end
        end
    end
    return false
end

local function owned(own)
    return type(own) == "table"
            and (own.equipped == true or (own.bags or 0) > 0 or (own.bank or 0) > 0)
        or false
end

-- Adds the player's side to an entry: own (bags, bank, equipped), tip (gear only), usable (race).
local function add(list, entry, input)
    entry.own = input.own(entry.id)
    if entry.section == "pole" or entry.section == "gear" then
        entry.tip = input.tip(entry.id)
    end
    entry.value = type(entry.tip) == "number" and entry.tip or entry.bonus
    entry.usable = GearModel.RaceOk(entry.races or 0, input.raceBit)
    entry.has = owned(entry.own)
    list[#list + 1] = entry
end

local function byValue(a, b)
    if a.value ~= b.value then
        return a.value < b.value
    end
    if (a.skill or 0) ~= (b.skill or 0) then
        return (a.skill or 0) < (b.skill or 0)
    end
    return a.id < b.id
end

local function items(model, journal, input)
    for id, g in pairs(tbl(journal.gear)) do
        local kind, slot = g[7], g[8]
        local section = kind == "lure" and "lure" or slot == "pole" and "pole" or "gear"
        add(model[section], {
            section = section,
            id = id,
            bonus = g[1],
            skill = g[2],
            level = g[3],
            races = g[4],
            source = g[5],
            quest = g[6],
            kind = kind,
            slot = slot,
        }, input)
    end
    for id, l in pairs(tbl(journal.lures)) do
        add(model.lure, {
            section = "lure",
            id = id,
            bonus = l[1],
            skill = l[2],
            level = 0,
            races = l[3],
            source = l[4],
            quest = l[5],
            kind = "lure",
        }, input)
    end
    for id, f in pairs(tbl(journal.food)) do
        add(model.food, {
            section = "food",
            id = id,
            bonus = f[1],
            skill = 0,
            level = f[2],
            races = 0,
            source = "cooking",
            valueSource = f[3],
        }, input)
    end
    for _, key in ipairs({ "pole", "gear", "lure", "food" }) do
        sort(model[key], byValue)
    end
end

local function others(model, journal, input)
    for _, r in ipairs(tbl(journal.ranks)) do
        local reached -- nil while the rank cap is unknown
        if type(input.cap) == "number" then
            reached = input.cap >= r[2]
        end
        model.rank[#model.rank + 1] = {
            section = "rank",
            key = r[1],
            cap = r[2],
            skill = r[3],
            level = r[4],
            source = r[5],
            spell = r[6],
            id = r[7] ~= 0 and r[7] or nil,
            reached = reached,
        }
    end
    for spell, e in pairs(tbl(journal.enchants)) do
        local on = input.gloves
        model.enchant[#model.enchant + 1] = {
            section = "enchant",
            spell = spell,
            bonus = e[1],
            skill = e[2],
            formula = e[3],
            source = e[4],
            on = on,
            value = type(on) == "number" and on or e[1],
            has = type(on) == "number",
            usable = true,
        }
    end
end

-- The equipped bonus: { items = sum over the equipped gear and the glove enchant (tooltip value
-- where read), count, game = skill modifier minus the active lure (nil when unknown) }. With one
-- equipped bonus that differs from the game's, that entry gets .game.
local function measure(model, journal, input)
    local sum, count, single = 0, 0, nil
    for _, key in ipairs({ "pole", "gear", "enchant" }) do
        for _, e in ipairs(model[key]) do
            local on = key == "enchant" and e.has or (e.own and e.own.equipped == true)
            if on and e.kind ~= "lure" then
                sum, count, single = sum + e.value, count + 1, e
            end
        end
    end
    local game
    if type(input.modifier) == "number" then
        local lure = 0
        if input.lure then
            lure = tbl(journal.lureEnchants)[input.lure] -- nil: an unknown lure
        end
        game = lure and input.modifier - lure or nil
    end
    if count == 1 and game and game ~= single.value then
        single.game = game
    end
    return { items = sum, count = count, game = game }
end

local function usableNow(e, input)
    return e.has
        and e.usable
        and (input.rank or 0) >= (e.skill or 0)
        and (type(input.level) ~= "number" or input.level >= (e.level or 0))
end

local function bestOf(list, input, test)
    local best
    for _, e in ipairs(list) do
        if usableNow(e, input) and test(e) and (not best or e.value > best.value) then
            best = e
        end
    end
    return best
end

-- Best setup: { total, rank, parts = { { slot, entry } }, lure = entry or nil }; nil without a
-- rank. A lure counts when it is in the bags (or the lure hat is owned).
function GearModel.Best(model, input)
    if type(input.rank) ~= "number" then
        return nil
    end
    local total, parts = input.rank, {}
    local gear = {}
    for _, key in ipairs({ "pole", "gear" }) do
        for _, e in ipairs(model[key]) do
            gear[#gear + 1] = e
        end
    end
    for _, slot in ipairs(GearModel.SLOTS) do
        local e = bestOf(gear, input, function(x)
            return x.slot == slot and x.kind == "gear"
        end)
        if e and e.value > 0 then
            parts[#parts + 1] = { slot = slot, entry = e }
            total = total + e.value
        end
    end
    local enchant = bestOf(model.enchant, input, function()
        return true
    end)
    if enchant then
        parts[#parts + 1] = { slot = "enchant", entry = enchant }
        total = total + enchant.value
    end
    local lure = bestOf(model.lure, input, function(x)
        return x.own.equipped == true or (x.own.bags or 0) > 0
    end)
    if lure then
        total = total + lure.value
    end
    return { total = total, rank = input.rank, parts = parts, lure = lure }
end

-- input: { own(id) -> { bags, bank, equipped } or nil (API missing), tip(id) -> tooltip bonus,
-- false (no number), or nil (not read), raceBit (nil: unknown), level, rank, cap (rank cap),
-- modifier (skill modifier), lure (active lure enchant ID), gloves (fishing bonus on the equipped
-- gloves, false: none, nil: unknown) }. Returns the sections (GearModel.SECTIONS keys) plus
-- .measure and .best.
function GearModel.Build(journal, input)
    local model = {}
    for _, key in ipairs(GearModel.SECTIONS) do
        model[key] = {}
    end
    items(model, journal, input)
    others(model, journal, input)
    model.measure = measure(model, journal, input)
    model.best = GearModel.Best(model, input)
    return model
end
