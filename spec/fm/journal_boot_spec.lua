-- Journal window boot tests through every TOC file: /fm journal, Shift-click on the minimap button
-- and on the addon compartment open it; the Fish tab draws with empty and full data, filters,
-- search, and the detail pane; the other tabs are placeholders; the last tab and the position are
-- saved per character; the scope button switches to one character. No Lua errors.
local fmboot = require("spec.helpers.fmboot")
local fakeui = require("spec.helpers.fakeui")
local statsui = require("spec.helpers.statsui")
local texts = statsui.texts

local STUBS = { "Minimap", "IsShiftKeyDown", "C_Spell", "GetMinimapShape" }
local NAMES = { [6303] = "Raw Slitherskin Mackerel", [6291] = "Raw Brilliant Smallfish" }

describe("FishingMastery journal window boot", function()
    local w, tabs

    local function stubItems()
        _G.C_Item.GetItemInfo = function(id)
            return NAMES[id] or ("Item " .. id), "link", 1
        end
        _G.C_Item.GetItemIconByID = function(id)
            return 100000 + id
        end
        _G.C_Spell = {
            GetSpellInfo = function(id)
                return { name = "Recipe " .. id }
            end,
        }
    end

    local function boot(saved, charSaved)
        local minimap = fakeui.new().CreateFrame("Frame")
        minimap.GetWidth = function()
            return 140
        end
        minimap.GetHeight = function()
            return 140
        end
        _G.Minimap = minimap
        w.boot(saved, charSaved)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        tabs = statsui.stub(w)
        stubItems()
    end

    before_each(function()
        w = fmboot.new()
        boot(nil, nil)
    end)

    after_each(function()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
        w.cleanup()
        statsui.cleanup()
    end)

    local function journal()
        return w.ns.journalWindow
    end

    local function fish()
        w.catch(5000, 9)
        w.catch(5020, 12)
        w.runTimers(5022)
    end

    it("opens with 4 tabs and lists every journal fish before any catch", function()
        _G.SlashCmdList.FM("journal")
        local window = journal()
        assert.is_true(window.frame:IsShown())
        assert.are.equal(4, #window.frame.Tabs)
        assert.are.same({ "Fish", "Waters", "Recipes", "Gear" }, {
            window.frame.Tabs[1]:GetText(),
            window.frame.Tabs[2]:GetText(),
            window.frame.Tabs[3]:GetText(),
            window.frame.Tabs[4]:GetText(),
        })
        assert.are.equal(88, #window.fishList.box.drawn)
        assert.truthy(window.progress:GetText():find("^Fish 0 / 28;  Trophy fish 0 / 35"))
        assert.are.equal("Click a fish to see its details.", window.fishDetail:GetText())
        assert.are.equal("All characters", window.scopeButton:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("shows catches, filters, searches, and details the selected fish", function()
        fish()
        _G.SlashCmdList.FM("journal")
        local window = journal()
        local rows = texts(window.fishList)
        assert.are.same({ "Fish", "2", "Durotar" }, { rows[1][2], rows[1][3], rows[1][4] })
        assert.truthy(rows[1][1]:find("Raw Slitherskin Mackerel", 1, true))
        assert.truthy(window.progress:GetText():find("^Fish 1 / 28"))

        assert.are.equal("All groups", window.groupButton:GetText())
        window.groupButton:Click()
        assert.are.equal("Fish", window.groupButton:GetText())
        assert.are.equal(28, #window.fishList.box.drawn)
        window.showButton:Click()
        assert.are.equal("Caught", window.showButton:GetText())
        assert.are.equal(1, #window.fishList.box.drawn)
        window.showButton:Click()
        assert.are.equal(27, #window.fishList.box.drawn)
        window.showButton:Click()
        window.groupButton:Click() -- trophy
        window.groupButton:Click()
        window.groupButton:Click()
        window.groupButton:Click() -- back to all
        assert.are.equal("All groups", window.groupButton:GetText())

        window.searchBox:SetText("smallfish")
        assert.are.equal(1, #window.fishList.box.drawn)
        local row = window.fishList.box.drawn[1]
        row:GetScript("OnMouseUp")(row)
        local detail = window.fishDetail:GetText()
        assert.truthy(detail:find("Raw Brilliant Smallfish", 1, true))
        assert.truthy(detail:find("Not caught yet", 1, true))
        assert.truthy(detail:find("Recipe 7751 (Cooking)", 1, true))

        window.searchBox:SetText("mackerel")
        row = window.fishList.box.drawn[1]
        row:GetScript("OnMouseUp")(row)
        detail = window.fishDetail:GetText()
        assert.truthy(detail:find("Caught 2 times", 1, true))
        assert.truthy(detail:find("First catch: %d+%-%d+%-%d+, Darkspear Strand, Durotar"))
        window.searchBox:SetText("no such fish")
        assert.are.equal("No fish match the filters.", window.fishEmpty:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("keeps the last tab and the position per character", function()
        _G.SlashCmdList.FM("journal")
        local window = journal()
        window.frame.Tabs[3]:Click()
        assert.are.equal(3, tabs.selected)
        assert.is_true(window.panels[3]:IsShown())
        assert.is_false(window.panels[1]:IsShown())
        window.frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 40, -50)
        window.frame:GetScript("OnDragStop")(window.frame)
        assert.are.equal(3, _G.FishingMasteryCharDB.ui.journalTab)
        assert.is_not_nil(_G.FishingMasteryCharDB.ui.journal)

        boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB) -- /reload
        _G.SlashCmdList.FM("journal")
        assert.are.equal(3, journal().tab)
        assert.is_true(journal().panels[3]:IsShown())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("opens with Shift-click on the minimap button and the addon compartment", function()
        local button = w.ns.minimap.button
        _G.IsShiftKeyDown = function()
            return true
        end
        button:GetScript("OnClick")(button, "LeftButton")
        assert.is_true(journal().frame:IsShown())
        button:GetScript("OnClick")(button, "LeftButton")
        assert.is_false(journal().frame:IsShown())
        _G.FishingMastery_OnAddonCompartmentClick("FishingMastery", "LeftButton")
        assert.is_true(journal().frame:IsShown())
        assert.is_nil(w.ns.stats.frame)

        _G.IsShiftKeyDown = function()
            return false
        end
        button:GetScript("OnClick")(button, "LeftButton")
        assert.is_true(w.ns.stats.frame:IsShown())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("limits the list to this character with the scope button", function()
        fish()
        local first = _G.FishingMasteryDB
        -- A second character on the account with a catch of its own.
        local other = { name = "Other", totals = w.ns.Totals.New(), subzones = {} }
        w.ns.Totals.Add(
            other.totals,
            { t = 100, map = 1412, out = "catch", loot = { { id = 6291 } } }
        )
        first.chars["Player-5827-0FFFFFFF"] = other
        _G.SlashCmdList.FM("journal")
        local window = journal()
        assert.truthy(window.progress:GetText():find("^Fish 2 / 28"))
        window.scopeButton:Click()
        assert.are.equal("This character", window.scopeButton:GetText())
        assert.truthy(window.progress:GetText():find("^Fish 1 / 28"))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("lists the waters for the skill and opens a water's fish in the Fish tab", function()
        fish()
        _G.SlashCmdList.FM("journal")
        local window = journal()
        window.frame.Tabs[2]:Click()
        assert.is_false(window.groupButton:IsShown())
        assert.is_false(window.searchBox:IsShown())
        assert.truthy(window.progress:GetText():find("effective skill 11", 1, true))
        local rows = window.watersList.rows
        assert.are.equal(136, #rows)
        assert.are.equal("Click a water to see its fish.", window.watersNote:GetText())
        local durotar
        for i, row in ipairs(rows) do
            if row.area == 14 then
                durotar = window.watersList.box.drawn[i]
            end
        end
        assert.are.same({ "2", "2" }, { durotar.cells[5]:GetText(), durotar.cells[6]:GetText() })
        assert.are.equal("orange", durotar.data.band) -- skill 11 < 25 (base -70 + 95)
        durotar:GetScript("OnMouseUp")(durotar)
        assert.truthy(
            window.watersNote
                :GetText()
                :find("Classic estimate next to your 2 catches here.", 1, true)
        )
        local fishRow = window.watersFish.box.drawn[1]
        assert.truthy(fishRow.cells[1]:GetText():find("Raw Slitherskin Mackerel", 1, true))

        window.fishableButton:Click()
        assert.are.equal("Fishable now", window.fishableButton:GetText())
        assert.is_true(#window.watersList.rows < 136)
        window.sortButton:Click()
        assert.are.equal("Sort: skill", window.sortButton:GetText())

        fishRow = window.watersFish.box.drawn[1]
        fishRow:GetScript("OnMouseUp")(fishRow)
        assert.are.equal(1, window.tab)
        assert.is_true(window.groupButton:IsShown())
        local detail = window.fishDetail:GetText()
        assert.truthy(detail:find("Raw Slitherskin Mackerel", 1, true))
        assert.truthy(detail:find("Caught 2 times", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
