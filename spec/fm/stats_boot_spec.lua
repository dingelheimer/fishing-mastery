-- Stats window boot tests through every TOC file: /fm stats opens the window, every tab draws
-- without Lua errors, the Overview matches /fm rebuild, Fish sorts and filters, the scope switch
-- merges characters, the position is saved, and the window waits for the count after login.
local fmboot = require("spec.helpers.fmboot")

-- Globals the stubs set; removed after each test.
local STUBS = {
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "CreateScrollBoxListLinearView",
    "ScrollUtil",
    "CreateDataProvider",
    "GetGameTime",
    "date",
}

-- Tab and ScrollBox stubs: a list draws every row of its data provider at once.
local function stubUi(w)
    local tabs = {}
    _G.PanelTemplates_SetNumTabs = function(frame, n)
        frame.numTabs = n
    end
    _G.PanelTemplates_SetTab = function(frame, id)
        tabs.selected = id
        frame.selectedTab = id
    end
    _G.CreateScrollBoxListLinearView = function()
        return {
            SetElementExtent = function() end,
            SetElementInitializer = function(view, _, init)
                view.init = init
            end,
        }
    end
    _G.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(box, _, view)
            box.SetDataProvider = function(_, provider)
                box.drawn = {}
                for i, data in ipairs(provider.rows) do
                    box.pool = box.pool or {}
                    local row = box.pool[i] or w.env.CreateFrame("Frame", nil, box)
                    box.pool[i] = row
                    view.init(row, data)
                    box.drawn[i] = row
                end
            end
        end,
    }
    _G.CreateDataProvider = function(rows)
        return { rows = rows }
    end
    _G.GetGameTime = function()
        return (math.floor((w.serverTime % 86400) / 3600) + 2) % 24, 0
    end
    _G.date = os.date
    _G.C_Map.GetMapInfo = function(map)
        return ({ [1411] = { name = "Durotar" }, [1412] = { name = "Mulgore" } })[map]
    end
    _G.C_Item.GetItemQualityColor = function()
        return 1, 1, 1, "ffffffff"
    end
    return tabs
end

-- Texts of the cells of every drawn row of a list.
local function texts(list)
    local rows = {}
    for i, row in ipairs(list.box.drawn) do
        rows[i] = {}
        for j, cell in ipairs(row.cells) do
            rows[i][j] = cell:GetText()
        end
    end
    return rows
end

