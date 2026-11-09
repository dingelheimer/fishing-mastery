-- The Settings page (Story 9.7) through every TOC file: every control writes its setting and
-- applies at once, the preview follows layout, scale, and opacity, "Defaults" asks first and
-- leaves the helpers alone, the data buttons run their commands, /reload keeps the values, and a
-- HUD style saved before Epic 9 becomes its layout.
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")

describe("FishingMastery settings page boot", function()
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

    local function hud()
        return _G.FishingMasteryDB.settings.hud
    end

    it("writes every control's setting and applies it at once", function()
        local page = open()
        local c = page.controls
        local settings = _G.FishingMasteryDB.settings
        w.catch(5000, 9) -- a session: the HUD is drawn
        local frame = w.ns.hud.frame

        c.hudLocked:Click()
        assert.is_true(hud().locked)
        c.hudZone:Click()
        assert.is_false(hud().zoneLine)
        c.hudScale:Drag(1.5)
        assert.are.equal(1.5, hud().scale)
        assert.are.equal(1.5, frame:GetScale())
        assert.are.equal("150 %", c.hudScale.valueText:GetText())
        c.hudOpacity:Drag(0.6)
        assert.are.equal(0.6, hud().opacity)
        assert.are.equal(0.6, frame:GetAlpha())
        c.hudLayout:Click()
        assert.are.equal("compact", hud().layout)
        assert.are.equal("Compact", c.hudLayout:GetText())
        c.hudEnabled:Click()
        assert.is_false(hud().enabled)
        assert.is_false(frame:IsShown())

        c.tooltipLine:Click()
        assert.is_false(settings.tooltip.shown)
        c.summaryChat:Click()
        assert.are.equal("chat", settings.summary.style)
        c.minimapShown:Click()
        assert.is_false(settings.minimap.shown)
        c.reloadReminder:Click()
        assert.is_false(settings.reloadReminder)
        c.countBelow:Drag(20)
        assert.are.equal(20, w.ns.stats.thresholds.countBelow)
        assert.are.equal("20 casts", c.countBelow.valueText:GetText())
        c.greyBelow:Drag(41) -- on its step
        assert.are.equal(40, settings.thresholds.greyBelow)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("draws the preview in the layout, scale, and opacity", function()
        local page = open()
        local preview = page.preview
        assert.is_true(preview.card:IsShown())
        assert.is_false(preview.compact:IsShown())
        assert.are.equal("The Barrens", preview.zone:GetText())
        assert.are.equal("no getaways", preview.tag:GetText())
        assert.are.equal("Fishing 154 / 225", preview.bar.text:GetText())
        assert.are.same(w.ns.Style.GREY, preview.numbers[2].value.color) -- 8/9: grey
        page.controls.hudScale:Drag(2)
        assert.are.equal(1.3, preview.card:GetScale()) -- grows only as far as the box allows
        page.controls.hudOpacity:Drag(0.5)
        assert.are.equal(0.5, preview.card:GetAlpha())
        page.controls.hudLayout:Click()
        assert.is_true(preview.compact:IsShown())
        assert.truthy(preview.line:GetText():find("8 catches", 1, true))
        assert.are.equal(0.5, preview.compact:GetAlpha())
    end)

    it("asks before putting the page's settings back, and keeps the helpers", function()
        local page = open()
        page.controls.hudScale:Drag(1.5)
        page.controls.minimapShown:Click()
        _G.FishingMasteryDB.settings.helpers = { hideUI = true }
        page.defaultsButton:Click()
        local confirm = page.confirm
        assert.is_true(confirm.frame:IsShown())
        assert.are.equal(1.5, hud().scale) -- nothing changes before the answer
        confirm.yes:Click()
        assert.are.equal(1, hud().scale)
        assert.is_true(_G.FishingMasteryDB.settings.minimap.shown)
        assert.is_true(_G.FishingMasteryDB.settings.helpers.hideUI)
        assert.are.equal("100 %", page.controls.hudScale.valueText:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("runs the data commands from its buttons", function()
        open()
        local ran = {}
        local dispatch = w.ns.Commands.Dispatch
        w.ns.Commands.Dispatch = function(command)
            ran[#ran + 1] = command
        end
        local buttons = {}
        for _, frame in ipairs(w.env.frames) do
            if frame.frameType == "Button" and frame.text then
                buttons[frame.text] = frame
            end
        end
        buttons["Export data"]:Click()
        buttons["Backups"]:Click()
        buttons["Contribute"]:Click()
        w.ns.Commands.Dispatch = dispatch
        assert.are.same({ "export", "backup", "contribute" }, ran)
    end)

    it("keeps the values over a /reload and turns an old HUD style into its layout", function()
        local page = open()
        page.controls.hudOpacity:Drag(0.7)
        page.controls.hudLayout:Click()
        boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB) -- /reload
        page = open()
        assert.are.equal(0.7, page.controls.hudOpacity:GetValue())
        assert.are.equal("Compact", page.controls.hudLayout:GetText())

        local saved = _G.FishingMasteryDB
        saved.settings.hud = { style = "text", scale = 1.2 } -- as saved before Epic 9
        boot(saved, _G.FishingMasteryCharDB)
        assert.are.equal("compact", hud().layout)
        assert.is_nil(hud().style)
        assert.are.equal(1.2, hud().scale)
        assert.are.equal(1, hud().opacity)
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
