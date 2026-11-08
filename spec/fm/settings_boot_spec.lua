-- Settings panel and minimap button boot tests through every TOC file: the panel registers one
-- control per setting, changes apply at once (HUD, thresholds, minimap button), sliders are left
-- out without the slider API, the button is dragged around the minimap and keeps its angle over
-- a /reload, its clicks open the stats window and the settings, the compartment opens the
-- window, and a new idle cap T counts the totals again at the next login.
local fakeui = require("spec.helpers.fakeui")
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")

-- Globals the stubs set; removed after each test.
local STUBS = { "Settings", "Minimap", "GetCursorPosition", "GetMinimapShape" }

-- A Settings API that records categories, settings, and controls.
local function stubSettings(opts)
    local log = { settings = {}, checkboxes = {}, sliders = {}, opened = {} }
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            log.category = {
                name = name,
                GetID = function()
                    return 77
                end,
            }
            return log.category
        end,
        RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
            local setting = { variable = variable, key = key, tbl = tbl, varType = varType }
            setting.name, setting.default = name, default
            log.settings[key] = setting
            return setting
        end,
        CreateCheckbox = function(_, setting)
            log.checkboxes[#log.checkboxes + 1] = setting.key
        end,
        RegisterAddOnCategory = function(category)
            category.registered = true
        end,
        OpenToCategory = function(id)
            log.opened[#log.opened + 1] = id
        end,
    }
    if not (opts and opts.noSliders) then
        _G.Settings.CreateSliderOptions = function(lo, hi, step)
            return { range = { lo, hi, step } }
        end
        _G.Settings.CreateSlider = function(_, setting, options)
            log.sliders[#log.sliders + 1] = setting.key
            setting.range = options.range
        end
    end
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

    it("registers one control per setting; changes apply at once", function()
        assert.are.equal("Fishing Mastery", log.category.name)
        assert.is_true(log.category.registered)
        assert.are.same({
            "hudEnabled",
            "hudLocked",
            "hudText",
            "hudZone",
            "summaryChat",
            "minimapShown",
            "tooltipLine",
            "reloadReminder",
            "doubleClick",
            "autoLure",
        }, log.checkboxes)
        assert.are.same({ "hudScale", "countBelow", "greyBelow", "activeCap" }, log.sliders)
        assert.are.same({ 30, 120, 5 }, log.settings.activeCap.range)
        assert.are.equal("FishingMastery_hudScale", log.settings.hudScale.variable)
        assert.are.equal(true, log.settings.hudEnabled.default)

        -- The panel writes through the proxy into the saved settings.
        w.catch(5000, 9)
        local settings = _G.FishingMasteryDB.settings
        local hud = w.ns.hud
        log.settings.hudScale.tbl.hudScale = 1.5
        assert.are.equal(1.5, settings.hud.scale)
        assert.are.equal(1.5, hud.frame:GetScale())
        log.settings.hudText.tbl.hudText = true
        assert.are.equal("text", settings.hud.style)
        log.settings.countBelow.tbl.countBelow = 20
        assert.are.equal(20, hud.thresholds.countBelow)
        assert.are.equal(20, w.ns.stats.thresholds.countBelow)
        log.settings.hudEnabled.tbl.hudEnabled = false
        assert.is_false(hud.frame:IsShown())
        assert.is_false(log.settings.hudEnabled.tbl.hudLocked) -- reads the saved value

        _G.SlashCmdList.FM("settings")
        assert.are.same({ 77 }, log.opened)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("leaves sliders out without the slider API and says so", function()
        w.cleanup()
        log = stubSettings({ noSliders = true })
        stubMinimap(w)
        boot(nil, nil)
        assert.are.equal(10, #log.checkboxes)
        assert.is_nil(log.settings.hudScale)
        w.printed = {}
        _G.SlashCmdList.FM("settings")
        assert.truthy(w.output():find("Setting not shown: hudScale: missing", 1, true))
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

    it("opens the stats window and the settings from the button and the compartment", function()
        local button = w.ns.minimap.button
        button:GetScript("OnClick")(button, "LeftButton")
        assert.is_true(w.ns.stats.frame:IsShown())
        button:GetScript("OnClick")(button, "LeftButton")
        assert.is_false(w.ns.stats.frame:IsShown())
        button:GetScript("OnClick")(button, "RightButton")
        assert.are.same({ 77 }, log.opened)
        _G.FishingMastery_OnAddonCompartmentClick("FishingMastery", "LeftButton")
        assert.is_true(w.ns.stats.frame:IsShown())

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
        log.settings.activeCap.tbl.activeCap = 20
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
