-- Boot tests for the UI API check (/fm dev ui) and the addon compartment handler: every API
-- missing (the plain fake UI), every API present (stubs), and APIs that raise. No case may
-- produce a Lua error.
local fmboot = require("spec.helpers.fmboot")
local fakeui = require("spec.helpers.fakeui")

-- Globals the stubs set; removed after each test.
local UI_STUBS = {
    "Settings",
    "ScrollUtil",
    "CreateScrollBoxListLinearView",
    "CreateDataProvider",
    "ITEM_QUALITY_COLORS",
    "TooltipDataProcessor",
    "Enum",
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "GetMinimapShape",
    "AddonCompartmentFrame",
}
local FRAME_METHODS = { "CreateLine", "CreateTexture" }

-- A region that accepts and records every method call (lines and textures).
local function recorder(log)
    return setmetatable({ calls = {} }, {
        __index = function(region, method)
            return function(_, ...)
                region.calls[#region.calls + 1] = { method, ... }
                if log and log[method] then
                    log[method](...)
                end
            end
        end,
    })
end

local function byName(result)
    local map = {}
    for _, entry in ipairs(result.results) do
        map[entry.name] = entry
    end
    return map
end

-- Installs working stubs for every checked API; returns the call log.
local function stubAll(w)
    local log = { categories = {}, opened = {}, checkboxes = {}, postCalls = {}, tabs = {} }
    fakeui.Frame.CreateLine = function()
        log.line = recorder(log.lineErrors)
        return log.line
    end
    fakeui.Frame.CreateTexture = function()
        return recorder()
    end
    _G.Settings = {
        VarType = { Boolean = "boolean" },
        RegisterVerticalLayoutCategory = function(name)
            local category = {
                name = name,
                GetID = function()
                    return 42
                end,
            }
            log.categories[#log.categories + 1] = category
            return category
        end,
        RegisterAddOnCategory = function(category)
            category.registered = true
        end,
        OpenToCategory = function(id)
            log.opened[#log.opened + 1] = id
        end,
        RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
            tbl[key] = default
            return { variable = variable, varType = varType, name = name }
        end,
        CreateCheckbox = function(_, setting)
            log.checkboxes[#log.checkboxes + 1] = setting
        end,
    }
    _G.CreateScrollBoxListLinearView = function()
        return {
            SetElementExtent = function(view, extent)
                view.extent = extent
            end,
            SetElementInitializer = function(view, frameType, init)
                view.frameType, view.init = frameType, init
            end,
        }
    end
    _G.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(box, _, view)
            box.SetDataProvider = function(_, provider)
                log.rows = {}
                for _, data in ipairs(provider.rows) do
                    local row = w.env.CreateFrame(view.frameType, nil, box)
                    view.init(row, data)
                    log.rows[#log.rows + 1] = row.label:GetText()
                end
            end
        end,
    }
    _G.CreateDataProvider = function(rows)
        return {
            rows = rows,
            GetSize = function(provider)
                return #provider.rows
            end,
        }
    end
    _G.C_Item.GetItemIconByID = function()
        return 133910
    end
    _G.C_Item.GetItemQualityColor = function()
        return 0, 0.44, 0.87, "ff0070dd"
    end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Enum = { TooltipDataType = { Item = 0 } }
    _G.TooltipDataProcessor = {
        AddTooltipPostCall = function(dataType, fn)
            log.postCalls[#log.postCalls + 1] = { dataType = dataType, fn = fn }
        end,
    }
    _G.PanelTemplates_SetNumTabs = function(frame, count)
        log.tabs.count, log.tabs.list = count, frame.Tabs
    end
    _G.PanelTemplates_SetTab = function(_, id)
        log.tabs.selected = id
    end
    _G.GetMinimapShape = function()
        return "ROUND"
    end
    _G.AddonCompartmentFrame = {}
    return log
end

describe("FishingMastery UI check boot", function()
    local w
    local saved = {}

    before_each(function()
        -- The plain fake UI has textures (the HUD uses them); the check starts without them.
        for _, method in ipairs(FRAME_METHODS) do
            saved[method] = fakeui.Frame[method]
            fakeui.Frame[method] = nil
        end
        w = fmboot.new()
        w.boot({ schemaVersion = 1, chars = {}, settings = { dev = true } }, nil)
    end)

    after_each(function()
        for _, name in ipairs(UI_STUBS) do
            _G[name] = nil
        end
        for _, method in ipairs(FRAME_METHODS) do
            fakeui.Frame[method] = saved[method]
        end
        w.cleanup()
    end)

    it("is a dev command only", function()
        _G.FishingMasteryDB.settings.dev = nil
        _G.SlashCmdList.FM("dev ui")
        assert.truthy(w.output():find("Unknown command: dev", 1, true))
        assert.is_nil(w.ns.UiCheck.result)
    end)

    it("reports every missing API without Lua errors", function()
        _G.SlashCmdList.FM("dev ui")
        local result = _G.FishingMasteryDB.dev.ui
        assert.are.equal(w.serverTime, result.at)
        assert.are.equal(#w.ns.UiCheck.CHECKS, #result.results)
        for _, entry in ipairs(result.results) do
            assert.are.equal("missing", entry.status, entry.name)
        end
        local map = byName(result)
        assert.are.equal("Frame:CreateLine", map["Frame:CreateLine"].detail)
        assert.are.equal(
            "Settings.RegisterVerticalLayoutCategory, Settings.RegisterAddOnCategory, "
                .. "Settings.OpenToCategory",
            map["Settings API"].detail
        )
        assert.truthy(
            w.output():find("GetMinimapShape: missing - GetMinimapShape (normal", 1, true)
        )
        assert.truthy(w.output():find("UI check: 0 ok, 11 missing, 0 errors.", 1, true))
        assert.is_true(w.ns.UiCheck.state.window.frame:IsShown())

        -- The settings button without a category says so instead of failing.
        fakeui.button(w.env, "Open settings"):Click()
        assert.truthy(w.output():find("Open settings: no category", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("uses every present API, once per session", function()
        local log = stubAll(w)
        _G.SlashCmdList.FM("dev ui")
        local result = _G.FishingMasteryDB.dev.ui
        for _, entry in ipairs(result.results) do
            assert.are.equal("ok", entry.status, entry.name .. ": " .. tostring(entry.detail))
        end
        local map = byName(result)
        assert.are.equal("category 42, checkbox ok", map["Settings API"].detail)
        assert.are.equal("3 rows, scroll bar EventFrame", map["ScrollBox list"].detail)
        assert.are.equal("icon 133910", map["C_Item.GetItemIconByID"].detail)
        assert.are.equal("0 0.44 0.87 ff0070dd", map["C_Item.GetItemQualityColor"].detail)
        assert.are.equal("PanelTabButtonTemplate", map["Tab templates"].detail)
        assert.are.equal("ROUND", map.GetMinimapShape.detail)
        assert.are.same({ "Row 1", "Row 2", "Row 3" }, log.rows)
        assert.are.same({ "SetColorTexture", 1, 0.82, 0, 1 }, log.line.calls[1])
        assert.are.same({ "SetThickness", 2 }, log.line.calls[4])
        assert.are.equal(2, log.tabs.count)
        assert.are.equal(1, log.tabs.selected)
        assert.is_true(log.categories[1].registered)
        assert.are.equal("FishingMastery_UiCheck", log.checkboxes[1].variable)
        assert.are.same({ flag = false }, _G.FishingMasteryDB.dev.uiSetting)
        assert.truthy(w.output():find("UI check: 11 ok, 0 missing, 0 errors.", 1, true))

        fakeui.button(w.env, "Open settings"):Click()
        assert.are.same({ 42 }, log.opened)
        assert.are.equal("ok", result.openSettings)

        -- The tooltip line appears for items while the dev flag is set.
        local postCall = log.postCalls[1]
        assert.are.equal(0, postCall.dataType)
        local lines = {}
        local tooltip = {
            AddLine = function(_, text)
                lines[#lines + 1] = text
            end,
        }
        postCall.fn(tooltip, { id = 6303 })
        postCall.fn(tooltip, {})
        assert.are.same({ "Fishing Mastery UI check: item 6303" }, lines)
        assert.are.equal(1, result.tooltipSeen)

        -- Tab clicks select the tab through PanelTemplates.
        log.tabs.list[2]:Click()
        assert.are.equal(2, log.tabs.selected)

        -- A second run reuses the window, the category, and the post-call.
        local window, scrollBox = w.ns.UiCheck.state.window, w.ns.UiCheck.state.window.scrollBox
        _G.SlashCmdList.FM("dev ui")
        assert.are.equal(window, w.ns.UiCheck.state.window)
        assert.are.equal(scrollBox, window.scrollBox)
        assert.are.equal(1, #log.categories)
        assert.are.equal(1, #log.postCalls)
        assert.are.equal(0, w.ns.Guard.errors)

        -- Without the dev flag the tooltip stays unchanged.
        _G.FishingMasteryDB.settings.dev = nil
        postCall.fn(tooltip, { id = 6303 })
        assert.are.equal(1, #lines)
    end)

    it("reports APIs that raise as errors and keeps going", function()
        local log = stubAll(w)
        log.lineErrors = {
            SetThickness = function()
                error("bad thickness", 0)
            end,
        }
        _G.Settings.RegisterVerticalLayoutCategory = function()
            error("no categories", 0)
        end
        _G.Settings.RegisterAddOnSetting = nil
        _G.CreateFrame = function(frameType, name, parent, template)
            if template and template:find("Tab") then
                error("Couldn't find inherited node: " .. template)
            end
            return w.env.CreateFrame(frameType, name, parent, template)
        end
        _G.SlashCmdList.FM("dev ui")
        local map = byName(_G.FishingMasteryDB.dev.ui)
        assert.are.same(
            { status = "error", detail = "bad thickness", name = "Frame:CreateLine" },
            map["Frame:CreateLine"]
        )
        assert.are.equal("no categories", map["Settings API"].detail)
        assert.truthy(
            map["Tab templates"].detail:find("no tab template of PanelTabButtonTemplate", 1, true)
        )
        assert.are.equal("ok", map["ScrollBox list"].status)
        assert.truthy(w.output():find("UI check: 8 ok, 0 missing, 3 errors.", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("keeps the checkbox error in the detail", function()
        stubAll(w)
        _G.Settings.CreateCheckbox = function()
            error("wrong arguments", 0)
        end
        _G.SlashCmdList.FM("dev ui")
        local map = byName(_G.FishingMasteryDB.dev.ui)
        assert.are.equal("category 42, checkbox error wrong arguments", map["Settings API"].detail)
    end)

    it("runs the compartment handler through the guard", function()
        assert.are.equal("function", type(_G.FishingMastery_OnAddonCompartmentClick))
        _G.FishingMastery_OnAddonCompartmentClick("FishingMastery", "LeftButton")
        assert.truthy(w.output():find("Addon compartment works", 1, true))

        _G.SlashCmdList.FM("dev ui")
        _G.FishingMastery_OnAddonCompartmentClick("FishingMastery", "LeftButton")
        assert.are.equal(1, _G.FishingMasteryDB.dev.ui.compartmentClicks)

        w.ns.Print = function()
            error("chat broken")
        end
        _G.FishingMastery_OnAddonCompartmentClick("FishingMastery", "LeftButton")
        assert.are.equal(1, w.ns.Guard.errors)
        assert.are.equal("compartment", w.ns.recentErrors[1].where)
    end)
end)
