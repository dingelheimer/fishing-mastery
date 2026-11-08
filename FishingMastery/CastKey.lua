-- The casting key (module 5, Story 8.1): one named secure button, FishingMasteryCastButton, that
-- casts Fishing when the player presses the key bound to "Cast Fishing" (Bindings.xml; the game's
-- Key Bindings, AddOns, Fishing Mastery; no key by default). It acts once, on key release. Its
-- attributes change only out of combat; a change during combat waits for the end of the fight. The
-- button never clicks itself, and casts through it are tracked like any other cast.
local _, ns = ...

local setmetatable, type, pcall, ipairs = setmetatable, type, pcall, ipairs
local L, Context = ns.L, ns.Context

local CastKey = {}
CastKey.__index = CastKey
ns.CastKey = CastKey

CastKey.BUTTON = "FishingMasteryCastButton" -- a binding of the form CLICK <name> needs a name
CastKey.TEMPLATE = "SecureActionButtonTemplate"
CastKey.SPELL = 7620 -- Fishing; cast by name, the client picks the highest known rank
CastKey.RANKS = { 18248, 7732, 7731, 7620 } -- Artisan, Expert, Journeyman, Apprentice
CastKey.EVENTS = { "SPELLS_CHANGED", "SKILL_LINES_CHANGED" }

-- Texts of the game's Key Bindings window (globals the client reads; listed in .luacheckrc).
BINDING_HEADER_FISHINGMASTERY = L.PREFIX
_G["BINDING_NAME_CLICK " .. CastKey.BUTTON .. ":LeftButton"] = L.BINDING_CAST

-- The button's spell: the readable name when there is one, else the highest known rank's ID, nil
-- without Fishing. learned: Fishing is learned; name: localized spell name or nil;
-- known(spellID): IsPlayerSpell.
function CastKey.Spell(learned, name, known)
    if not learned then
        return nil
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    for _, id in ipairs(CastKey.RANKS) do
        if known(id) == true then
            return id
        end
    end
    return CastKey.SPELL
end

local function inCombat(self)
    return Context.Call(self.env, "InCombatLockdown") == true
end

-- Creates the secure button (out of combat only). Returns false without the secure template.
local function build(self)
    local env = self.env
    local ok, button =
        pcall(env.CreateFrame, "Button", CastKey.BUTTON, env.UIParent, CastKey.TEMPLATE)
    if not ok or not button then
        return false
    end
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("useOnKeyDown", false) -- act on release only, once per press
    button:SetScript("PostClick", function(_, _, down)
        if not down then
            self:AfterPress()
        end
    end)
    self.button = button
    return true
end

-- deps: { env, bus, print }. Builds the button at login, or after the fight after a /reload in
-- combat.
function CastKey.Start(deps)
    local self = setmetatable({
        env = deps.env,
        print = deps.print,
        attributes = {},
        released = {},
        pending = false,
        warned = false,
        built = false,
    }, CastKey)
    local function update()
        self:Update()
    end
    for _, event in ipairs(CastKey.EVENTS) do
        deps.bus:On(event, update)
    end
    deps.bus:On("PLAYER_REGEN_ENABLED", function()
        if self.pending then
            self:Update()
        end
    end)
    self:Update()
    return self
end

-- The spell for this character now.
function CastKey:CurrentSpell()
    local env = self.env
    local rank = Context.Fishing(env)
    local info = Context.Call(env, "C_Spell.GetSpellInfo", CastKey.SPELL)
    local name = type(info) == "table" and info.name or nil
    if type(name) ~= "string" then
        name = Context.FishingName(env)
    end
    return CastKey.Spell(rank ~= nil, name, function(id)
        return Context.Call(env, "IsPlayerSpell", id)
    end)
end

local function set(self, key, value)
    if self.attributes[key] ~= value then
        self.attributes[key] = value
        self.button:SetAttribute(key, value)
    end
end

-- Builds the button and writes its attributes, or waits for the end of combat.
function CastKey:Update()
    if inCombat(self) then
        self.pending = true
        return
    end
    self.pending = false
    if not self.built then
        self.built = true
        if not build(self) then
            return
        end
    end
    if not self.button then
        return
    end
    local spell = self:CurrentSpell()
    self.spell = spell
    set(self, "type", spell and "spell" or nil)
    set(self, "spell", spell)
end

-- fn() runs after every release of the button (the double-click override clears itself).
function CastKey:OnRelease(fn)
    self.released[#self.released + 1] = fn
end

-- After a key press: says once per login that this character has no Fishing.
function CastKey:AfterPress()
    for _, fn in ipairs(self.released) do
        fn()
    end
    if self.spell == nil and not self.warned then
        self.warned = true
        self.print(L.CASTKEY_NO_FISHING)
    end
end
