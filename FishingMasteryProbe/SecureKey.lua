-- Step S14a (Q28): a secure action button that casts Fishing, bound to a temporary test key.
-- The player enables the key with a click and presses it; the probe never casts by itself.
-- The binding is removed after the result, when the step ends, and on logout.
local _, ns = ...

local setmetatable, type, pcall, tostring = setmetatable, type, pcall, tostring
local isSecret = issecretvalue or function()
    return false
end

local Calls = ns.Calls

local SecureKey = {}
SecureKey.__index = SecureKey
ns.SecureKey = SecureKey

SecureKey.KEY = "CTRL-SHIFT-F"
SecureKey.TEMPLATE = "SecureActionButtonTemplate"
-- SetOverrideBindingClick takes a frame name, so this is the probe's only named frame.
SecureKey.BUTTON_NAME = "FishingMasteryProbeTestButton"
SecureKey.WINDOW = 2 -- seconds between the key press and the channel start
SecureKey.SLACK = 0.1

local function plain(value)
    return not isSecret(value) and value or nil
end

-- deps: { env, bus, log(kind, data, q), now(), after(seconds, fn), inCombat(),
-- fishingSpellID() -> number or nil, onChange() }.
function SecureKey.New(deps)
    local self = setmetatable({
        env = deps.env,
        log = deps.log,
        now = deps.now,
        after = deps.after,
        inCombat = deps.inCombat,
        fishingSpellID = deps.fishingSpellID or function() end,
        onChange = deps.onChange or function() end,
        state = "off", -- off, active, waiting, done, combat, failed
        enabled = false,
    }, SecureKey)
    deps.bus:On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, _, spellID)
        self:OnChannel(spellID)
    end, "player")
    deps.bus:On("PLAYER_REGEN_ENABLED", function()
        if self.pendingClear then
            self:Disable(self.pendingClear)
        end
    end)
    return self
end

-- The spell for the button: the spell of a recorded catch first, then the fishing profession
-- name from GetProfessions (4th index) and GetProfessionInfo.
function SecureKey.ResolveSpell(env, spellID)
    if type(spellID) == "number" then
        local info = Calls.Call(env, "C_Spell.GetSpellInfo", spellID)
        local name = info.ok and type(info.values[1]) == "table" and plain(info.values[1].name)
        if type(name) == "string" then
            return { value = name, name = name, spellID = spellID, source = "catch_name" }
        end
        return { value = spellID, spellID = spellID, source = "catch_id" }
    end
    local _, ok, _, _, _, fishing = Calls.Invoke(env, "GetProfessions")
    fishing = ok and plain(fishing)
    if type(fishing) ~= "number" then
        return nil
    end
    local _, infoOk, name = Calls.Invoke(env, "GetProfessionInfo", fishing)
    name = infoOk and plain(name)
    if type(name) == "string" then
        return { value = name, name = name, source = "profession" }
    end
    return nil
end

local function check(self, data)
    data.test = "S14a"
    data.key = SecureKey.KEY
    self.log("probe_check", data, "Q28")
end

local function createButton(self)
    if self.button then
        return true
    end
    local env = self.env
    local ok, button =
        pcall(env.CreateFrame, "Button", SecureKey.BUTTON_NAME, env.UIParent, SecureKey.TEMPLATE)
    if not ok or not button then
        return false, isSecret(button) and "<secret>" or tostring(button)
    end
    button:SetAttribute("type", "spell")
    -- Modern clients act on either the down or the up click (ActionButtonUseKeyDown).
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetScript(
        "PostClick",
        ns.Guard.Wrap("securekey:click", function(_, mouseButton, down)
            self:OnPress(mouseButton, down)
        end)
    )
    self.button = button
    return true
end

