-- Louder splash (SoundBoost.lua) and the hidden interface (HideUI.lua) through every TOC file:
-- save and restore of each sound setting (pole out of the hand, setting off, logout, the next
-- login after a /reload), every reason that brings the interface back, the player's own Alt+Z,
-- the catch line on WorldFrame, and no change with the settings off.
local fmboot = require("spec.helpers.fmboot")

local STUBS = {
    "InCombatLockdown",
    "UnitIsDeadOrGhost",
    "GetInventoryItemID",
    "GetCVar",
    "SetCVar",
    "SetUIVisibility",
    "WorldFrame",
    "ITEM_QUALITY_COLORS",
    "BINDING_HEADER_FISHINGMASTERY",
    "BINDING_NAME_CLICK FishingMasteryCastButton:LeftButton",
}

local POLE = 6256
local MINE = {
    Sound_EnableSFX = "0",
    Sound_SFXVolume = "0.4",
    Sound_MusicVolume = "0.6",
    Sound_AmbienceVolume = "0.3",
    Sound_MasterVolume = "0.8",
}
local LOUD = {
    Sound_EnableSFX = "1",
    Sound_SFXVolume = "1",
    Sound_MusicVolume = "0",
    Sound_AmbienceVolume = "0",
    Sound_MasterVolume = "0.8",
}

