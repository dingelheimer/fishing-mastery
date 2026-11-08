-- Double right-click casting (module 5, Story 8.2; setting "doubleClick", off by default). On the
-- second right-button press of a double-click into the world (DoubleClick.lua), and only when
-- nothing blocks a cast, the right button is bound to the casting key's secure button for that
-- one press (SetOverrideBindingClick); the press's release casts Fishing. The override never
-- outlives the click: the button's release, PLAYER_REGEN_DISABLED (before the lockdown), a loading
-- screen, and a timer clear it. Nothing is clicked from code.
local _, ns = ...

local setmetatable, type, ipairs = setmetatable, type, ipairs
local Context, Options, DoubleClick, CastKey = ns.Context, ns.Options, ns.DoubleClick, ns.CastKey
local isSecret = issecretvalue or function()
    return false
end

local DoubleCast = {}
DoubleCast.__index = DoubleCast
ns.DoubleCast = DoubleCast

DoubleCast.KEY = "BUTTON2"
-- Fishing addons with their own double right-click casting (folder names).
DoubleCast.CONFLICTS = { "Luredon", "ClassicFishingCompanion" }
DoubleCast.WORLD_EVENTS =
    { "LOADING_SCREEN_ENABLED", "PLAYER_LEAVING_WORLD", "PLAYER_ENTERING_WORLD" }

local function flag(env, path, ...)
    local value = Context.Call(env, path, ...)
    return not isSecret(value) and value == true
end

-- The first loaded fishing addon with its own double-click casting, or nil.
function DoubleCast.Conflict(env)
    for _, name in ipairs(DoubleCast.CONFLICTS) do
        if flag(env, "C_AddOns.IsAddOnLoaded", name) then
            return name
        end
    end
    return nil
end

-- deps: { env, bus, castKey, settings, now, after(seconds, fn), isFishingSpell(id) }.
function DoubleCast.Start(deps)
    local env = deps.env
    local self = setmetatable({
        env = env,
        castKey = deps.castKey,
        settings = deps.settings,
        now = deps.now,
        after = deps.after,
        clicks = DoubleClick.New(),
        owner = env.CreateFrame("Frame"),
        armed = false,
        token = 0,
        lineOut = false,
    }, DoubleCast)
    local bus = deps.bus
    bus:On("GLOBAL_MOUSE_DOWN", function(_, button)
        if button == "RightButton" then
            self:Press()
        end
    end)
    bus:On("GLOBAL_MOUSE_UP", function(_, button)
        if button == "RightButton" then
            self.clicks:Up(self.now())
        end
    end)
    bus:On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, _, spellID)
        if deps.isFishingSpell(spellID) then
            self.lineOut = true
        end
    end, "player")
    bus:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, _, spellID)
        if deps.isFishingSpell(spellID) then
            self.lineOut = false
            self.clicks:LineIn(self.now())
        end
    end, "player")
    bus:On("PLAYER_REGEN_DISABLED", function()
        self:Disarm("combat")
    end)
    bus:On("PLAYER_REGEN_ENABLED", function()
        self:Disarm("after-combat") -- in case the fight started between press and release
    end)
    for _, event in ipairs(DoubleCast.WORLD_EVENTS) do
        bus:On(event, function()
            self:Disarm("loading")
            self.clicks:Forget()
            self.lineOut = false
        end)
    end
    deps.castKey:OnRelease(function()
        self:Disarm("click")
    end)
    return self
end

-- What is under the mouse: "ui" (a frame), "unit", or "world".
function DoubleCast:Place()
    local env = self.env
    local focus
    if type(env.GetMouseFoci) == "function" then
        local foci = Context.Call(env, "GetMouseFoci")
        focus = type(foci) == "table" and foci[1] or nil
    else
        focus = Context.Call(env, "GetMouseFocus")
    end
    if focus ~= nil and focus ~= env.WorldFrame then
        return "ui"
    end
    if flag(env, "UnitExists", "mouseover") then
        return "unit"
    end
    return "world"
end

-- The state DoubleClick.Blocked reads.
function DoubleCast:State()
    local env = self.env
    local key = self.castKey
    return {
        off = Options.Get(self.settings, "doubleClick") ~= true,
        combat = flag(env, "InCombatLockdown"),
        mounted = flag(env, "IsMounted"),
        swimming = flag(env, "IsSwimming"),
        flying = flag(env, "IsFlying"),
        taxi = flag(env, "UnitOnTaxi", "player"),
        dead = flag(env, "UnitIsDeadOrGhost", "player"),
        noButton = key.button == nil or key.pending,
        noFishing = key.spell == nil,
        lureWait = key.mode == "wait",
        noPole = not Context.HasPole(env),
        lineOut = self.lineOut,
    }
end

-- A right-button press: binds the right button to the cast button for this press when it is
-- the second click of a double-click and nothing blocks a cast. Returns what it decided.
function DoubleCast:Press()
    local double, reason = self.clicks:Down(self.now(), self:Place())
    if not double then
        self.last = reason
        return reason
    end
    self.castKey:Update() -- the smart lure may be waiting for a lure to land
    local blocked = DoubleClick.Blocked(self:State())
    if blocked then
        self.last = blocked
        return blocked
    end
    self:Arm()
    self.last = "armed"
    return "armed"
end

function DoubleCast:Arm()
    local env = self.env
    if flag(env, "IsMouselooking") then
        Context.Call(env, "MouselookStop") -- the first press started camera turning
    end
    Context.Call(env, "SetOverrideBindingClick", self.owner, true, DoubleCast.KEY, CastKey.BUTTON)
    self.armed = true
    self.armedCount = (self.armedCount or 0) + 1
    self.token = self.token + 1
    local token = self.token
    if self.after then
        self.after(DoubleClick.ARM_TIMEOUT, function()
            if self.token == token then
                self:Disarm("timeout")
            end
        end)
    end
end

-- Removes the right-button override (out of combat only; PLAYER_REGEN_DISABLED comes first).
function DoubleCast:Disarm(why)
    if not self.armed or flag(self.env, "InCombatLockdown") then
        return
    end
    Context.Call(self.env, "ClearOverrideBindings", self.owner)
    self.armed = false
    self.token = self.token + 1
    self.disarmed = why
end
