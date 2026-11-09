-- The smart lure (module 5, Story 8.3; setting "autoLure", off by default): reads the water's
-- base skill, the skill without the running lure, the lures in the bags, and the running lure,
-- and lets LureChoice decide what the casting key does on its next press: cast, put a lure on
-- the pole, or nothing while a lure is still being applied. Also the HUD tooltip line (with the
-- setting on or off). Reads the game through Context; the lure data is the bundled journal.
local _, ns = ...

local setmetatable, type, pairs, ipairs, select, sort, format =
    setmetatable, type, pairs, ipairs, select, table.sort, string.format
local L, Context, Options, LureChoice = ns.L, ns.Context, ns.Options, ns.LureChoice
local isSecret = issecretvalue or function()
    return false
end

local SmartLure = {}
SmartLure.__index = SmartLure
ns.SmartLure = SmartLure

SmartLure.APPLY_MAX = 10 -- seconds a lure click waits at most for the enchant to show up
SmartLure.RACE_ID = 3 -- UnitRace: raceID
SmartLure.CANCEL_EVENTS = { "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }

local function number(value)
    return not isSecret(value) and type(value) == "number" and value or nil
end

-- Lures of the journal in the bags that this race may use: { { id, bonus, need, count } }, by
-- item ID;
-- nil when the bags cannot be read.
local function owned(env, journal)
    local race = number(select(SmartLure.RACE_ID, Context.Call(env, "UnitRace", "player")))
    local raceBit = race and race >= 1 and 2 ^ (race - 1) or nil
    local list = {}
    for id, l in pairs(journal.lures or {}) do
        local count = number(Context.Call(env, "C_Item.GetItemCount", id, false))
        if not count then
            return nil
        end
        if count > 0 and ns.GearModel.RaceOk(l[3], raceBit) then
            list[#list + 1] = { id = id, bonus = l[1], need = l[2], count = count }
        end
    end
    sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

-- The LureChoice input from the game, without the applying flag (lures nil: bags unknown).
function SmartLure.Read(env, areas, journal)
    local rank, modifier = Context.Fishing(env)
    local enchant, seconds = Context.LureTime(env)
    local bonus = enchant and (journal.lureEnchants or {})[enchant] or nil
    local skill
    if rank then
        local total = rank + (modifier or 0)
        if not enchant then
            skill = total
        elseif bonus then
            skill = total - bonus
        end
    end
    local area = areas and Context.CurrentArea(env, areas)
    return {
        base = area and areas:Base(area) or nil,
        skill = skill,
        rank = rank,
        lures = owned(env, journal),
        active = enchant and { bonus = bonus, seconds = seconds } or nil,
    }
end

local function itemName(env, id)
    local name = Context.Call(env, "C_Item.GetItemInfo", id)
    if isSecret(name) or type(name) ~= "string" or name == "" then
        return format(L.LURE_ITEM, id)
    end
    return name
end

-- The Helpers page's "Right now" facts: the choice without the running lure (nil when the bags
-- cannot be read), the running lure, the water's name, and an item name reader.
function SmartLure.Now(env, areas, journal)
    local input = SmartLure.Read(env, areas, journal)
    local active, choice = input.active, nil
    if input.lures then
        input.active = nil
        choice = LureChoice.Choose(input)
    end
    local area = areas and Context.CurrentArea(env, areas)
    return {
        choice = choice,
        active = active,
        zone = area and Context.AreaName(env, area) or nil,
        name = function(id)
            return itemName(env, id)
        end,
    }
end

-- deps: { env, bus, castKey, settings, areas, journal, now }.
function SmartLure.Start(deps)
    local self = setmetatable({
        env = deps.env,
        settings = deps.settings,
        areas = deps.areas,
        journal = deps.journal,
        now = deps.now,
        applyingUntil = nil,
    }, SmartLure)
    deps.castKey:SetChooser(function()
        return self:Plan()
    end)
    deps.castKey:OnRelease(function(mode)
        if mode == "lure" then
            self.applyingUntil = self.now() + SmartLure.APPLY_MAX
        end
    end)
    local function cancel()
        self.applyingUntil = nil
    end
    for _, event in ipairs(SmartLure.CANCEL_EVENTS) do
        deps.bus:On(event, cancel, "player")
    end
    deps.bus:On("LOADING_SCREEN_ENABLED", cancel)
    return self
end

-- A lure click is still being applied: until a lure with more than LureChoice.KEEP seconds
-- shows up, the cast fails or is interrupted, or APPLY_MAX passed.
function SmartLure:Applying()
    if not self.applyingUntil then
        return false
    end
    local _, seconds = Context.LureTime(self.env)
    if self.now() >= self.applyingUntil or (seconds and seconds > LureChoice.KEEP) then
        self.applyingUntil = nil
        return false
    end
    return true
end

-- The casting key's next press: nil (cast), { action = "lure", item }, or { action = "wait" }.
function SmartLure:Plan()
    if Options.Get(self.settings, "autoLure") ~= true or not Context.HasPole(self.env) then
        self.choice = nil
        return nil
    end
    local input = SmartLure.Read(self.env, self.areas, self.journal)
    input.applying = self:Applying()
    local choice = LureChoice.Choose(input)
    self.choice = choice
    if choice.action == "lure" then
        return { action = "lure", item = choice.lure.id }
    elseif choice.action == "wait" then
        return { action = "wait" }
    end
    return nil
end
