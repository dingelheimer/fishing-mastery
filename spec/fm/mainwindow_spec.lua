-- The main window (Story 9.2): the page registry and its tab order, page switching, the
-- template decoration and its fallbacks, Escape, and moving by the title (fake pages), then
-- through every TOC file: the Statistics and Journal pages, slash commands, the last page per
-- character, and the removed positions of the old windows.
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")

local FILES = {
    "Locale.lua",
    "LocaleUI.lua",
    "Guard.lua",
    "Style.lua",
    "Tip.lua",
    "Frames.lua",
    "Controls.lua",
    "MainWindow.lua",
}

describe("FishingMastery main window", function()
    local ns, env, store, log

    local function page(key, order)
        return {
            key = key,
            label = "Page " .. key,
            icon = "icon-" .. key,
            order = order,
            build = function(_, panel)
                log[#log + 1] = "build " .. key
                panel.built = key
            end,
            show = function()
                log[#log + 1] = "show " .. key
            end,
        }
    end

    local function start(opts)
        ns = addon.load(FILES, nil, "FishingMastery")
        env = fakeui.new(opts)
        env.UISpecialFrames = {}
        store, log = { stats = { point = "TOP", x = 1, y = 2 }, minimap = { angle = 9 } }, {}
        ns.MainWindow.Register(page("journal", 20))
        ns.MainWindow.Register(page("stats", 10))
        ns.MainWindow.Register(page("helpers", 30))
        return ns.MainWindow.Start({ env = env, store = store })
    end

    it("orders the tabs by order, replaces a page with the same key, rejects bad pages", function()
        local window = start()
        ns.MainWindow.Register(page("journal", 25))
        assert.has_error(function()
            ns.MainWindow.Register({ key = "x" })
        end)
        window:Open()
        local keys = {}
        for i, tab in ipairs(window.tabs) do
            keys[i] = tab.key
        end
        assert.are.same({ "stats", "journal", "helpers" }, keys)
        assert.are.equal("icon-stats", window.tabs[1].Icon.texture)
        -- The first tab hangs on the right edge outside the frame, the others below it.
        assert.are.same({ "TOPLEFT", window.frame, "TOPRIGHT", 0, -36 }, window.tabs[1].points[1])
        assert.are.same({ "TOP", window.tabs[1], "BOTTOM", 0, -6 }, window.tabs[2].points[1])
    end)

    it("opens on the first page, switches pages, and builds each page once", function()
        local window = start()
        window:Open()
        assert.are.equal("stats", window.page)
        assert.are.same({ "build stats", "show stats" }, log)
        assert.is_true(window.tabs[1]:GetChecked())
        assert.are.equal("Page stats", window.pageName:GetText())
        window.tabs[2]:Click()
        assert.are.equal("journal", store.page)
        assert.is_false(window.panels.stats:IsShown())
        assert.is_true(window.panels.journal:IsVisible())
        assert.is_false(window.tabs[1]:GetChecked())
        assert.is_true(window.tabs[2].SelectedTexture:IsShown())
        window.tabs[1]:Click()
        assert.are.same(
            { "build stats", "show stats", "build journal", "show journal", "show stats" },
            log
        )
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("toggles per page and reopens on the last page", function()
        local window = start()
        store.page = "helpers"
        window:Toggle()
        assert.is_true(window:IsShown("helpers"))
        window:Toggle("journal") -- another page: switch, stay open
        assert.is_true(window:IsShown("journal"))
        window:Toggle("journal")
        assert.is_false(window:IsShown())
        window:Open()
        assert.are.equal("journal", window.page)
        window:Open("missing") -- unknown keys fall back to the first page
        assert.are.equal("stats", window.page)
    end)

    it("decorates the portrait frame, closes with Escape and the close button", function()
        local window = start()
        window:Open()
        local frame = window.frame
        assert.are.equal("ButtonFrameTemplate", frame.template)
        assert.are.equal("FishingMasteryFrame", frame.name)
        assert.are.same({ "FishingMasteryFrame" }, env.UISpecialFrames)
        assert.are.equal("Fishing Mastery", frame.TitleContainer.TitleText:GetText())
        assert.are.equal(
            "Interface\\Icons\\Trade_Fishing",
            frame.PortraitContainer.portrait.texture
        )
        assert.are.same({ "TOPLEFT", frame, "TOPLEFT", 4, -56 }, frame.Inset.points[1])
        assert.are.same({ 820, 500 }, { frame.width, frame.height })
        frame.CloseButton:Click()
        assert.is_false(window:IsShown())
        -- The old windows' positions are gone; other layout keys stay.
        assert.is_nil(store.stats)
        assert.are.same({ angle = 9 }, store.minimap)
    end)

    it("moves by the title and saves the position", function()
        local window = start()
        window:Open()
        local frame, handle = window.frame, window.handle
        handle:GetScript("OnDragStart")(handle)
        assert.is_true(frame.moving)
        frame.points = { { "TOPLEFT", env.UIParent, "TOPLEFT", 40, -50 } }
        handle:GetScript("OnDragStop")(handle)
        assert.are.same(
            { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 40, y = -50 },
            store.main
        )
        assert.is_nil(frame.scripts.OnDragStop) -- only the title drags
    end)

    it("shows the page name in a tooltip on the side tab", function()
        local window = start()
        window:Open()
        local tab = window.tabs[2]
        tab:GetScript("OnEnter")(tab)
        assert.are.same({ "Page journal" }, env.GameTooltip.lines)
        assert.are.equal("ANCHOR_RIGHT", env.GameTooltip.anchor)
        tab:GetScript("OnLeave")(tab)
        assert.is_false(env.GameTooltip.shown)
    end)

    it("falls back to the inset frame, then the old frame, and hand-built side tabs", function()
        local window = start({
            missingTemplates = { ButtonFrameTemplate = true, LargeSideTabButtonTemplate = true },
        })
        window:Open()
        assert.are.equal("PortraitFrameTemplate", window.frame.template)
        local inset
        for _, frame in ipairs(env.frames) do
            if frame.parent == window.frame and frame.template == "InsetFrameTemplate" then
                inset = frame
            end
        end
        assert.is_truthy(inset)
        local tab = window.tabs[1]
        assert.is_nil(tab.template)
        assert.are.equal("icon-stats", tab.Icon.texture)
        assert.is_true(tab.SelectedTexture:IsShown())
        assert.is_false(window.tabs[2].SelectedTexture:IsShown())

        window = start({
            missingTemplates = { ButtonFrameTemplate = true, PortraitFrameTemplate = true },
        })
        window:Open()
        assert.are.equal("BasicFrameTemplateWithInset", window.frame.template)
        assert.are.equal("Fishing Mastery", window.frame.fontStrings[1]:GetText())
        assert.are.equal(0, ns.Guard.errors)
    end)
end)

describe("FishingMastery main window boot", function()
    local w

    before_each(function()
        w = fmboot.new()
        w.boot(nil, { schemaVersion = 1, ui = { stats = { point = "TOP", x = 0, y = 0 } } })
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        statsui.stub(w)
    end)

    after_each(function()
        w.cleanup()
        statsui.cleanup()
    end)

    it("opens the pages with the slash commands and the side tabs", function()
        local main = w.ns.mainWindow
        assert.is_nil(_G.FishingMasteryCharDB.ui.stats)
        _G.SlashCmdList.FM("journal")
        assert.is_true(main:IsShown("journal"))
        assert.are.equal("Journal", main.pageName:GetText())
        assert.are.equal(2, #main.tabs)
        assert.is_true(w.ns.journalWindow.frame.Tabs[1]:IsVisible())
        _G.SlashCmdList.FM("stats")
        assert.is_true(main:IsShown("stats"))
        assert.is_true(w.ns.stats.frame.Tabs[1]:IsVisible())
        assert.is_false(w.ns.journalWindow.frame.Tabs[1]:IsVisible()) -- only this page's tabs
        -- The scope dropdown sits at the top right of the page (hidden on the Overview tab).
        local scope = w.ns.stats.scopeButton
        assert.are.same({ "TOPRIGHT", w.ns.stats.frame, "TOPRIGHT", -14, -29 }, scope.points[1])
        assert.are.equal("InsetFrameTemplate", scope.template)
        main.tabs[2]:Click()
        assert.is_true(w.ns.journalWindow.frame:IsVisible())
        assert.is_false(w.ns.stats.frame:IsVisible())
        assert.are.same({ "FishingMasteryFrame" }, _G.UISpecialFrames)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("reopens on the last page after a reload", function()
        _G.SlashCmdList.FM("journal")
        w.ns.mainWindow.frame:Hide()
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB) -- /reload
        statsui.stub(w)
        _G.FishingMastery_OnAddonCompartmentClick("FishingMastery", "LeftButton")
        assert.is_true(w.ns.mainWindow:IsShown("journal"))
        assert.are.equal("journal", _G.FishingMasteryCharDB.ui.page)
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
