-- Journal API check (/fm dev journal, dev flag only): reads the spell, tooltip, and item APIs the
-- journal depends on (Epic 5) for fixed lists of recipe spells, new Forever spells, gear items,
-- and one fish per journal group. While the dev flag is on, opening a trade skill window logs one
-- trade read (Dev.lua calls JournalCheck.Trade on TRADE_SKILL_SHOW). Missing APIs are reported by
-- name; nothing raises. Saved under FishingMasteryDB.dev.journal: IDs, counts, and the game's own
-- tooltip and spell texts; no character names or GUIDs.
local _, ns = ...

local type, format, concat, ipairs, tostring, gmatch, match, sub, remove =
    type,
    string.format,
    table.concat,
    ipairs,
    tostring,
    string.gmatch,
    string.match,
    string.sub,
    table.remove
local L = ns.L
local Call = ns.Context.Call
local isSecret = issecretvalue or function()
    return false
end

local JournalCheck = {}
ns.JournalCheck = JournalCheck

JournalCheck.CAP = 10 -- runs and trade reads kept each; the oldest is dropped first
JournalCheck.TRADE_RECIPES = 3 -- recipes read per trade skill window
JournalCheck.TIP_LINES = 12 -- tooltip lines kept per item
JournalCheck.TEXT_MAX = 120 -- characters kept per saved text

JournalCheck.APIS = {
    "IsSpellKnown",
    "IsPlayerSpell",
    "GetSpellInfo",
    "C_Spell.GetSpellInfo",
    "C_TooltipInfo.GetItemByID",
    "C_Item.GetItemCount",
    "C_Item.GetItemInfoInstant",
    "C_Item.RequestLoadItemDataByID",
    "GetInventoryItemID",
    "GetNumTradeSkills",
    "GetTradeSkillLine",
    "GetTradeSkillInfo",
    "GetTradeSkillItemLink",
    "GetTradeSkillRecipeLink",
    "GetTradeSkillNumReagents",
    "GetTradeSkillReagentInfo",
    "GetTradeSkillReagentItemLink",
}

-- Bundled Classic recipe spells (Journal research): Cooking from skill 1 and 275, Alchemy, a drop.
JournalCheck.RECIPES = { 7751, 7752, 18246, 7836, 8238 }
-- Spells on the Forever Fishing line not in CMaNGOS (all 9) and 5 of the 55 new Cooking spells.
-- stylua: ignore
JournalCheck.NEW_SPELLS = {
    43308, 1229745, 1240948, 1240959, 1240970, 1240983, 1262990, 1262998, 1278067,
    1225758, 1240945, 1249957, 1250142, 1270632,
}
-- Fishing gear: 8 obtainable Classic items, the line, the basic pole, and 4 Forever items.
-- stylua: ignore
JournalCheck.GEAR = {
    19970, 19022, 6367, 6366, 6365, 19969, 19972, 12225, 19971, 6256,
    259846, 276272, 276203, 244229,
}
-- One item per journal group: fish, trophy fish, container, bloated fish, quest fish, potion,
-- junk, other.
JournalCheck.GROUP_ITEMS = { 6291, 6292, 6351, 6643, 16967, 118, 6297, 3857 }

local function plain(value)
    if isSecret(value) then
        return nil
    end
    return value
end

local function text(value)
    value = plain(value)
    return type(value) == "string" and sub(value, 1, JournalCheck.TEXT_MAX) or nil
end

local function number(value)
    value = plain(value)
    return type(value) == "number" and value or nil
end

local function flag(value)
    value = plain(value)
    if value == nil then
        return nil
    end
    return value and value ~= 0 or false
end

local function exists(env, path)
    local value = env
    for key in gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then
            return false
        end
        value = value[key]
    end
    return type(value) == "function"
end

local function spellName(env, id)
    local info = Call(env, "C_Spell.GetSpellInfo", id)
    local name = type(info) == "table" and text(info.name) or nil
    return name or text(Call(env, "GetSpellInfo", id))
end

local function spells(env, list, known)
    local out = {}
    for i, id in ipairs(list) do
        local entry = { id = id, name = spellName(env, id) }
        if known then
            entry.known = flag(Call(env, "IsSpellKnown", id))
            entry.player = flag(Call(env, "IsPlayerSpell", id))
        end
        out[i] = entry
    end
    return out
end

