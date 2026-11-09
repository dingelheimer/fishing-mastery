-- Look settings (Story 10.4): warm tints inside window insets and boxes, a solid backing behind
-- the HUD views, both switched as a whole; through every TOC file the Settings page writes and
-- applies "Window panels" and "HUD background", the preview and the HUD follow, Defaults resets
-- them, and /reload keeps them.
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")

describe("FishingMastery look settings", function()
    it("creates tints and backings once and switches them as a whole", function()
        local ns = addon.load({
            "Options.lua",
            "OptionsControls.lua",
            "Look.lua",
        }, nil, "FishingMastery")
        local env = fakeui.new()
        local box, card = env.CreateFrame("Frame"), env.CreateFrame("Frame")
        local tint = ns.Look.Tint(box, ns.Look.WARM_PANEL)
        local backing = ns.Look.Backing(card)
        -- The defaults: warm panels, the game's tooltip background behind the HUD.
        assert.are.same({ true, false }, { tint:IsShown(), backing:IsShown() })
        local c = ns.Look.WARM_PANEL
        assert.are.same({ c[1], c[2], c[3], c[4] }, tint.color)
        assert.are.same({ "TOPLEFT", box, "TOPLEFT", 3, -3 }, { tint:GetPoint(1) })

        ns.Look.Apply({ ui = { panels = "warm" }, hud = { background = "solid" } })
        assert.are.same({ true, true }, { tint:IsShown(), backing:IsShown() })
        -- A box built later starts in the current look.
        assert.is_true(ns.Look.Tint(env.CreateFrame("Frame"), ns.Look.WARM_BODY):IsShown())
        ns.Look.SetPanels("game")
        assert.are.same({ false, true }, { tint:IsShown(), backing:IsShown() })
        ns.Look.Apply({}) -- old saved data without the keys: the defaults
        assert.are.same({ "warm", "tooltip" }, { ns.Look.panels, ns.Look.background })
    end)

    describe("Settings page", function()
        local w

        local function boot(saved, charSaved)
            w.boot(saved, charSaved)
            w.fire("PLAYER_ENTERING_WORLD", true, false)
            statsui.stub(w)
        end

        before_each(function()
            w = fmboot.new()
            boot(nil, nil)
        end)

        after_each(function()
            w.cleanup()
            statsui.cleanup()
        end)

        local function open()
            _G.SlashCmdList.FM("settings")
            return w.ns.settingsPage
        end

        it("writes and applies both looks, follows in the preview and the HUD, resets", function()
            local page = open()
            local settings = _G.FishingMasteryDB.settings
            w.catch(5000, 9) -- the HUD is shown
            local box = w.ns.Controls.Box(_G, _G.UIParent)
            assert.are.equal("Panels: warm", page.controls.uiPanels:GetText())
            assert.are.equal("Game tooltip", page.controls.hudBackground:GetText())
            assert.is_true(box.lookTint:IsShown())

            page.controls.uiPanels:Click()
            assert.are.equal("game", settings.ui.panels)
            assert.are.equal("Panels: game", page.controls.uiPanels:GetText())
            assert.is_false(box.lookTint:IsShown())

            page.controls.hudBackground:Click()
            assert.are.equal("solid", settings.hud.background)
            assert.are.equal("Solid", page.controls.hudBackground:GetText())
            assert.is_true(page.preview.card.lookBacking:IsShown())
            assert.is_true(w.ns.hud.card.card.lookBacking:IsShown())
            assert.is_true(w.ns.hud.card.compact.lookBacking:IsShown())

            page.defaultsButton:Click()
            page.confirm.yes:Click()
            assert.are.same({ "warm", "tooltip" }, { settings.ui.panels, settings.hud.background })
            assert.is_true(box.lookTint:IsShown())
            assert.is_false(page.preview.card.lookBacking:IsShown())
            assert.are.equal(0, w.ns.Guard.errors)
        end)

        it("keeps both looks over a /reload", function()
            local page = open()
            page.controls.uiPanels:Click()
            page.controls.hudBackground:Click()
            boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB) -- /reload
            assert.are.same({ "game", "solid" }, { w.ns.Look.panels, w.ns.Look.background })
            page = open()
            assert.are.equal("Panels: game", page.controls.uiPanels:GetText())
            assert.is_true(page.preview.card.lookBacking:IsShown())
        end)
    end)
end)