-- Enables the test key. Returns false when skipped (combat) or when the setup failed.
function SecureKey:Enable()
    if self.inCombat() then
        self.state = "combat"
        self.log("probe_skip", { test = "S14a", reason = "combat" }, "Q28")
        return false
    end
    if self.enabled then
        return true
    end
    local created, err = createButton(self)
    if not created then
        self.state = "failed"
        check(self, { template = false, error = err })
        return false
    end
    local spell = SecureKey.ResolveSpell(self.env, self.fishingSpellID())
    if not spell then
        self.state = "failed"
        check(self, { template = true, reason = "no_spell" })
        return false
    end
    self.button:SetAttribute("spell", spell.value)
    self.spell = spell
    local exists, ok, result = Calls.Invoke(
        self.env,
        "SetOverrideBindingClick",
        self.button,
        true,
        SecureKey.KEY,
        SecureKey.BUTTON_NAME,
        "LeftButton"
    )
    local keyDown = Calls.Call(self.env, "GetCVar", "ActionButtonUseKeyDown")
    self.log("probe_key", {
        action = "enable",
        template = true,
        bindExists = exists,
        bound = exists and ok or false,
        bindResult = ns.Serializer.Sanitize(result),
        spellSource = spell.source,
        spellID = spell.spellID,
        keyDown = keyDown,
    }, "Q28")
    if not (exists and ok) then
        self.state = "failed"
        check(self, { template = true, bound = false, spellSource = spell.source })
        return false
    end
    self.enabled, self.presses, self.pressedAt = true, 0, nil
    self.state = "active"
    return true
end

-- Removes the binding; deferred to the end of combat when bindings are locked.
function SecureKey:Disable(reason)
    if not self.enabled then
        return false
    end
    if self.inCombat() then
        if not self.pendingClear then
            self.log("probe_key", { action = "clear_deferred", reason = reason }, "Q28")
        end
        self.pendingClear = reason
        return false
    end
    local exists, ok = Calls.Invoke(self.env, "ClearOverrideBindings", self.button)
    self.enabled, self.pendingClear = false, nil
    if self.state == "active" or self.state == "waiting" then
        self.state = "off"
    end
    self.log("probe_key", { action = "disable", reason = reason, cleared = exists and ok }, "Q28")
    self.onChange()
    return true
end

local function finish(self, channel)
    if self.state ~= "waiting" then
        return
    end
    self.state = "done"
    self.result = channel ~= nil
    self:Disable("checked")
    local spell = self.spell or {}
    check(self, {
        template = true,
        bound = true,
        spellSource = spell.source,
        presses = self.presses,
        channelStarted = channel ~= nil,
        delay = channel and channel.delay,
        spellID = channel and channel.spellID,
        matchesSpell = channel and channel.matches,
    })
    self.onChange()
end

-- PostClick of the secure button: the player pressed the key (or clicked the button).
function SecureKey:OnPress(mouseButton, down)
    if not self.enabled then
        return
    end
    self.presses = self.presses + 1
    self.log(
        "probe_key",
        { action = "press", mouseButton = plain(mouseButton), down = down },
        "Q28"
    )
    if self.state ~= "active" then
        return
    end
    self.state, self.pressedAt = "waiting", self.now()
    self.after(SecureKey.WINDOW + SecureKey.SLACK, function()
        finish(self, nil)
    end)
    self.onChange()
end

function SecureKey:OnChannel(spellID)
    if self.state ~= "waiting" then
        return
    end
    local delay = self.now() - self.pressedAt
    if delay > SecureKey.WINDOW then
        return
    end
    spellID = plain(spellID)
    local spell, matches = self.spell or {}, nil
    if spell.spellID then
        matches = spellID == spell.spellID
    elseif spell.name and spellID then
        local info = Calls.Call(self.env, "C_Spell.GetSpellInfo", spellID)
        local data = info.ok and info.values[1]
        matches = type(data) == "table" and plain(data.name) == spell.name
    end
    finish(self, { delay = delay, spellID = spellID, matches = matches })
end
