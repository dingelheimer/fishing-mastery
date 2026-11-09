-- The key-binding button of the Helpers page (Story 9.6): shows the key bound to "Cast Fishing"
-- (Bindings.xml), or "Not bound". A click waits for the next key (with Shift, Ctrl, Alt) and binds
-- it with SetBinding and SaveBindings; Escape cancels; a right-click clears the binding. Binding
-- changes are protected in combat, so the button is disabled there. The binding changes only on
-- the player's click. Unnamed, insecure frame (the dropdown look without the arrow).
local _, ns = ...

local type, ipairs = type, ipairs
local L, Context = ns.L, ns.Context

local KeyButton = {}
ns.KeyButton = KeyButton

KeyButton.COMMAND = "CLICK " .. ns.CastKey.BUTTON .. ":LeftButton"
-- Keys that only modify another key, and the prefixes the client writes for held modifiers.
KeyButton.MODIFIERS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
}
KeyButton.PREFIXES = { { "IsAltKeyDown", "ALT-" }, { "IsControlKeyDown", "CTRL-" } }

local function inCombat(env)
    return Context.Call(env, "InCombatLockdown") == true
end

-- The key bound to the casting key, or nil.
function KeyButton.Current(env)
    local key = Context.Call(env, "GetBindingKey", KeyButton.COMMAND)
    return type(key) == "string" and key ~= "" and key or nil
end

-- The binding text of a pressed key with the held modifiers ("SHIFT-F", "ALT-CTRL-3").
function KeyButton.Combo(env, key)
    local text = key
    if Context.Call(env, "IsShiftKeyDown") then
        text = "SHIFT-" .. text
    end
    for _, prefix in ipairs(KeyButton.PREFIXES) do
        if Context.Call(env, prefix[1]) then
            text = prefix[2] .. text
        end
    end
    return text
end

local function save(env)
    local set = Context.Call(env, "GetCurrentBindingSet")
    Context.Call(env, "SaveBindings", set)
end

-- Removes every key bound to the casting key.
local function clear(env)
    for _, key in ipairs({ Context.Call(env, "GetBindingKey", KeyButton.COMMAND) }) do
        if type(key) == "string" then
            Context.Call(env, "SetBinding", key)
        end
    end
end

local function stop(button)
    button.waiting = false
    button:EnableKeyboard(false)
    button:Refresh()
end

local function onKey(button, key)
    local env = button.env
    if KeyButton.MODIFIERS[key] then
        return
    end
    if key ~= "ESCAPE" and not inCombat(env) then
        clear(env)
        Context.Call(env, "SetBinding", KeyButton.Combo(env, key), KeyButton.COMMAND)
        save(env)
    end
    stop(button)
end

local function onClick(button, mouse)
    local env = button.env
    if inCombat(env) then
        button:Refresh()
        return
    end
    if mouse == "RightButton" then
        clear(env)
        save(env)
        stop(button)
        return
    end
    button.waiting = true
    button:EnableKeyboard(true)
    button:SetText(L.HKEY_PRESS)
end

-- Shows the bound key, "Press a key" while waiting, or "Not in combat" (disabled) in combat.
local function refresh(button)
    local env = button.env
    local combat = inCombat(env)
    if combat and button.waiting then
        button.waiting = false
        button:EnableKeyboard(false)
    end
    button:SetEnabled(not combat)
    if combat then
        button:SetText(L.HKEY_COMBAT)
    elseif button.waiting then
        button:SetText(L.HKEY_PRESS)
    else
        button:SetText(KeyButton.Current(env) or L.HKEY_NONE)
    end
end

function KeyButton.Create(env, parent, width)
    local button = ns.Controls.Button(env, parent, width, function() end)
    button.env, button.Refresh = env, refresh
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", ns.Guard.Wrap("key:click", onClick))
    button:SetScript("OnKeyDown", ns.Guard.Wrap("key:press", onKey))
    button:SetScript("OnEnter", function(owner)
        ns.Tip.Open(env, owner, function(tip)
            tip:Title(L.HKEY)
            tip:Gap()
            tip:Hint(L.HKEY_HINT_SET)
            tip:Hint(L.HKEY_HINT_CANCEL)
            tip:Hint(L.HKEY_HINT_CLEAR)
        end)
    end)
    button:SetScript("OnLeave", function(owner)
        ns.Tip.Close(env, owner)
    end)
    button:Refresh()
    return button
end
