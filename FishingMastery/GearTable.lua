-- Pure logic: the Gear tab of the journal window from a GearModel model: a heading row per
-- section (poles, other gear, lures, buff food, fishing ranks, enchants), then one row per entry
-- (item, bonus, needs, source, owned), the hover lines, the best setup line, and the line that sets
-- the equipped items against the bonus the game applies. Entries the player does not have, or
-- cannot use (race), are grey. No frame or API calls.
local _, ns = ...

local format, ipairs, concat = string.format, ipairs, table.concat
local L, StatsTables, GearModel = ns.L, ns.StatsTables, ns.GearModel

local GearTable = {}
ns.GearTable = GearTable

GearTable.COLUMNS = {
    { key = "item", label = L.GEAR_COL_ITEM, width = 200 },
    { key = "bonus", label = L.GEAR_COL_BONUS, width = 160 },
    { key = "needs", label = L.GEAR_COL_NEEDS, width = 130 },
    { key = "source", label = L.GEAR_COL_SOURCE, width = 180 },
    { key = "owned", label = L.GEAR_COL_OWNED, width = 102 },
}
GearTable.HEADING = { 1, 0.82, 0 } -- gold
GearTable.DERBY_QUEST = 8193 -- "Master Angler", the Stranglethorn Fishing Extravaganza
local GREY_ALL = { true, true, true, true, true }

local function itemText(input, id)
    return StatsTables.ItemText(id, input.info(id))
end

local function nameOf(e, input)
    if e.section == "rank" then
        return format(L.GEAR_RANK, L["GEAR_RANK_" .. e.key], e.cap)
    end
    if e.section == "enchant" then
        return input.spellName(e.spell) or format(L.GEAR_SPELL_LOADING, e.spell)
    end
    return itemText(input, e.id)
end

-- Values from the guides (the client table with them is not bundled): lures, food, enchants,
-- and the Forever items.
local function isGuide(e)
    return e.section == "lure"
        or e.section == "food"
        or e.section == "enchant"
        or e.source == "guide"
end

local function bonusText(e)
    if e.section == "rank" then
        return format(L.GEAR_CAP, e.cap)
    end
    local text
    if type(e.tip) == "number" and e.tip ~= e.bonus then
        text = format(L.GEAR_BONUS_DIFF, e.tip, e.bonus)
    elseif type(e.tip) == "number" then
        text = format(L.GEAR_BONUS_TIP, e.tip)
    elseif e.tip == false and e.bonus == 0 then
        text = format(L.GEAR_BONUS, 0) -- a pole without a bonus
    elseif e.tip == false then
        text = format(L.GEAR_BONUS_NO_LINE, e.bonus)
    elseif isGuide(e) then
        text = format(L.GEAR_BONUS_GUIDE, e.bonus)
    else
        text = format(L.GEAR_BONUS, e.bonus)
    end
    if e.game then
        text = text .. format(L.GEAR_BONUS_GAME, e.game)
    end
    return text
end

local function racesText(races)
    if races == GearModel.ALLIANCE then
        return L.GEAR_ALLIANCE
    elseif races == GearModel.HORDE then
        return L.GEAR_HORDE
    elseif (races or 0) ~= 0 then
        return L.GEAR_SOME_RACES
    end
    return nil
end

