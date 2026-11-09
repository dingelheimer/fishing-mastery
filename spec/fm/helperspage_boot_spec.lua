-- The Helpers page (Story 9.6) through every TOC file: /fm helpers prints and opens it, the check
-- boxes write the same settings as before and apply at once, the key-binding button binds and
-- clears "Cast Fishing" only out of combat, "Right now" and "This login" are drawn, and the page
-- redraws while shown.
local fmboot = require("spec.helpers.fmboot")

local STUBS = {
    "GetBindingKey",
    "SetBinding",
    "SaveBindings",
    "GetCurrentBindingSet",
    "InCombatLockdown",
    "IsShiftKeyDown",
    "IsControlKeyDown",
    "IsAltKeyDown",
}

local COMMAND = "CLICK FishingMasteryCastButton:LeftButton"

describe("FishingMastery helpers page boot", function()
    local w, game

    before_each(function()
        w = fmboot.new()
        game = { bindings = {}, saved = nil, combat = false, shift = false }
        _G.GetBindingKey = function(command)
            for key, bound in pairs(game.bindings) do
                if bound == command then
                    return key
                end
            end
        end
        _G.SetBinding = function(key, command)
            game.bindings[key] = command
            return true
        end
        _G.SaveBindings = function(set)
            game.saved = set
        end
        _G.GetCurrentBindingSet = function()
            return 2
        end
        _G.InCombatLockdown = function()
            return game.combat
        end
        _G.IsShiftKeyDown = function()
            return game.shift
        end
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
    end)

    after_each(function()
        w.cleanup()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
    end)

    local function open()
        _G.SlashCmdList.FM("helpers")
        return w.ns.helpersPage
    end

    it("prints the counts and opens the page with every helper off", function()
        local page = open()
        assert.truthy(w.output():find("Helpers this login", 1, true))
        assert.is_true(w.ns.mainWindow:IsShown("helpers"))
        assert.are.equal("Helpers", w.ns.mainWindow.pageName:GetText())
        for _, key in ipairs({ "doubleClick", "autoLure", "loudSplash", "hideUI" }) do
            assert.is_false(page.rows[key].check:GetChecked())
            assert.are.equal("off", page.rows[key].tag:GetText())
        end
        assert.are.equal("Not bound", page.keyButton:GetText())
        assert.are.equal("Casts through the key", page.loginRows[1].label:GetText())
        assert.are.equal("0", page.loginRows[1].value:GetText())
        assert.truthy(page.nowTitle:GetText() ~= "")
        assert.are.equal("", page.conflict:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("turns helpers on at once with the same settings as before", function()
        local page = open()
        local helpers = function()
            return _G.FishingMasteryDB.settings.helpers or {}
        end
        page.rows.loudSplash.check:Click()
        assert.is_true(helpers().loudSplash)
        assert.are.equal("on", page.rows.loudSplash.tag:GetText()) -- no pole: not active yet
        page.rows.autoLure.check:Click()
        assert.is_true(helpers().autoLure)
        assert.are.equal("needs the casting key", page.rows.autoLure.tag:GetText())
        assert.are.same(w.ns.Style.ORANGE, page.rows.autoLure.tag.color)
        page.rows.autoLure.check:Click()
        assert.is_false(helpers().autoLure)
        assert.are.equal("off", page.rows.autoLure.tag:GetText())
        -- The long explanation in the row tooltip, behind Shift.
        local hover = page.rows.hideUI.hover
        hover:GetScript("OnEnter")(hover)
        assert.are.same({ "Hide the interface", " ", "Hold Shift for more" }, _G.GameTooltip.lines)
        game.shift = true
        hover:GetScript("OnEnter")(hover)
        game.shift = false
        assert.truthy(_G.GameTooltip.lines[3]:find("like Alt+Z", 1, true))
        assert.is_true(_G.GameTooltip.wraps[3])
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("binds and clears the casting key, and never in combat", function()
        local page = open()
        local button = page.keyButton
        button:GetScript("OnEnter")(button)
        assert.are.same({
            "Casting key",
            " ",
            "Click, then a key: set",
            "Escape: cancel",
            "Right-click: clear",
        }, _G.GameTooltip.lines)
        button:Click()
        assert.are.equal("Press a key", button:GetText())
        assert.is_true(button.keyboard)
        button:PressKeyboard("LSHIFT") -- a modifier alone waits for the key
        assert.is_true(button.keyboard)
        game.shift = true
        button:PressKeyboard("F")
        assert.are.same({ ["SHIFT-F"] = COMMAND }, game.bindings)
        assert.are.equal(2, game.saved)
        assert.are.equal("SHIFT-F", button:GetText())
        assert.is_false(button.keyboard)
        page.rows.autoLure.check:Click()
        assert.are.equal("on", page.rows.autoLure.tag:GetText()) -- the key is bound now

        -- Escape cancels; a right-click clears.
        game.shift = false
        button:Click()
        button:PressKeyboard("ESCAPE")
        assert.are.same({ ["SHIFT-F"] = COMMAND }, game.bindings)
        button:Click("RightButton")
        assert.are.same({}, game.bindings)
        assert.are.equal("Not bound", button:GetText())

        -- In combat the button is disabled and a waiting capture stops.
        button:Click()
        game.combat = true
        button:Refresh()
        assert.are.equal("Not in combat", button:GetText())
        assert.is_false(button:IsEnabled())
        assert.is_false(button:Click())
        button:PressKeyboard("G")
        assert.are.same({}, game.bindings)
        game.combat = false
        button:Refresh()
        assert.are.equal("Not bound", button:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("redraws every second while shown and stops when hidden", function()
        local page = open()
        _G.FishingMasteryDB.settings.helpers = { hideUI = true }
        w.runTimers(w.clock + 1.1)
        assert.are.equal("on", page.rows.hideUI.tag:GetText())
        w.ns.mainWindow.frame:Hide()
        _G.FishingMasteryDB.settings.helpers.hideUI = false
        w.runTimers(w.clock + 2.2)
        assert.are.equal("on", page.rows.hideUI.tag:GetText()) -- no redraw while hidden
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