-- Tooltip lines of an item; nil when the API is missing or the item is not loaded yet.
local function tipLines(env, id)
    local data = Call(env, "C_TooltipInfo.GetItemByID", id)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return nil
    end
    local lines = {}
    for _, line in ipairs(data.lines) do
        local left = type(line) == "table" and text(line.leftText)
        if left and left ~= "" then
            lines[#lines + 1] = left
            if #lines >= JournalCheck.TIP_LINES then
                break
            end
        end
    end
    return lines
end

local function gear(env)
    local out = {}
    for i, id in ipairs(JournalCheck.GEAR) do
        Call(env, "C_Item.RequestLoadItemDataByID", id)
        out[i] = {
            id = id,
            tip = tipLines(env, id),
            bags = number(Call(env, "C_Item.GetItemCount", id)),
            bank = number(Call(env, "C_Item.GetItemCount", id, true)),
        }
    end
    return out
end

local function groups(env)
    local out = {}
    for i, id in ipairs(JournalCheck.GROUP_ITEMS) do
        local info = { Call(env, "C_Item.GetItemInfoInstant", id) }
        out[i] = { id = id, class = number(info[6]), subclass = number(info[7]) }
    end
    return out
end

-- One run; returns the saved entry.
function JournalCheck.Read(env, at)
    local run = { at = at, missing = {} }
    for _, path in ipairs(JournalCheck.APIS) do
        if not exists(env, path) then
            run.missing[#run.missing + 1] = path
        end
    end
    run.recipes = spells(env, JournalCheck.RECIPES, true)
    run.newSpells = spells(env, JournalCheck.NEW_SPELLS, false)
    run.gear = gear(env)
    run.groups = groups(env)
    local rank, modifier = ns.Context.Fishing(env)
    local pole = number(Call(env, "GetInventoryItemID", "player", 16))
    run.fishing = { rank = rank, modifier = modifier, pole = pole }
    run.fishing.tip = pole and tipLines(env, pole) or nil
    return run
end

local function count(list, test)
    local n = 0
    for _, entry in ipairs(list) do
        n = n + (test(entry) and 1 or 0)
    end
    return n
end

-- Tooltip lines that name a skill bonus ("+N"); the full lines are in the saved run.
local function bonusLines(tip)
    local parts = {}
    for _, line in ipairs(tip or {}) do
        if match(line, "%+%s*%d") then
            parts[#parts + 1] = line
        end
    end
    return #parts > 0 and concat(parts, " / ") or "-"
end

-- Chat lines for one run.
function JournalCheck.Lines(run)
    local lines = {}
    local function add(...)
        lines[#lines + 1] = format(...)
    end
    for _, r in ipairs(run.recipes) do
        add(L.JCHECK_RECIPE, r.id, tostring(r.name), tostring(r.known), tostring(r.player))
    end
    local named = count(run.newSpells, function(entry)
        return entry.name
    end)
    local names = {}
    for _, entry in ipairs(run.newSpells) do
        names[#names + 1] = format("%d %s", entry.id, entry.name or "?")
    end
    add(L.JCHECK_SPELLS, named, #run.newSpells, concat(names, ", "))
    for _, g in ipairs(run.gear) do
        add(
            L.JCHECK_GEAR,
            g.id,
            g.tip and tostring(g.tip[1]) or L.JCHECK_NOT_LOADED,
            tostring(g.bags),
            tostring(g.bank),
            g.tip and bonusLines(g.tip) or "-"
        )
    end
    local parts = {}
    for _, g in ipairs(run.groups) do
        parts[#parts + 1] = format("%d=%s/%s", g.id, tostring(g.class), tostring(g.subclass))
    end
    add(L.JCHECK_GROUPS, concat(parts, ", "))
    local f = run.fishing
    add(
        L.JCHECK_FISHING,
        tostring(f.rank),
        tostring(f.modifier),
        tostring(f.pole),
        f.tip and bonusLines(f.tip) or "-"
    )
    add(L.JCHECK_MISSING, #run.missing > 0 and concat(run.missing, ", ") or "-")
    return lines
end

local function store(db)
    local dev = ns.Stress.Dev(db)
    local j = dev.journal
    if type(j) ~= "table" or type(j.runs) ~= "table" or type(j.trades) ~= "table" then
        j = { runs = {}, trades = {} }
        dev.journal = j
    end
    return j
end

local function push(list, entry)
    list[#list + 1] = entry
    while #list > JournalCheck.CAP do
        remove(list, 1)
    end
end

-- Shared with JournalTrade.lua.
JournalCheck.Text, JournalCheck.Number, JournalCheck.Store, JournalCheck.Push =
    text, number, store, push

-- deps: { env, db, serverTime }. Runs the check, prints it, appends it to dev.journal.runs.
function JournalCheck.Run(deps, action)
    if action == "clear" then
        ns.Stress.Dev(deps.db).journal = { runs = {}, trades = {} }
        ns.Print(L.JCHECK_CLEARED)
        return
    end
    local j = store(deps.db)
    local run = JournalCheck.Read(deps.env, deps.serverTime())
    push(j.runs, run)
    ns.Print(format(L.JCHECK_HEADER, #j.runs, JournalCheck.CAP, #j.trades))
    for _, line in ipairs(JournalCheck.Lines(run)) do
        ns.Print(line)
    end
    return run
end
