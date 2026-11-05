-- Step S14 (Q27, Q28): the opt-in helper tests. Creates the secure test key (S14a) and the addon
-- self-whisper (S14b), logs the helper environment once, and removes the test key when S14 ends
-- or the player logs out.
local _, ns = ...

local setmetatable = setmetatable

local Calls = ns.Calls

local Helpers = {}
Helpers.__index = Helpers
ns.Helpers = Helpers

Helpers.STEP = "S14"
-- Logged as function / table / nil; loadstring_untainted is the secure snippet support check.
Helpers.APIS = {
    "loadstring_untainted",
    "SetOverrideBindingClick",
    "ClearOverrideBindings",
    "InCombatLockdown",
    "C_ChatInfo.RegisterAddonMessagePrefix",
    "C_ChatInfo.IsAddonMessagePrefixRegistered",
    "C_ChatInfo.SendAddonMessage",
}

-- InCombatLockdown when it exists; without it the probe assumes no combat lock.
function Helpers.InCombat(env)
    local _, ok, locked = Calls.Invoke(env, "InCombatLockdown")
    return ok and locked == true
end

-- Q28 / secure snippets: what the client offers for helpers, without calling anything protected.
function Helpers.Environment(env)
    return {
        apis = ns.Scan.Existence(env, Helpers.APIS),
        templateInfo = Calls.Call(env, "C_XMLUtil.GetTemplateInfo", ns.SecureKey.TEMPLATE),
        inCombat = Helpers.InCombat(env),
        key = ns.SecureKey.KEY,
    }
end

-- deps: { env, bus, log(kind, data, q), now(), after(seconds, fn), fishingSpellID(), onChange() }.
function Helpers.New(deps)
    local env = deps.env
    local function inCombat()
        return Helpers.InCombat(env)
    end
    local shared = {
        env = env,
        bus = deps.bus,
        log = deps.log,
        now = deps.now,
        after = deps.after,
        inCombat = inCombat,
        fishingSpellID = deps.fishingSpellID,
        onChange = deps.onChange,
    }
    local self = setmetatable({
        key = ns.SecureKey.New(shared),
        message = ns.AddonMessage.New(shared),
    }, Helpers)
    deps.log("helpers_env", Helpers.Environment(env), "Q28")
    return self
end

function Helpers:EnableKey()
    return self.key:Enable()
end

function Helpers:SendWhisper()
    return self.message:Send()
end

-- Called on every progress change: the test key only lives while S14 is started.
function Helpers:Sync(progress)
    if progress:Current().id ~= Helpers.STEP or not progress:Started() then
        self.key:Disable("step_end")
    end
end

function Helpers:Shutdown()
    self.key:Disable("logout")
end

-- States for the window: { key, keyName, keyResult, whisper, whisperResult }.
function Helpers:Status()
    return {
        key = self.key.state,
        keyName = ns.SecureKey.KEY,
        keyResult = self.key.result,
        whisper = self.message.state,
        whisperResult = self.message.result,
    }
end
