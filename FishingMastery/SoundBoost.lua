-- Louder splash (module 5, Story 8.4; setting "loudSplash", off by default): while a fishing pole
-- is in the main hand, sound effects play at full volume and music and ambience are off. The old
-- values of exactly these console variables are saved in the character settings
-- (FishingMasteryCharDB.sounds) and put back when the pole leaves the hand, the setting is turned
-- off, and at logout (SavedVariables are written after PLAYER_LOGOUT, so they stay restored). A
-- copy left from a session that ended without logout is restored at the next login.
local _, ns = ...

local setmetatable, type, pairs, ipairs, tostring = setmetatable, type, pairs, ipairs, tostring
local Context, Options = ns.Context, ns.Options
local isSecret = issecretvalue or function()
    return false
end

local SoundBoost = {}
SoundBoost.__index = SoundBoost
ns.SoundBoost = SoundBoost

-- The only console variables changed, with their value while the pole is in hand.
SoundBoost.CVARS = {
    Sound_EnableSFX = "1",
    Sound_SFXVolume = "1",
    Sound_MusicVolume = "0",
    Sound_AmbienceVolume = "0",
}
SoundBoost.EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }

-- deps: { env, bus, settings (db.settings), store (FishingMasteryCharDB) }.
function SoundBoost.Start(deps)
    local self = setmetatable({
        env = deps.env,
        settings = deps.settings,
        store = deps.store,
    }, SoundBoost)
    local function update()
        self:Update()
    end
    for _, event in ipairs(SoundBoost.EVENTS) do
        deps.bus:On(event, update)
    end
    deps.bus:On("PLAYER_LOGOUT", function()
        self:Restore()
    end)
    self:Update()
    return self
end

function SoundBoost:Active()
    return Options.Get(self.settings, "loudSplash") == true and Context.HasPole(self.env)
end

-- Saves the current values and sets the loud ones (once; a saved copy is kept as it is).
function SoundBoost:Apply()
    if type(self.store.sounds) == "table" then
        return
    end
    local saved = {}
    for cvar, value in pairs(SoundBoost.CVARS) do
        local current = Context.Call(self.env, "GetCVar", cvar)
        if not isSecret(current) and current ~= nil then
            saved[cvar] = tostring(current)
            Context.Call(self.env, "SetCVar", cvar, value)
        end
    end
    self.store.sounds = saved
end

-- Puts the saved values back and forgets them.
function SoundBoost:Restore()
    local saved = self.store.sounds
    if type(saved) ~= "table" then
        return
    end
    for cvar, value in pairs(saved) do
        if SoundBoost.CVARS[cvar] and type(value) == "string" then
            Context.Call(self.env, "SetCVar", cvar, value)
        end
    end
    self.store.sounds = nil
end

function SoundBoost:Update()
    if self:Active() then
        self:Apply()
    else
        self:Restore()
    end
end
