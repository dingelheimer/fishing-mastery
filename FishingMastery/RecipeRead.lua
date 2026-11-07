-- Recipe read for the journal (every player): when the player opens a profession window
-- (TRADE_SKILL_SHOW), every learned recipe that uses a journal item is stored once per account
-- (RecipeModel). The recipe list is still loading at the event (Story 5.1: 3 of 132 IDs), so the
-- read waits RecipeRead.DELAY seconds and then until C_TradeSkillUI.IsTradeSkillReady is true (at
-- most RecipeRead.TRIES checks). Products and reagents come from JournalTradeUI.Recipe. Without
-- C_TradeSkillUI nothing is read. Stores IDs and counts only; recipe names are never saved.
local _, ns = ...

local format, type, ipairs, setmetatable = string.format, type, ipairs, setmetatable
local L, Context = ns.L, ns.Context
local Call = Context.Call

local RecipeRead = {}
RecipeRead.__index = RecipeRead
ns.RecipeRead = RecipeRead

RecipeRead.DELAY = 1 -- seconds after TRADE_SKILL_SHOW before the first check
RecipeRead.TRIES = 5 -- readiness checks, one per DELAY

local function number(value)
    value = ns.JournalCheck.Number(value)
    return type(value) == "number" and value or nil
end

-- Skill line of a recipe: its profession info (parent line first), else the window's base line.
local function profession(env, id, base)
    local info = Call(env, "C_TradeSkillUI.GetProfessionInfoByRecipeID", id)
    if type(info) == "table" then
        local line = number(info.parentProfessionID) or number(info.professionID)
        if line and line > 0 then
            return line
        end
    end
    return base
end

-- Every learned recipe of the open window: { { id, profession, product, reagents } }.
function RecipeRead.Read(env)
    local ids = Call(env, "C_TradeSkillUI.GetAllRecipeIDs")
    if type(ids) ~= "table" then
        return {}
    end
    local base = Call(env, "C_TradeSkillUI.GetBaseProfessionInfo")
    base = type(base) == "table" and number(base.professionID) or nil
    local read = {}
    for _, id in ipairs(ids) do
        id = number(id)
        local info = id and Call(env, "C_TradeSkillUI.GetRecipeInfo", id)
        if type(info) == "table" and info.learned == true then
            local recipe = ns.JournalTradeUI.Recipe(env, id)
            recipe.profession = profession(env, id, base)
            read[#read + 1] = recipe
        end
    end
    return read
end

-- deps: { env, bus, db (FishingMasteryDB), isJournal(itemID), after(seconds, fn) or nil,
-- onStored() (the journal redraws) }.
function RecipeRead.Start(deps)
    local self = setmetatable({
        env = deps.env,
        db = deps.db,
        isJournal = deps.isJournal,
        after = deps.after,
        onStored = deps.onStored,
    }, RecipeRead)
    deps.bus:On("TRADE_SKILL_SHOW", function()
        self:Schedule()
    end)
    return self
end

-- Reads and stores now; prints how many recipes were new. Returns added, changed.
function RecipeRead:Run()
    local store = ns.RecipeModel.Store(self.db)
    local added, changed = ns.RecipeModel.Merge(store, RecipeRead.Read(self.env), self.isJournal)
    if added > 0 then
        ns.Print(format(L.RECIPES_STORED, added))
    end
    if (added > 0 or changed > 0) and self.onStored then
        self.onStored()
    end
    return added, changed
end

local function check(self, try)
    local ready = Call(self.env, "C_TradeSkillUI.IsTradeSkillReady")
    if ready == false and try < RecipeRead.TRIES then
        self.after(RecipeRead.DELAY, function()
            check(self, try + 1)
        end)
        return
    end
    self.pending = false
    self:Run()
end

-- One read per window opening, once the list has loaded.
function RecipeRead:Schedule()
    if type(self.env.C_TradeSkillUI) ~= "table" or self.pending then
        return
    end
    if not self.after then
        self:Run()
        return
    end
    self.pending = true
    self.after(RecipeRead.DELAY, function()
        check(self, 1)
    end)
end