describe("FishingMastery sound boost and hidden interface", function()
    local w, game, cvars, writes, visibility

    local function stub()
        _G.InCombatLockdown = function()
            return game.combat == true
        end
        _G.UnitIsDeadOrGhost = function()
            return game.dead == true
        end
        _G.GetInventoryItemID = function(_, slot)
            return slot == 16 and game.pole or nil
        end
        _G.GetCVar = function(name)
            return cvars[name]
        end
        _G.SetCVar = function(name, value)
            writes[#writes + 1] = name
            cvars[name] = value
        end
        _G.SetUIVisibility = function(show)
            visibility[#visibility + 1] = show
            w.env.UIParent.shown = show
        end
        _G.WorldFrame = { name = "WorldFrame" }
        _G.ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
    end

    -- A login or /reload with the saved variables kept (the char DB holds the sound copy).
    local function login()
        local saved, charSaved = _G.FishingMasteryDB, _G.FishingMasteryCharDB
        w.boot(saved, charSaved)
        w.fire("PLAYER_ENTERING_WORLD")
    end

    before_each(function()
        w = fmboot.new()
        w.game.itemInfoInstant = function(id)
            return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, id == POLE and 20 or 7
        end
        game = { pole = POLE }
        cvars, writes, visibility = {}, {}, {}
        for k, v in pairs(MINE) do
            cvars[k] = v
        end
        stub()
        login()
    end)

    after_each(function()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
        w.cleanup()
    end)

    local function set(key, value)
        w.ns.Options.Set(w.ns.db.settings, key, value)
        if key == "loudSplash" then
            w.ns.soundBoost:Update()
        elseif key == "hideUI" then
            w.ns.hideUI:Update()
        end
    end

    local function equip(id)
        game.pole = id
        w.fire("PLAYER_EQUIPMENT_CHANGED", 16, id == nil)
    end

    describe("louder splash", function()
        it("changes nothing with the setting off", function()
            assert.is_false(w.ns.Options.Default("loudSplash"))
            equip(2488)
            equip(POLE)
            assert.are.same({}, writes)
            assert.are.same(MINE, cvars)
        end)

        it("sets the four sound settings with a pole in hand and restores them after", function()
            set("loudSplash", true)
            assert.are.same(LOUD, cvars)
            assert.are.same({
                Sound_EnableSFX = "0",
                Sound_SFXVolume = "0.4",
                Sound_MusicVolume = "0.6",
                Sound_AmbienceVolume = "0.3",
            }, _G.FishingMasteryCharDB.sounds)
            equip(POLE) -- another equipment change: the saved copy stays the old values
            assert.are.equal("0.6", _G.FishingMasteryCharDB.sounds.Sound_MusicVolume)

            equip(2488) -- the pole leaves the hand
            assert.are.same(MINE, cvars)
            assert.is_nil(_G.FishingMasteryCharDB.sounds)
            equip(POLE)
            assert.are.same(LOUD, cvars)
            set("loudSplash", false)
            assert.are.same(MINE, cvars)
            assert.are.equal(0, w.ns.Guard.errors)
        end)

        it(
            "restores at logout and sets them again after a /reload with the pole in hand",
            function()
                set("loudSplash", true)
                w.fire("PLAYER_LOGOUT")
                assert.are.same(MINE, cvars)
                assert.is_nil(_G.FishingMasteryCharDB.sounds)
                login()
                assert.are.same(LOUD, cvars)
                assert.are.equal("0.6", _G.FishingMasteryCharDB.sounds.Sound_MusicVolume)
            end
        )

        it("restores a copy left without logout at the next login without a pole", function()
            set("loudSplash", true)
            game.pole = nil -- the session ended without logout; next login without the pole
            login()
            assert.are.same(MINE, cvars)
            assert.is_nil(_G.FishingMasteryCharDB.sounds)
            -- With the pole still in hand the copy is kept, not saved again over the loud values.
            game.pole = POLE
            w.ns.soundBoost:Update()
            local copy = _G.FishingMasteryCharDB.sounds
            login()
            assert.are.equal(
                copy.Sound_MusicVolume,
                _G.FishingMasteryCharDB.sounds.Sound_MusicVolume
            )
            assert.are.equal("0.6", _G.FishingMasteryCharDB.sounds.Sound_MusicVolume)
        end)
    end)

    describe("hidden interface", function()
        local function lineOut(t)
            w.at(t or 6000, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        end

        it("changes nothing with the setting off", function()
            assert.is_false(w.ns.Options.Default("hideUI"))
            lineOut()
            w.fire("PLAYER_STARTED_MOVING")
            assert.are.same({}, visibility)
        end)

        it("hides when the line goes out and comes back for every reason", function()
            set("hideUI", true)
            local reasons = {
                { "PLAYER_STARTED_MOVING", "moving" },
                { "PLAYER_REGEN_DISABLED", "combat" },
                { "PLAYER_DEAD", "dead" },
                { "PLAYER_TARGET_CHANGED", "target" },
                { "CHAT_MSG_WHISPER", "whisper" },
                { "CHAT_MSG_BN_WHISPER", "whisper" },
                { "PARTY_INVITE_REQUEST", "dialog" },
                { "TRADE_SHOW", "dialog" },
                { "PLAYER_MOUNT_DISPLAY_CHANGED", "mount" },
                { "LOADING_SCREEN_ENABLED", "loading" },
                { "PLAYER_LEAVING_WORLD", "loading" },
                { "PLAYER_LOGOUT", "logout" },
            }
            for _, case in ipairs(reasons) do
                visibility = {}
                lineOut()
                assert.is_false(w.env.UIParent.shown)
                w.fire(case[1])
                assert.is_true(w.env.UIParent.shown, case[1])
                assert.are.equal(case[2], w.ns.hideUI.shownBy)
                assert.are.same({ false, true }, visibility)
            end

            lineOut()
            w.fire("LOOT_OPENED", true) -- auto loot: stays hidden
            assert.is_false(w.env.UIParent.shown)
            w.fire("LOOT_OPENED", false)
            assert.are.equal("loot", w.ns.hideUI.shownBy)

            lineOut()
            equip(POLE) -- still a pole: stays hidden
            assert.is_false(w.env.UIParent.shown)
            equip(nil)
            assert.are.equal("pole", w.ns.hideUI.shownBy)

            game.pole = POLE
            lineOut()
            set("hideUI", false)
            assert.are.equal("setting", w.ns.hideUI.shownBy)
            assert.is_true(w.env.UIParent.shown)
            assert.are.equal(0, w.ns.Guard.errors)
        end)

        it("does not hide in combat, when dead, or when the player hid it", function()
            set("hideUI", true)
            game.combat = true
            lineOut()
            game.combat, game.dead = false, true
            lineOut()
            game.dead = false
            w.env.UIParent.shown = false -- Alt+Z by the player
            lineOut()
            w.fire("PLAYER_STARTED_MOVING")
            assert.are.same({}, visibility)
            assert.is_false(w.env.UIParent.shown)
        end)

        it("lets go when the player brings it back with Alt+Z", function()
            set("hideUI", true)
            lineOut()
            w.env.UIParent.shown = true -- Alt+Z
            w.fire("PLAYER_STARTED_MOVING")
            assert.are.same({ false }, visibility) -- nothing to show
            lineOut(6100) -- the next cast hides it again
            assert.are.same({ false, false }, visibility)
        end)

        it("shows the catches on WorldFrame while hidden and clears them", function()
            set("hideUI", true)
            w.catch(6000, 5) -- hides at the channel start; the catch comes in hidden
            local f = w.ns.hideUI.frame
            assert.are.equal(_G.WorldFrame, f.parent)
            assert.is_true(f:IsShown())
            assert.are.equal("|cffffffff+1 Raw Slitherskin Mackerel|r", f.texts[1]:GetText())
            w.catch(6010, 5)
            assert.are.equal(f.texts[1]:GetText(), f.texts[2]:GetText())
            w.runTimers(6021)
            assert.is_false(f:IsShown())

            w.catch(6030, 5)
            assert.is_true(f:IsShown())
            w.fire("PLAYER_STARTED_MOVING")
            assert.is_false(f:IsShown())
            -- Not hidden: no catch line.
            w.catch(6040, 5)
            w.fire("PLAYER_STARTED_MOVING")
            visibility = {}
            set("hideUI", false)
            w.catch(6050, 5)
            assert.is_false(f:IsShown())
            assert.are.same({}, visibility)
            assert.are.equal(0, w.ns.Guard.errors)
        end)
    end)
end)
