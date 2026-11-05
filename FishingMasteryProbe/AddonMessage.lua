-- Step S14b (Q27): registers the prefix FMProbe and whispers one fixed test message to the
-- player's own character. Only messages with this prefix are looked at; nothing of other addons,
-- channels, or players is logged. The own name stays in memory and is never logged.
local _, ns = ...

local setmetatable, type, pairs = setmetatable, type, pairs
local isSecret = issecretvalue or function()
    return false
end

local Calls, Redact = ns.Calls, ns.Redact

local AddonMessage = {}
AddonMessage.__index = AddonMessage
ns.AddonMessage = AddonMessage

AddonMessage.PREFIX = "FMProbe"
AddonMessage.TEXT = "FMProbe self-test 1"
AddonMessage.CHANNEL = "WHISPER"
AddonMessage.TIMEOUT = 5 -- seconds to wait for CHAT_MSG_ADDON
AddonMessage.SLACK = 0.1

local function plain(value)
    return not isSecret(value) and value or nil
end

-- The own character as whisper target: "Name" or "Name-Realm" when UnitName has a realm part.
function AddonMessage.OwnTarget(env)
    local _, ok, name, realm = Calls.Invoke(env, "UnitName", "player")
    name, realm = ok and plain(name), ok and plain(realm)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm, name
    end
    return name, name
end

-- deps: { env, bus, log(kind, data, q), now(), after(seconds, fn), inCombat(), onChange() }.
function AddonMessage.New(deps)
    local self = setmetatable({
        env = deps.env,
        log = deps.log,
        now = deps.now,
        after = deps.after,
        inCombat = deps.inCombat,
        onChange = deps.onChange or function() end,
        state = "off", -- off, waiting, done, combat, failed
        round = 0,
    }, AddonMessage)
    self.listening = deps.bus:On("CHAT_MSG_ADDON", function(_, ...)
        self:OnMessage(...)
    end)
    return self
end

-- Send results can name the target in an error text; the own name is replaced.
local function reduce(value, target, name)
    value = Redact.OwnName(Redact.OwnName(value, target), name)
    return ns.Serializer.Sanitize(value)
end

local function check(self, data)
    data.test = "S14b"
    data.prefix = AddonMessage.PREFIX
    data.listening = self.listening
    self.log("probe_check", data, "Q27")
end

-- Sends the test message. Returns false when skipped (combat) or when sending failed.
function AddonMessage:Send()
    if self.inCombat() then
        self.state = "combat"
        self.log("probe_skip", { test = "S14b", reason = "combat" }, "Q27")
        return false
    end
    if self.state == "waiting" then
        return true
    end
    local env, prefix = self.env, AddonMessage.PREFIX
    local register = Calls.Call(env, "C_ChatInfo.RegisterAddonMessagePrefix", prefix)
    local registered = Calls.Call(env, "C_ChatInfo.IsAddonMessagePrefixRegistered", prefix)
    local target, name = AddonMessage.OwnTarget(env)
    if not target then
        self.state = "failed"
        check(self, { register = register, registered = registered, reason = "no_name" })
        return false
    end
    local exists, ok, result = Calls.Invoke(
        env,
        "C_ChatInfo.SendAddonMessage",
        prefix,
        AddonMessage.TEXT,
        AddonMessage.CHANNEL,
        target
    )
    local send = {
        exists = exists,
        ok = ok,
        result = reduce(result, target, name),
        realmPart = target ~= name,
    }
    if not (exists and ok) then
        self.state = "failed"
        check(self, { register = register, registered = registered, send = send, received = false })
        return false
    end
    self.round = self.round + 1
    local round = self.round
    self.pending = {
        t = self.now(),
        register = register,
        registered = registered,
        send = send,
        target = target,
        name = name,
    }
    self.state = "waiting"
    self.log("probe_message", { action = "sent", send = send }, "Q27")
    self.after(AddonMessage.TIMEOUT + AddonMessage.SLACK, function()
        if self.round == round then
            self:Finish(nil)
        end
    end)
    self.onChange()
    return true
end

function AddonMessage:Finish(receipt)
    local pending = self.pending
    if not pending then
        return
    end
    self.pending = nil
    self.state = "done"
    self.result = receipt ~= nil
    local data = {
        register = pending.register,
        registered = pending.registered,
        send = pending.send,
        received = receipt ~= nil,
    }
    if receipt then
        for key, value in pairs(receipt) do
            data[key] = value
        end
    end
    check(self, data)
    self.onChange()
end

-- CHAT_MSG_ADDON payload: prefix, text, channel, sender, target, ... Other prefixes are ignored.
function AddonMessage:OnMessage(prefix, text, channel, sender)
    if isSecret(prefix) or prefix ~= AddonMessage.PREFIX then
        return
    end
    local pending = self.pending
    local receipt = {
        sameText = not isSecret(text) and text == AddonMessage.TEXT,
        channel = type(plain(channel)) == "string" and channel or nil,
        senderSecret = isSecret(sender) or nil,
    }
    if not pending then
        self.log("probe_message", { action = "late", sameText = receipt.sameText }, "Q27")
        return
    end
    sender = plain(sender)
    receipt.fromSelf = sender == pending.target or sender == pending.name
    receipt.senderHasRealm = type(sender) == "string" and sender:find("-", 1, true) ~= nil
    receipt.delay = self.now() - pending.t
    self:Finish(receipt)
end
