-- Trade skill read for the journal API check (dev flag only): on TRADE_SKILL_SHOW, Dev.lua calls
-- JournalTrade.Run, which reads the line name, the recipe count, and for the first
-- JournalCheck.TRADE_RECIPES recipes the product, recipe spell, and reagent item IDs with counts.
-- Recipe names are printed but not saved. Each read also holds the C_TradeSkillUI read
-- (JournalTradeUI.lua) and is repeated once after JournalTrade.LATER seconds. Appends to
-- FishingMasteryDB.dev.journal.trades.
local _, ns = ...

local format, concat, ipairs, tostring, match, tonumber =
    string.format, table.concat, ipairs, tostring, string.match, tonumber
local L = ns.L
local Call = ns.Context.Call
local JournalCheck = ns.JournalCheck
local text, number = JournalCheck.Text, JournalCheck.Number

local JournalTrade = {}
ns.JournalTrade = JournalTrade

-- ID from a hyperlink: |Hitem:6291:...|h, |Henchant:7751|h, or |Hspell:7751|h.
function JournalTrade.LinkID(link, kind)
    link = text(link)
    return link and tonumber(match(link, "|H" .. kind .. ":(%d+)")) or nil
end

-- Reads the first TRADE_RECIPES recipes (headers skipped) of the open trade skill window.
function JournalTrade.Read(env, at)
    local trade = { at = at, fired = true, recipes = {} }
    trade.line = text(Call(env, "GetTradeSkillLine"))
    trade.num = number(Call(env, "GetNumTradeSkills"))
    for i = 1, trade.num or 0 do
        if #trade.recipes >= JournalCheck.TRADE_RECIPES then
            break
        end
        local name, kind = Call(env, "GetTradeSkillInfo", i)
        if text(kind) ~= "header" and text(name) then
            local recipe = {
                index = i,
                product = JournalTrade.LinkID(Call(env, "GetTradeSkillItemLink", i), "item"),
                reagents = {},
            }
            local link = Call(env, "GetTradeSkillRecipeLink", i)
            recipe.spell = JournalTrade.LinkID(link, "enchant")
                or JournalTrade.LinkID(link, "spell")
            for r = 1, number(Call(env, "GetTradeSkillNumReagents", i)) or 0 do
                local _, _, needed = Call(env, "GetTradeSkillReagentInfo", i, r)
                recipe.reagents[r] = {
                    id = JournalTrade.LinkID(
                        Call(env, "GetTradeSkillReagentItemLink", i, r),
                        "item"
                    ),
                    count = number(needed),
                }
            end
            trade.recipes[#trade.recipes + 1] = recipe
            trade.names = trade.names or {}
            trade.names[#trade.recipes] = text(name) -- printed only, removed before saving
        end
    end
    return trade
end

JournalTrade.LATER = 1 -- seconds after TRADE_SKILL_SHOW for the second read (list may load late)

local function printRecipes(recipes, names, spellKey)
    for i = 1, math.min(#recipes, JournalCheck.TRADE_RECIPES) do
        local recipe, parts = recipes[i], {}
        for _, reagent in ipairs(recipe.reagents) do
            parts[#parts + 1] = format("%s x%s", tostring(reagent.id), tostring(reagent.count))
        end
        ns.Print(
            format(
                L.JCHECK_TRADE_RECIPE,
                tostring(names[i]),
                tostring(recipe[spellKey]),
                tostring(recipe.product),
                #parts > 0 and concat(parts, ", ") or "-"
            )
        )
    end
end

-- deps: { env, db, serverTime, after(seconds, fn) or nil }. Called on TRADE_SKILL_SHOW while the
-- dev flag is on (phase nil = "show"); schedules one more read JournalTrade.LATER seconds later.
function JournalTrade.Run(deps, phase)
    local trade = JournalTrade.Read(deps.env, deps.serverTime())
    trade.phase = phase or "show"
    local names = trade.names or {}
    trade.names = nil
    local modernNames
    trade.modern, modernNames = ns.JournalTradeUI.Read(deps.env)
    local j = JournalCheck.Store(deps.db)
    JournalCheck.Push(j.trades, trade)
    ns.Print(
        format(L.JCHECK_TRADE, trade.phase, tostring(trade.line), tostring(trade.num), #j.trades)
    )
    printRecipes(trade.recipes, names, "spell")
    local m = trade.modern
    ns.Print(
        format(
            L.JCHECK_TRADE_UI,
            m.api and #m.api or 0,
            tostring(m.profession),
            tostring(m.professionName),
            tostring(m.skill),
            tostring(m.maxSkill),
            tostring(m.total),
            tostring(m.learned)
        )
    )
    printRecipes(m.recipes, modernNames, "id")
    if not phase and deps.after then
        deps.after(JournalTrade.LATER, function()
            ns.Guard.Call("dev:trade", JournalTrade.Run, deps, "later")
        end)
    end
    return trade
end
