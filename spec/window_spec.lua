local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")

describe("Window", function()
    local ns, env, store, progress, window, logged

    local function create(opts)
        env = fakeui.new(opts)
        ns = addon.load({
            "Locale.lua",
            "Guard.lua",
            "Steps.lua",
            "Progress.lua",
            "View.lua",
            "Window.lua",
            "Checklist.lua",
        })
        logged = {}
        progress = ns.Progress.New(store, ns.Steps, {
            log = function(kind, data)
                logged[#logged + 1] = { kind = kind, data = data }
            end,
            onChange = function()
                if window then
                    window:Refresh()
                end
            end,
        })
        window = nil
        window = ns.Window.Create(env, {
            progress = progress,
            store = store,
            info = function()
                return { snapshot = { count = 24, supported = 35 }, events = 36 }
            end,
        })
        return window
    end

    local function click(label)
        return fakeui.button(env, label):Click()
    end

    before_each(function()
        store = {}
    end)

    it("starts hidden, centered, movable, and without named frames", function()
        create()
        assert.is_false(window.frame:IsShown())
        assert.are.same({ "CENTER", env.UIParent, "CENTER", 0, 0 }, window.frame.points[1])
        assert.is_true(window.frame.movable)
        assert.are.equal("LeftButton", window.frame.dragButton)
        assert.are.equal("BasicFrameTemplateWithInset", window.frame.template)
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("renders the current step when shown and toggles", function()
        create()
        window:Toggle()
        assert.is_true(window.frame:IsShown())
        assert.are.equal("Step S0 (1 of 16)", window.lines.header:GetText())
        assert.truthy(window.lines.extra:GetText():find("24 entries", 1, true))
        assert.is_false(fakeui.button(env, "Start"):IsShown())
        assert.is_false(fakeui.button(env, "Back"):IsEnabled())
        window:Toggle()
        assert.is_false(window.frame:IsShown())
    end)

    it("drives the progress with Start, Done, and Back and updates the counter", function()
        create()
        window:Show()
        for _ = 1, 3 do
            assert.is_true(click("Done"))
        end
        assert.are.equal("S3", progress:Current().id)
        assert.are.equal("Catches: 0 / 5", window.lines.counter:GetText())
        assert.is_true(fakeui.button(env, "Start"):IsShown())
        assert.is_true(click("Start"))
        assert.is_false(fakeui.button(env, "Start"):IsEnabled())
        progress:Observe("attempt", { outcome = "catch" })
        assert.are.equal("Catches: 1 / 5", window.lines.counter:GetText())
        assert.is_true(click("Back"))
        assert.are.equal("S2", progress:Current().id)
        assert.are.equal("Step S2 (3 of 16)", window.lines.header:GetText())
    end)

    it("asks for a skip reason on required steps", function()
        create()
        window:Show()
        local noItem = fakeui.button(env, "No item")
        assert.is_false(noItem:IsShown())
        assert.is_true(click("Skip"))
        assert.is_true(noItem:IsShown())
        assert.is_false(fakeui.button(env, "Done"):IsShown())
        assert.is_true(click("Cancel"))
        assert.are.equal("S0", progress:Current().id)
        assert.is_false(noItem:IsShown())
        click("Skip")
        assert.is_true(click("No location"))
        assert.are.equal("no_location", progress:Reason("S0"))
        assert.are.equal("S1", progress:Current().id)
        assert.is_true(fakeui.button(env, "Done"):IsShown())
    end)

    it("skips optional steps with one click", function()
        store = { step = "S11" }
        create()
        window:Show()
        assert.truthy(window.lines.title:GetText():find("(optional)", 1, true))
        click("Skip")
        assert.are.equal("optional", progress:Reason("S11"))
        assert.are.equal("S12", progress:Current().id)
        assert.is_false(fakeui.button(env, "No item"):IsShown())
    end)

    it("saves the position after dragging and restores it", function()
        create()
        local frame = window.frame
        frame:GetScript("OnDragStart")(frame)
        assert.is_true(frame.moving)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", 120, 640)
        frame:GetScript("OnDragStop")(frame)
        assert.is_false(frame.moving)
        assert.are.same(
            { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 120, y = 640 },
            store.window
        )
        create()
        assert.are.same({ "TOPLEFT", env.UIParent, "BOTTOMLEFT", 120, 640 }, window.frame.points[1])
    end)

    it("shows the checklist with colored statuses", function()
        create()
        window:Show()
        click("Done")
        click("Checklist")
        local checklist = window.checklist
        assert.is_true(checklist.frame:IsShown())
        assert.are.equal(16, #checklist.lines)
        assert.are.equal("  S0  Login snapshot - Done", checklist.lines[1]:GetText())
        assert.are.same(ns.Checklist.COLORS.done, checklist.lines[1].color)
        assert.are.same(ns.Checklist.COLORS.current, checklist.lines[2].color)
        click("Done")
        assert.are.equal("  S1  Without fishing pole - Done", checklist.lines[2]:GetText())
        click("Checklist")
        assert.is_false(checklist.frame:IsShown())
    end)

    it("falls back to plain frames when templates are missing", function()
        create({
            missingTemplates = { BasicFrameTemplateWithInset = true, UIPanelButtonTemplate = true },
        })
        window:Show()
        assert.is_nil(window.frame.template)
        assert.is_true(click("Done"))
        assert.are.equal("S1", progress:Current().id)
    end)

    it("logs a click error instead of breaking the window", function()
        create()
        window:Show()
        progress.Done = function()
            error("boom")
        end
        assert.is_true(click("Done"))
        assert.are.equal(1, ns.Guard.errors)
    end)

    it("shows the S14 helper buttons only on S14 and enables them after Start", function()
        store.step = "S13"
        create()
        local calls = {}
        window.helpers = function()
            return {
                EnableKey = function()
                    calls[#calls + 1] = "key"
                end,
                SendWhisper = function()
                    calls[#calls + 1] = "whisper"
                end,
            }
        end
        window:Show()
        local key, whisper =
            fakeui.button(env, "Enable test key"), fakeui.button(env, "Send self-whisper")
        assert.is_false(key:IsShown())
        progress:Skip("optional")
        assert.is_true(key:IsShown())
        assert.is_true(whisper:IsShown())
        assert.is_false(key:Click())
        click("Start")
        assert.is_true(key:Click())
        assert.is_true(whisper:Click())
        assert.are.same({ "key", "whisper" }, calls)
        assert.truthy(window.lines.extra:GetText():find("not ready yet", 1, true))
        click("Skip")
        assert.is_false(key:IsShown())
        click("Cancel")
        assert.is_true(key:IsShown())
        click("Done")
        assert.is_false(key:IsShown())
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("plays the advance cue only when the sound API exists", function()
        create()
        ns.Window.PlayCue(env)
        env.SOUNDKIT = { READY_CHECK = 8960 }
        env.PlaySound = function(id)
            env.sounds[#env.sounds + 1] = id
        end
        ns.Window.PlayCue(env)
        env.PlaySound = function()
            error("no sound")
        end
        ns.Window.PlayCue(env)
        assert.are.same({ 8960 }, env.sounds)
    end)
end)
