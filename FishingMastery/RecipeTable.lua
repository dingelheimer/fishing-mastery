-- Pure logic: the Recipes tab of the journal window from a RecipeModel list: one row per recipe
-- (product, profession, reagents with counts and own stock, color ranks, learn skill and source,
-- fishing buff, known), the hover lines with the full details, and the progress line. Filters: the
-- recipes of one fish (from the Fish tab) and known or not. Recipes the character does not know
-- are grey. No frame or API calls.
local _, ns = ...

local format, ipairs, concat, tostring = string.format, ipairs, table.concat, tostring
local L, StatsTables = ns.L, ns.StatsTables

local RecipeTable = {}
ns.RecipeTable = RecipeTable

RecipeTable.SHOWS = { "all", "known", "unknown" }
RecipeTable.COLUMNS = {
    { key = "recipe", label = L.RECIPES_COL_RECIPE, width = 180 },
    { key = "profession", label = L.RECIPES_COL_PROFESSION, width = 64 },
    { key = "reagents", label = L.RECIPES_COL_REAGENTS, width = 240 },
    { key = "colors", label = L.RECIPES_COL_COLORS, width = 64, right = true },
    { key = "learn", label = L.RECIPES_COL_LEARN, width = 104 },
    { key = "buff", label = L.RECIPES_COL_BUFF, width = 80 },
    { key = "known", label = L.RECIPES_COL_KNOWN, width = 56 },
}
local GREY_ALL = { true, true, true, true, true, true, true }

local function professionName(entry)
    return entry.profession and L["JOURNAL_SKILL_" .. entry.profession] or L.JOURNAL_NO_PLACE
end

local function itemName(input, id)
    return input.info(id).name or format(L.HUD_ITEM_LOADING, id)
end

local function productText(entry, input)
    if entry.product then
        return StatsTables.ItemText(entry.product, input.info(entry.product))
    end
    return input.spellName(entry.spell) or format(L.JOURNAL_SPELL_LOADING, entry.spell)
end

local function stockText(input, id)
    local stock = input.stock(id)
    return stock and tostring(stock) or "?"
end

local function reagentsText(entry, input)
    local parts = {}
    for i, reagent in ipairs(entry.reagents) do
        parts[i] = format(
            L.RECIPES_REAGENT,
            itemName(input, reagent[1]),
            reagent[2],
            stockText(input, reagent[1])
        )
    end
    return concat(parts, ", ")
end

local function learnText(entry)
    if entry.forever then
        return L.RECIPES_READ
    end
    return format(L.RECIPES_LEARN, entry.learn, L["RECIPES_SOURCE_" .. entry.source] or "")
end

local function buffText(entry)
    local food = entry.food
    if not food then
        return ""
    end
    return format(L.RECIPES_BUFF, food.bonus, L["RECIPES_VALUE_" .. food.source] or "")
end

local function knownText(known)
    if known == nil then
        return "?"
    end
    return known and L.RECIPES_YES or L.RECIPES_NO
end

local function uses(entry, item)
    for _, reagent in ipairs(entry.reagents) do
        if reagent[1] == item then
            return true
        end
    end
    return false
end

local function matches(entry, filters, known)
    if filters.fish and not uses(entry, filters.fish) then
        return false
    end
    if filters.show == "known" and known ~= true then
        return false
    end
    if filters.show == "unknown" and known ~= false then
        return false
    end
    return true
end

-- Hover lines of one recipe.
function RecipeTable.Tooltip(entry, input, known)
    local lines = { productText(entry, input) }
    local function add(...)
        lines[#lines + 1] = format(...)
    end
    add("%s", professionName(entry))
    add("%s", L.RECIPES_T_REAGENTS)
    for _, reagent in ipairs(entry.reagents) do
        add(
            L.RECIPES_T_REAGENT,
            itemName(input, reagent[1]),
            reagent[2],
            stockText(input, reagent[1])
        )
    end
    if entry.low then
        add(L.RECIPES_T_COLORS, entry.low, entry.high)
    end
    if entry.forever then
        add("%s", L.RECIPES_T_FOREVER)
    else
        add(
            L.RECIPES_T_LEARN,
            professionName(entry),
            entry.learn,
            L["RECIPES_SOURCE_" .. entry.source] or ""
        )
        if entry.read then
            add("%s", L.RECIPES_T_READ)
        end
    end
    local food = entry.food
    if food then
        add(L.RECIPES_T_BUFF, food.bonus, food.level, L["RECIPES_VALUE_" .. food.source] or "")
    end
    add(L.RECIPES_T_KNOWN, knownText(known))
    return lines
end

-- input: { info(id) -> { name, icon, hex }, spellName(spell), known(spell) -> true, false, or nil
-- (unknown), stock(itemID) -> count in bags and bank or nil }. filters: { fish (item ID or nil),
-- show ("all", "known", "unknown") }. Returns the list rows (data.spell = recipe spell).
function RecipeTable.Rows(list, input, filters)
    local rows = {}
    for _, entry in ipairs(list) do
        local known = input.known(entry.spell)
        if matches(entry, filters, known) then
            local cells = {
                productText(entry, input),
                professionName(entry),
                reagentsText(entry, input),
                entry.low and format(L.RECIPES_COLORS, entry.low, entry.high) or L.JOURNAL_NO_PLACE,
                learnText(entry),
                buffText(entry),
                knownText(known),
            }
            rows[#rows + 1] = {
                spell = entry.spell,
                grey = known ~= true and GREY_ALL or nil,
                cells = cells,
                tooltip = RecipeTable.Tooltip(entry, input, known),
            }
        end
    end
    return rows
end

-- "23 recipes (19 Cooking, 4 Alchemy) + 2 read in game; this character knows 5." With a fish
-- filter: "Recipes with Raw Brilliant Smallfish: 2." first.
function RecipeTable.Progress(list, input, filters)
    local bundled, forever, known, by = 0, 0, 0, {}
    for _, entry in ipairs(list) do
        if entry.forever then
            forever = forever + 1
        else
            bundled = bundled + 1
            by[entry.profession] = (by[entry.profession] or 0) + 1
        end
        if input.known(entry.spell) == true then
            known = known + 1
        end
    end
    local line = format(L.RECIPES_PROGRESS, bundled, by[185] or 0, by[171] or 0)
    if forever > 0 then
        line = line .. format(L.RECIPES_PROGRESS_READ, forever)
    end
    line = line .. format(L.RECIPES_PROGRESS_KNOWN, known)
    if filters.fish then
        local n = 0
        for _, entry in ipairs(list) do
            n = n + (uses(entry, filters.fish) and 1 or 0)
        end
        line = format(L.RECIPES_PROGRESS_FISH, itemName(input, filters.fish), n) .. "  " .. line
    end
    return line
end