describe("FishingMastery stats window boot", function()
    local w, tabs

    before_each(function()
        w = fmboot.new()
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        tabs = stubUi(w)
    end)

    after_each(function()
        w.cleanup()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
    end)

    local function stats()
        return w.ns.stats
    end

    local function fish()
        w.catch(5000, 9)
        w.catch(5020, 12)
        w.at(5040, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(5050, "UI_INFO_MESSAGE", 418, "Your fish got away!")
        w.at(5050.2, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.runTimers(5052)
    end

    it("opens with 8 tabs and draws every tab without Lua errors", function()
        fish()
        _G.SlashCmdList.FM("stats")
        local window = stats()
        assert.is_true(window.frame:IsShown())
        assert.are.equal(8, #window.frame.Tabs)
        assert.are.equal(8, window.frame.numTabs)
        assert.are.equal("Overview", window.frame.Tabs[1]:GetText())
        assert.are.equal("Compare", window.frame.Tabs[8]:GetText())
        for i, tab in ipairs(window.frame.Tabs) do
            assert.is_true(tab:Click())
            assert.are.equal(i, tabs.selected)
            for j, panel in ipairs(window.panels) do
                assert.are.equal(i == j, panel:IsShown())
            end
        end
        local soon = window.panels[4].fontStrings[1]:GetText()
        assert.are.equal("Coming soon in a later version.", soon)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("shows the same casts and catches on the Overview as /fm rebuild", function()
        fish()
        _G.SlashCmdList.FM("stats")
        local text = stats().overviewText:GetText()
        assert.truthy(text:find("All characters: 3 casts, 2 catches on 1 days", 1, true))
        assert.truthy(text:find("favorite zone Durotar", 1, true))
        assert.truthy(text:find("Most catches in a session: 2 (Dingel", 1, true))
        assert.are.same(
            { { "Dingel (you)", "3", "2", "2/3", "-", "Durotar" } },
            texts(stats().characters)
        )
        w.printed = {}
        _G.SlashCmdList.FM("rebuild")
        assert.truthy(
            w.output():find("Totals rebuilt from 3 casts (2 catches) on 1 days.", 1, true)
        )
        assert.truthy(w.output():find("Equal to the live totals.", 1, true))
    end)

    it("lists fish and zones, sorts by a header, and filters by quality", function()
        fish()
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[2]:Click()
        local rows = texts(window.fish)
        assert.are.equal(1, #rows)
        assert.are.equal("|cffffffffRaw Slitherskin Mackerel|r", rows[1][1])
        assert.are.equal("2", rows[1][2])
        assert.are.equal("Durotar", rows[1][4])
        assert.is_true(window.fish.box.drawn[1].cells[3].color[1] < 1) -- 2/2: greyed
        -- Header click: the same column flips the order.
        window.fish.headers[2]:Click()
        assert.are.same({ key = "n", descending = false }, window.sort)
        window.fish.headers[1]:Click()
        assert.are.same({ key = "name", descending = false }, window.sort)
        -- Quality filter: all -> poor (nothing) -> common (the mackerel).
        assert.are.equal("Quality: all", window.qualityButton:GetText())
        window.qualityButton:Click()
        assert.are.equal("Quality: poor", window.qualityButton:GetText())
        assert.are.equal(0, #window.fish.box.drawn)
        window.qualityButton:Click()
        assert.are.equal(1, #window.fish.box.drawn)
        -- Tooltip with the range on hover.
        local row = window.fish.box.drawn[1]
        row:GetScript("OnEnter")(row)
        assert.truthy(table.concat(_G.GameTooltip.lines, "\n"):find("Caught 2 times", 1, true))

        window.frame.Tabs[3]:Click()
        rows = texts(window.zones)
        assert.are.same({ "Durotar", "    Darkspear Strand" }, { rows[1][1], rows[2][1] })
        assert.are.equal("3", rows[1][2])
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("merges every character with the scope button and saves the position", function()
        fish()
        local db = _G.FishingMasteryDB
        local other = { name = "Alt", subzones = { "Darkspear Strand" }, sessions = {} }
        other.totals = w.ns.Totals.New()
        w.ns.Totals.Add(other.totals, {
            t = w.serverTime,
            map = 1412,
            sub = 1,
            out = "catch",
            loot = { { id = 6303 } },
        })
        db.chars["Player-5827-00000001"] = other
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[3]:Click()
        assert.are.equal("This character", window.scopeButton:GetText())
        assert.are.equal(2, #window.zones.box.drawn)
        window.scopeButton:Click()
        assert.are.equal("All characters", window.scopeButton:GetText())
        local names = {}
        for i, row in ipairs(texts(window.zones)) do
            names[i] = row[1]
        end
        assert.are.same(
            { "Durotar", "    Darkspear Strand", "Mulgore", "    Darkspear Strand" },
            names
        )
        window.frame.Tabs[1]:Click()
        assert.is_false(window.scopeButton:IsShown()) -- the Overview always shows both
        assert.are.equal(2, #window.characters.box.drawn)

        local frame = window.frame
        frame:SetPoint("TOP", _G.UIParent, "TOP", 0, -50)
        frame.points = { frame.points[#frame.points] }
        frame:GetScript("OnDragStop")(frame)
        assert.are.equal(-50, _G.FishingMasteryCharDB.ui.stats.y)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("shows that the history is being counted after the update, then the numbers", function()
        fish()
        -- One chunk is counted at login, so the count after an update is set here (CastLog's
        -- steps are covered by the totals boot spec).
        w.ns.castLog.counting = true
        _G.SlashCmdList.FM("stats")
        local window = stats()
        assert.truthy(window.status:GetText():find("Counting your history", 1, true))
        w.ns.castLog.counting = false
        w.runTimers(w.clock + 1) -- the window checks again every second while counting
        assert.are.equal("", window.status:GetText())
        assert.truthy(window.overviewText:GetText():find("3 casts, 2 catches", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("fills in item names that load after the window opened", function()
        fish()
        local loaded = false
        _G.C_Item.GetItemInfo = function()
            if loaded then
                return "Raw Slitherskin Mackerel", "link", 1
            end
        end
        _G.C_Item.RequestLoadItemDataByID = function() end
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[2]:Click()
        assert.are.equal("Item 6303", texts(window.fish)[1][1])
        loaded = true
        w.fire("ITEM_DATA_LOAD_RESULT", 6303, true)
        w.runTimers(w.clock + 0.1)
        assert.are.equal("|cffffffffRaw Slitherskin Mackerel|r", texts(window.fish)[1][1])
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
