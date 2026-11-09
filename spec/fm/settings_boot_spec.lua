-- The Options launcher and the minimap button through every TOC file: the game's Options entry
-- is a launcher whose button opens the Settings page (a canvas, else a button initializer, else
-- nothing), the minimap button is dragged around the minimap and keeps its angle over a /reload,
-- its clicks open the window and the Settings page, the compartment opens the window, and a new
-- idle cap T set on the page counts the totals again at the next login.
local fakeui = require("spec.helpers.fakeui")
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")

-- Globals the stubs set; removed after each test.
local STUBS = {
    "Settings",
    "SettingsPanel",
    "CreateSettingsButtonInitializer",
    "Minimap",
    "GetCursorPosition",
    "GetMinimapShape",
}

-- A Settings API that records the launcher: a canvas category unless opts.noCanvas.
local function stubSettings(opts)
    local log = { initializers = {} }
    local function category(name, frame)
        log.category = { name = name, frame = frame }
        return log.category
    end
    _G.Settings = {
        RegisterVerticalLayoutCategory = function(name)
            local layout = {
                AddInitializer = function(_, initializer)
                    log.initializers[#log.initializers + 1] = initializer
                end,
            }
            return category(name), layout
        end,
        RegisterAddOnCategory = function(c)
            c.registered = true
        end,
    }
    if not (opts and opts.noCanvas) then
        _G.Settings.RegisterCanvasLayoutCategory = function(frame, name)
            return category(name, frame)
        end
    end
    _G.SettingsPanel = {
        Close = function()
            log.closed = (log.closed or 0) + 1
        end,
    }
    return log
end

-- A 140 × 140 minimap centered at (500, 400) with the cursor at w.cursor.
local function stubMinimap(w)
    local minimap = fakeui.new().CreateFrame("Frame")
    minimap.GetWidth = function()
        return 140
    end
    minimap.GetHeight = function()
        return 140
    end
    minimap.GetCenter = function()
        return 500, 400
    end
    minimap.GetEffectiveScale = function()
        return 1
    end
    _G.Minimap = minimap
    _G.GetCursorPosition = function()
        return w.cursor[1], w.cursor[2]
    end
end

describe("FishingMastery settings and minimap boot", function()
    local w, log

    -- Boots with the stubs; saved and charSaved as from the last session.
    local function boot(saved, charSaved)
        w.boot(saved, charSaved)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
    end

    before_each(function()
        w = fmboot.new()
        w.cursor = { 0, 0 }
        log = stubSettings()
        stubMinimap(w) -- before the boot, which builds the button
        boot(nil, nil)
        statsui.stub(w)
    end)

    after_each(function()
        w.cleanup()
        statsui.cleanup()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
    end)

    it("registers the launcher; its button and /fm settings open the Settings page", function()
        local panel = w.ns.settingsPanel
        assert.are.equal("canvas", panel.kind)
        assert.are.equal("Fishing Mastery", log.category.name)
        assert.is_true(log.category.registered)
        assert.are.equal(panel.frame, log.category.frame)
        assert.are.equal("Open Fishing Mastery settings", panel.button:GetText())
        panel.button:Click()
        assert.are.equal(1, log.closed) -- the game's settings window closes first
        assert.is_true(w.ns.mainWindow:IsShown("settings"))
        w.ns.mainWindow.frame:Hide()
        _G.SlashCmdList.FM("settings")
        assert.is_true(w.ns.mainWindow:IsShown("settings"))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("falls back to a button initializer, and to nothing without one", function()
        w.cleanup()
        log = stubSettings({ noCanvas = true })
        _G.CreateSettingsButtonInitializer = function(name, label, click, tip)
            return { name = name, label = label, click = click, tip = tip }
        end
        stubMinimap(w)
        boot(nil, nil)
        assert.are.equal("button", w.ns.settingsPanel.kind)
        local initializer = log.initializers[1]
        assert.are.equal("Open Fishing Mastery settings", initializer.label)
        initializer.click()
        assert.is_true(w.ns.mainWindow:IsShown("settings"))

        w.cleanup()
        log = stubSettings({ noCanvas = true })
        _G.CreateSettingsButtonInitializer = nil
        stubMinimap(w)
        boot(nil, nil)
        assert.are.equal("none", w.ns.settingsPanel.kind)
        assert.is_true(log.category.registered)
        assert.are.same({}, log.initializers)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("drags the button around the minimap and keeps the angle over a /reload", function()
        local minimap = w.ns.minimap
        local button = minimap.button
        assert.is_true(button:IsShown())
        assert.are.equal(_G.Minimap, button.parent)
        local point = button.points[#button.points]
        assert.are.same({ "CENTER", _G.Minimap, "CENTER" }, { point[1], point[2], point[3] })

        button:GetScript("OnDragStart")(button)
        w.cursor = { 500, 600 } -- straight above the center
        button:GetScript("OnUpdate")(button)
        button:GetScript("OnDragStop")(button)
        assert.is_nil(button:GetScript("OnUpdate"))
        assert.are.equal(90, _G.FishingMasteryCharDB.ui.minimap.angle)
        point = button.points[#button.points]
        assert.is_true(math.abs(point[4]) < 1e-9)
        assert.are.equal(75, point[5])

        _G.SlashCmdList.FM("minimap hide")
        assert.is_false(button:IsShown())
        assert.is_false(_G.FishingMasteryDB.settings.minimap.shown)
        _G.SlashCmdList.FM("minimap show")
        assert.is_true(button:IsShown())

        -- /reload: the saved angle places the new button; a square minimap follows corners.
        local saved, charSaved = _G.FishingMasteryDB, _G.FishingMasteryCharDB
        _G.SlashCmdList.FM("minimap hide")
        boot(saved, charSaved)
        _G.GetMinimapShape = function()
            return "SQUARE"
        end
        w.ns.minimap:Update()
        assert.is_nil(w.ns.minimap.button) -- hidden setting kept: no button built
        _G.SlashCmdList.FM("minimap show")
        point = w.ns.minimap.button.points[#w.ns.minimap.button.points]
        assert.are.equal(75, point[5])
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("opens the main window and the settings from the button and the compartment", function()
        local button = w.ns.minimap.button
        button:GetScript("OnClick")(button, "LeftButton")
        assert.is_true(w.ns.stats.frame:IsVisible()) -- the first page without a saved one
        button:GetScript("OnClick")(button, "LeftButton")
        assert.is_false(w.ns.stats.frame:IsVisible())
        button:GetScript("OnClick")(button, "RightButton")
        assert.is_true(w.ns.mainWindow:IsShown("settings"))
        w.ns.mainWindow.frame:Hide()
        _G.FishingMastery_OnAddonCompartmentClick("FishingMastery", "LeftButton")
        assert.is_true(w.ns.mainWindow:IsShown("settings")) -- the last page

        button:GetScript("OnEnter")(button)
        assert.are.equal("Fishing Mastery", _G.GameTooltip.lines[1])
        assert.are.equal("No open fishing session.", _G.GameTooltip.lines[2])
        w.catch(5000, 9)
        button:GetScript("OnEnter")(button)
        assert.truthy(
            table.concat(_G.GameTooltip.lines, "\n"):find("Success: 1 of 1 fair casts", 1, true)
        )
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("counts the totals again at the next login after a new idle cap T", function()
        w.catch(5000, 9)
        w.catch(5030, 9)
        local totals = _G.FishingMasteryDB.chars[w.ns.stats.charKey].totals
        local before = totals.active[1411]
        w.printed = {}
        _G.SlashCmdList.FM("settings")
        w.ns.settingsPage.controls.activeCap:Drag(20)
        assert.truthy(w.output():find("Idle cap set to 30 s", 1, true)) -- clamped to 30
        assert.are.equal(60, w.ns.Totals.cap) -- this login keeps its T

        local saved, charSaved = _G.FishingMasteryDB, _G.FishingMasteryCharDB
        w.fire("PLAYER_LOGOUT")
        boot(saved, charSaved)
        assert.are.equal(30, w.ns.Totals.cap)
        local rebuilt = _G.FishingMasteryDB.chars[w.ns.stats.charKey].totals
        assert.are.equal(30, rebuilt.cap)
        assert.is_true(rebuilt.active[1411] < before)
        assert.are.equal(30, w.ns.stats.thresholds.activeCap)
        assert.are.equal(0, w.ns.Guard.errors)
        w.ns.Totals.SetCap(60)
    end)
end)
