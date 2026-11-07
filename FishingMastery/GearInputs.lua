-- Gear tab inputs read from the game (the GearModel.Build input): where the player has each item
-- (C_Item.GetItemCount with and without the bank, the equipped slots), the fishing bonus on an
-- item's tooltip (C_TooltipInfo.GetItemByID) and on the equipped gloves, race, level, fishing
-- rank, rank cap, skill modifier, and the active lure. Every call is protected; a missing API gives
-- nil, shown as "?". Tooltip text is matched as data only (GearModel.TipBonus); only the parsed
-- number is kept, for the session.
local _, ns = ...

local type, ipairs, select = type, ipairs, select
local Context = ns.Context

local GearInputs = {}
ns.GearInputs = GearInputs

GearInputs.SLOTS = { 1, 8, 10, 16 } -- head, feet, hands, main hand (the pole)
GearInputs.HANDS = 10
GearInputs.RACE_ID = 3 -- UnitRace: raceID

local function lines(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return nil
    end
    local out = {}
    for _, line in ipairs(data.lines) do
        local left = type(line) == "table" and line.leftText
        if type(left) == "string" then
            out[#out + 1] = left
        end
    end
    return out
end

local function number(value)
    return type(value) == "number" and value or nil
end

-- Fishing bonus on the equipped gloves (the enchant line): a number, false (no gloves or no
-- line), or nil (unknown).
local function gloves(env, skillName)
    if not skillName then
        return nil
    end
    if not number(Context.Call(env, "GetInventoryItemID", "player", GearInputs.HANDS)) then
        return false
    end
    local data = Context.Call(env, "C_TooltipInfo.GetInventoryItem", "player", GearInputs.HANDS)
    return ns.GearModel.TipBonus(lines(data), skillName, nil)
end

-- cache: { tips = {} }, kept by the window (tooltip values do not change in a session).
-- loaded(id): true once the item's data is loaded (the first tooltip only says "Retrieving").
function GearInputs.Read(env, cache, loaded)
    local skillName = Context.FishingName(env)
    local prefix = type(env.ITEM_SPELL_TRIGGER_ONEQUIP) == "string"
            and env.ITEM_SPELL_TRIGGER_ONEQUIP
        or nil
    local equipped = {}
    for _, slot in ipairs(GearInputs.SLOTS) do
        local id = number(Context.Call(env, "GetInventoryItemID", "player", slot))
        if id then
            equipped[id] = true
        end
    end
    local rank, modifier, cap = Context.Fishing(env)
    local race = number(select(GearInputs.RACE_ID, Context.Call(env, "UnitRace", "player")))
    return {
        own = function(id)
            local all = number(Context.Call(env, "C_Item.GetItemCount", id, true))
            local bags = number(Context.Call(env, "C_Item.GetItemCount", id, false))
            if not (all and bags) then
                return nil
            end
            -- Both counts include the equipped item (Story 5.1).
            local on = equipped[id] == true
            local inBags = bags - (on and 1 or 0)
            return {
                equipped = on,
                bags = inBags > 0 and inBags or 0,
                bank = all > bags and all - bags or 0,
            }
        end,
        tip = function(id)
            local tips = cache.tips
            if tips[id] == nil and skillName and loaded(id) then
                local data = Context.Call(env, "C_TooltipInfo.GetItemByID", id)
                local value = ns.GearModel.TipBonus(lines(data), skillName, prefix)
                if value ~= nil then
                    tips[id] = value
                end
            end
            return tips[id]
        end,
        raceBit = race and race >= 1 and 2 ^ (race - 1) or nil,
        level = number(Context.Call(env, "UnitLevel", "player")),
        rank = rank,
        cap = cap,
        modifier = modifier,
        lure = Context.Lure(env),
        gloves = gloves(env, skillName),
    }
end

-- Client name of a quest (C_QuestLog), or nil until it is loaded or without the API.
function GearInputs.QuestName(env, quest)
    local name = Context.Call(env, "C_QuestLog.GetTitleForQuestID", quest)
    if type(name) ~= "string" or name == "" then
        name = Context.Call(env, "C_QuestLog.GetQuestInfo", quest)
    end
    return type(name) == "string" and name ~= "" and name or nil
end

-- The Gear tab model and its table input for a journal window.
function GearInputs.Model(window)
    window.gearCache = window.gearCache or { tips = {} }
    local env, input = window.env, window:Inputs(nil, {})
    input.questName = function(quest)
        return GearInputs.QuestName(env, quest)
    end
    local gear = GearInputs.Read(env, window.gearCache, function(id)
        return input.info(id).name ~= nil
    end)
    return ns.GearModel.Build(window.journal, gear), input, gear
end
