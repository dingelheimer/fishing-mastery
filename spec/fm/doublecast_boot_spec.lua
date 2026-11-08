-- Double right-click casting (DoubleCast.lua) through every TOC file, with a fake mouse and the
-- fake clock: off by default; the right button bound to the cast button for one press only when
-- every condition holds; the override cleared by the release, combat, a loading screen, and the
-- timer; the conflict warning of other fishing addons.
local fmboot = require("spec.helpers.fmboot")

local STUBS = {
    "InCombatLockdown",
    "IsMounted",
    "IsSwimming",
    "IsFlying",
    "UnitOnTaxi",
    "UnitIsDeadOrGhost",
    "UnitExists",
    "GetMouseFoci",
    "WorldFrame",
    "IsMouselooking",
    "MouselookStop",
    "GetInventoryItemID",
    "SetOverrideBindingClick",
    "ClearOverrideBindings",
    "Settings",
    "BINDING_HEADER_FISHINGMASTERY",
    "BINDING_NAME_CLICK FishingMasteryCastButton:LeftButton",
}

local POLE, SWORD = 6256, 2488

describe("FishingMastery double right-click casting", function()
    local w, game, overrides, stopped

    before_each(function()
        w = fmboot.new()
        game = { pole = POLE, focus = "world" }
        overrides, stopped = {}, 0
        for _, name in ipairs({ "IsMounted", "IsSwimming", "IsFlying", "IsMouselooking" }) do
            local field = name
            _G[name] = function()
                return game[field] == true
            end
        end
        _G.InCombatLockdown = function()
            return game.combat == true
        end
        _G.UnitOnTaxi = function()
            return game.taxi == true
        end
        _G.UnitIsDeadOrGhost = function()
            return game.dead == true
        end
        _G.UnitExists = function(unit)
            return unit == "mouseover" and game.focus == "unit"
        end
        _G.WorldFrame = { name = "WorldFrame" }
        _G.GetMouseFoci = function()
            return { game.focus == "ui" and { name = "SomeFrame" } or _G.WorldFrame }
        end
        _G.MouselookStop = function()
            stopped = stopped + 1
        end
        _G.GetInventoryItemID = function(_, slot)
            return slot == 16 and game.pole or nil
        end
        _G.SetOverrideBindingClick = function(owner, priority, key, button)
            assert.is_false(game.combat == true, "override set in combat")
            overrides[owner] = { priority = priority, key = key, button = button }
        end
        _G.ClearOverrideBindings = function(owner)
            assert.is_false(game.combat == true, "override cleared in combat")
            overrides[owner] = nil
        end
        w.boot(nil, nil)
        _G.C_Item.GetItemInfoInstant = function(id)
            if id == POLE then
                return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, 20
            end
            return id, "Weapon", "Swords", "INVTYPE_WEAPON", 1, 2, 7
        end
        w.ns.Options.Set(w.ns.db.settings, "doubleClick", true)
    end)

    after_each(function()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
        w.cleanup()
    end)

    local function dc()
        return w.ns.doubleCast
    end

    local function override()
        return overrides[dc().owner]
    end

    -- A right-button press and release at t (0.1 s long).
    local function click(t)
        w.at(t, "GLOBAL_MOUSE_DOWN", "RightButton")
        w.at(t + 0.1, "GLOBAL_MOUSE_UP", "RightButton")
    end

    local function double(t)
        click(t)
        w.at(t + 0.25, "GLOBAL_MOUSE_DOWN", "RightButton")
        return dc().last
    end

    it("is off by default", function()
        w.ns.Options.Set(w.ns.db.settings, "doubleClick", false)
        assert.is_false(w.ns.Options.Default("doubleClick"))
        assert.are.equal("off", double(6000))
        assert.is_nil(override())
    end)

    it("binds the right button to the cast button for the second press only", function()
        assert.are.equal("armed", double(6000))
        assert.are.same(
            { priority = true, key = "BUTTON2", button = "FishingMasteryCastButton" },
            override()
        )
        -- The release casts through the 8.1 button; PostClick clears the override.
        local button = w.ns.castKey.button
        assert.are.equal("spell", button:GetAttribute("type"))
        button:PressKey(false)
        assert.is_nil(override())
        assert.are.equal("click", dc().disarmed)
        -- The cast is tracked like any other.
        w.catch(6001, 5)
        w.runTimers(6010)
        local totals = _G.FishingMasteryDB.chars[next(_G.FishingMasteryDB.chars)].totals
        assert.are.equal(1, totals.outcomes.catch)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("stops camera turning before it binds the button", function()
        game.IsMouselooking = true
        assert.are.equal("armed", double(6000))
        assert.are.equal(1, stopped)
    end)

    it("does nothing in any blocked state", function()
        local cases = {
            { "combat", "combat" },
            { "IsMounted", "mounted" },
            { "IsSwimming", "swimming" },
            { "IsFlying", "flying" },
            { "taxi", "taxi" },
            { "dead", "dead" },
        }
        local t = 6000
        for _, case in ipairs(cases) do
            game[case[1]] = true
            assert.are.equal(case[2], double(t))
            assert.is_nil(override())
            game[case[1]] = nil
            t = t + 10
        end
        game.pole = SWORD
        assert.are.equal("no-pole", double(t))
        game.pole = nil
        assert.are.equal("no-pole", double(t + 10))
        game.pole = POLE
        -- A line is out: the click is for the bobber.
        w.at(t + 20, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        assert.are.equal("line-out", double(t + 21))
        w.at(t + 30, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        assert.are.equal("armed", double(t + 40))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("does nothing without Fishing", function()
        _G.GetProfessions = function()
            return 5, nil, nil, nil, 6
        end
        w.fire("SKILL_LINES_CHANGED")
        assert.are.equal("no-fishing", double(6000))
        assert.is_nil(override())
    end)

    it("keeps right-clicks on units and windows, and camera drags, as they are", function()
        game.focus = "unit"
        click(6000)
        assert.are.equal("unit", double(6000.3))
        game.focus = "ui"
        assert.are.equal("ui", double(6010))
        game.focus = "world"
        -- A held first press turned the camera.
        w.at(6020, "GLOBAL_MOUSE_DOWN", "RightButton")
        w.at(6020.5, "GLOBAL_MOUSE_UP", "RightButton")
        w.at(6020.6, "GLOBAL_MOUSE_DOWN", "RightButton")
        assert.are.equal("first", dc().last)
        -- The left button is not ours.
        w.at(6030, "GLOBAL_MOUSE_DOWN", "LeftButton")
        w.at(6030.2, "GLOBAL_MOUSE_DOWN", "LeftButton")
        assert.is_nil(override())
    end)

    it("does not throw the line out again on a double-click on the bobber", function()
        w.at(6000, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(6005, "GLOBAL_MOUSE_DOWN", "RightButton") -- hooks the fish
        w.at(6005.05, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.at(6005.1, "GLOBAL_MOUSE_UP", "RightButton")
        w.at(6005.3, "GLOBAL_MOUSE_DOWN", "RightButton")
        assert.are.equal("bobber", dc().last)
        assert.is_nil(override())
    end)

    it("clears the override at combat start, a loading screen, and after the timer", function()
        assert.are.equal("armed", double(6000))
        w.fire("PLAYER_REGEN_DISABLED") -- before the lockdown
        assert.is_nil(override())
        assert.are.equal("combat", dc().disarmed)

        assert.are.equal("armed", double(6010))
        w.fire("LOADING_SCREEN_ENABLED")
        assert.is_nil(override())
        assert.are.equal("loading", dc().disarmed)

        assert.are.equal("armed", double(6020))
        w.runTimers(6021.5)
        assert.is_not_nil(override())
        w.runTimers(6022.3)
        assert.is_nil(override())
        assert.are.equal("timeout", dc().disarmed)

        -- An old timer does not clear a newer override.
        assert.are.equal("armed", double(6030))
        w.ns.castKey.button:PressKey(false)
        assert.are.equal("armed", double(6031))
        w.runTimers(6032.4) -- the first timer is due, the second not yet
        assert.is_not_nil(override())
        w.runTimers(6033.3)
        assert.is_nil(override())

        -- Combat started between press and release: cleared after the fight.
        assert.are.equal("armed", double(6040))
        game.combat = true
        w.fire("PLAYER_REGEN_DISABLED")
        assert.is_not_nil(override())
        game.combat = false
        w.fire("PLAYER_REGEN_ENABLED")
        assert.is_nil(override())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("forgets the first press at a loading screen", function()
        click(6000)
        w.fire("PLAYER_ENTERING_WORLD")
        w.at(6000.3, "GLOBAL_MOUSE_DOWN", "RightButton")
        assert.are.equal("first", dc().last)
    end)

    it("warns in the settings when another fishing addon is loaded", function()
        local DoubleCast = w.ns.DoubleCast
        local loaded = {}
        local env = {
            C_AddOns = {
                IsAddOnLoaded = function(name)
                    return loaded[name] == true
                end,
            },
        }
        assert.is_nil(DoubleCast.Conflict(env))
        assert.is_nil(DoubleCast.Conflict({}))
        loaded.ClassicFishingCompanion = true
        assert.are.equal("ClassicFishingCompanion", DoubleCast.Conflict(env))
        loaded.Luredon = true
        assert.are.equal("Luredon", DoubleCast.Conflict(env))

        local tips = {}
        _G.Settings = {
            RegisterVerticalLayoutCategory = function()
                return {}, {}
            end,
            RegisterAddOnSetting = function(_, _, key)
                return { key = key }
            end,
            CreateCheckbox = function(_, setting, tooltip)
                tips[setting.key] = tooltip
            end,
            RegisterAddOnCategory = function() end,
        }
        w.ns.SettingsPanel.Start({
            env = _G,
            settings = {},
            notes = { doubleClick = "Luredon is loaded and has its own casting" },
        })
        assert.truthy(tips.doubleClick:find("double right-click into the world", 1, true))
        assert.truthy(tips.doubleClick:find("\n\nLuredon is loaded", 1, true))
        assert.is_nil(tips.hudEnabled:find("Luredon", 1, true))
    end)
end)
