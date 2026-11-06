-- C_TradeSkillUI read for the journal API check (dev flag only). The Forever client has no Classic
-- trade skill API (Story 5.1 run 1), so JournalTrade.Run also calls JournalTradeUI.Read: the
-- C_TradeSkillUI function names that exist, the base profession, every recipe ID with its learned
-- flag, and for learned recipes (capped) the product and reagent item IDs with counts, from
-- GetRecipeSchematic or, if missing, the older GetRecipeReagentInfo family. Recipe names are
-- returned separately for printing and never saved.
local _, ns = ...

local type, pairs, ipairs, sort, tostring = type, pairs, ipairs, table.sort, tostring
local Call = ns.Context.Call
local JournalCheck = ns.JournalCheck
local text, number = JournalCheck.Text, JournalCheck.Number

local JournalTradeUI = {}
ns.JournalTradeUI = JournalTradeUI

JournalTradeUI.API_CAP = 150 -- C_TradeSkillUI function names kept
JournalTradeUI.LEARNED_CAP = 60 -- learned recipes read in full

local function apiNames(env)
    local api = env.C_TradeSkillUI
    if type(api) ~= "table" then
        return nil
    end
    local names = {}
    for key, value in pairs(api) do
        if type(key) == "string" and type(value) == "function" then
            names[#names + 1] = key
        end
    end
    sort(names)
    for i = #names, JournalTradeUI.API_CAP + 1, -1 do
        names[i] = nil
    end
    return names
end

local function fromSchematic(env, id, recipe)
    local schematic = Call(env, "C_TradeSkillUI.GetRecipeSchematic", id, false)
    if type(schematic) ~= "table" then
        return false
    end
    recipe.via = "schematic"
    recipe.product = number(schematic.outputItemID)
    local slots = type(schematic.reagentSlotSchematics) == "table"
            and schematic.reagentSlotSchematics
        or {}
    for _, slot in ipairs(slots) do
        local first = type(slot) == "table" and type(slot.reagents) == "table" and slot.reagents[1]
        recipe.reagents[#recipe.reagents + 1] = {
            id = type(first) == "table" and number(first.itemID) or nil,
            count = type(slot) == "table" and number(slot.quantityRequired) or nil,
        }
    end
    return true
end

local function fromReagentInfo(env, id, recipe)
    local count = number(Call(env, "C_TradeSkillUI.GetRecipeNumReagents", id))
    if not count then
        return
    end
    recipe.via = "reagentInfo"
    local LinkID = ns.JournalTrade.LinkID
    recipe.product = LinkID(Call(env, "C_TradeSkillUI.GetRecipeItemLink", id), "item")
    for r = 1, count do
        local _, _, needed = Call(env, "C_TradeSkillUI.GetRecipeReagentInfo", id, r)
        recipe.reagents[r] = {
            id = LinkID(Call(env, "C_TradeSkillUI.GetRecipeReagentItemLink", id, r), "item"),
            count = number(needed),
        }
    end
end

-- Returns the saved part and the recipe names (index matches read.recipes) for printing.
function JournalTradeUI.Read(env)
    local read = { api = apiNames(env), recipes = {} }
    local names = {}
    if not read.api then
        return read, names
    end
    local base = Call(env, "C_TradeSkillUI.GetBaseProfessionInfo")
    if type(base) == "table" then
        read.profession = number(base.professionID)
        read.professionName = text(base.professionName)
        read.skill, read.maxSkill = number(base.skillLevel), number(base.maxSkillLevel)
    end
    local ids = Call(env, "C_TradeSkillUI.GetAllRecipeIDs")
    ids = type(ids) == "table" and ids or {}
    read.total, read.learned = #ids, 0
    for _, id in ipairs(ids) do
        id = number(id)
        local info = id and Call(env, "C_TradeSkillUI.GetRecipeInfo", id)
        if type(info) == "table" and info.learned == true then
            read.learned = read.learned + 1
            if #read.recipes < JournalTradeUI.LEARNED_CAP then
                local recipe = { id = id, reagents = {} }
                if not fromSchematic(env, id, recipe) then
                    fromReagentInfo(env, id, recipe)
                end
                read.recipes[#read.recipes + 1] = recipe
                names[#read.recipes] = text(info.name) or tostring(id)
            end
        end
    end
    return read, names
end