local function needsText(e)
    local parts = {}
    if e.section == "enchant" then
        parts[1] = format(L.GEAR_NEEDS_ENCHANTING, e.skill)
    elseif (e.skill or 0) > 1 then
        parts[1] = format(L.GEAR_NEEDS_SKILL, e.skill)
    end
    if (e.level or 0) > 0 then
        parts[#parts + 1] = format(L.GEAR_NEEDS_LEVEL, e.level)
    end
    parts[#parts + 1] = racesText(e.races)
    return #parts > 0 and concat(parts, ", ") or L.JOURNAL_NO_PLACE
end

local function sourceText(e, input)
    local word = L["GEAR_SOURCE_" .. e.source] or e.source
    if e.source == "quest" and (e.quest or 0) > 0 then
        local name = input.questName(e.quest) or format(L.GEAR_QUEST_LOADING, e.quest)
        word =
            format(e.quest == GearTable.DERBY_QUEST and L.GEAR_SOURCE_DERBY or L.GEAR_QUEST, name)
    end
    if e.section == "rank" and e.id then
        return format(L.GEAR_SOURCE_BOOK, itemText(input, e.id), word)
    end
    if e.section == "enchant" then
        return format(L.GEAR_SOURCE_FORMULA, word)
    end
    return word
end

local function ownText(e)
    if e.section == "rank" then
        if e.reached == nil then
            return "?"
        end
        return e.reached and L.GEAR_LEARNED or L.GEAR_NOT_YET
    end
    if e.section == "enchant" then
        if e.on == nil then
            return "?"
        end
        return e.has and L.GEAR_ON_GLOVES or L.RECIPES_NO
    end
    if not e.usable then
        return racesText(e.races) or L.GEAR_NOT_FOR_YOU
    end
    local own = e.own
    if not own then
        return "?"
    end
    if own.equipped then
        return L.GEAR_EQUIPPED
    end
    local parts = {}
    if (own.bags or 0) > 0 then
        parts[1] = format(L.GEAR_BAGS, own.bags)
    end
    if (own.bank or 0) > 0 then
        parts[#parts + 1] = format(L.GEAR_BANK, own.bank)
    end
    return #parts > 0 and concat(parts, ", ") or L.RECIPES_NO
end

local function has(e)
    if e.section == "rank" then
        return e.reached == true
    end
    return e.has and e.usable
end

-- Hover lines of one entry.
function GearTable.Tooltip(e, input)
    local lines = { nameOf(e, input), L["GEAR_SECTION_" .. e.section] }
    local function add(...)
        lines[#lines + 1] = format(...)
    end
    if e.section ~= "rank" then
        add(isGuide(e) and L.GEAR_T_GUIDE or L.GEAR_T_DATA, e.bonus)
    end
    if type(e.tip) == "number" then
        add(L.GEAR_T_TIP, e.tip)
    elseif e.tip == false then
        add("%s", L.GEAR_T_NO_LINE)
    end
    if e.game then
        add(L.GEAR_T_GAME, e.game)
    end
    if e.kind == "lure" and e.section == "lure" and e.slot then
        add("%s", L.GEAR_T_LURE_HAT)
    end
    add(L.GEAR_T_NEEDS, needsText(e))
    add(L.GEAR_T_SOURCE, sourceText(e, input))
    add(L.GEAR_T_OWNED, ownText(e))
    return lines
end

local function row(e, input)
    return {
        id = e.id,
        grey = not has(e) and GREY_ALL or nil,
        cells = { nameOf(e, input), bonusText(e), needsText(e), sourceText(e, input), ownText(e) },
        tooltip = GearTable.Tooltip(e, input),
    }
end

-- input: { info(id) -> { name, icon, hex }, spellName(spell), questName(quest) }. Returns the list
-- rows: a gold heading row per section, then its entries.
function GearTable.Rows(model, input)
    local rows = {}
    for _, key in ipairs(GearModel.SECTIONS) do
        rows[#rows + 1] =
            { heading = key, color = GearTable.HEADING, cells = { L["GEAR_SECTION_" .. key] } }
        for _, e in ipairs(model[key]) do
            rows[#rows + 1] = row(e, input)
        end
    end
    return rows
end

-- "Best setup: Fishing 150 + pole 20 + head 5 + lure 50 = 225 (now 175)."
function GearTable.Best(model, now)
    local best = model.best
    if not best then
        return L.GEAR_BEST_UNKNOWN
    end
    local parts = { format(L.GEAR_BEST_RANK, best.rank) }
    for _, part in ipairs(best.parts) do
        parts[#parts + 1] = format(L.GEAR_BEST_PART, L["GEAR_SLOT_" .. part.slot], part.entry.value)
    end
    if best.lure then
        parts[#parts + 1] = format(L.GEAR_BEST_PART, L.GEAR_SLOT_lure, best.lure.value)
    end
    local line = format(L.GEAR_BEST, concat(parts, " + "), best.total)
    if type(now) == "number" then
        line = line .. format(L.GEAR_BEST_NOW, now)
    end
    return line .. "."
end

-- The equipped items against the bonus the game applies (skill modifier without the lure).
function GearTable.Measure(model)
    local m = model.measure
    if not m.game then
        return L.GEAR_MEASURE_UNKNOWN
    end
    if m.game == m.items then
        return format(L.GEAR_MEASURE_SAME, m.items)
    end
    return format(L.GEAR_MEASURE_DIFF, m.items, m.game)
end
