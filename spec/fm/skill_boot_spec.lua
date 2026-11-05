-- Stats window boot tests through every TOC file for Story 3.9: the Skill tab reads the history
-- in steps with a progress line and draws the rank line chart and the pace bars; the Compare tab
-- compares lure on and off, switches kinds, and picks characters; the Overview draws the calendar
-- heatmap with tooltips.
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")
local texts = statsui.texts

describe("FishingMastery skill and compare boot", function()
    local w

    before_each(function()
        w = fmboot.new()
        w.game.rank = 45
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        statsui.stub(w)
    end)

    after_each(function()
        w.cleanup()
        statsui.cleanup()
    end)

    local function stats()
        return w.ns.stats
    end

    local function myChar()
        return _G.FishingMasteryDB.chars[stats().charKey]
    end

    -- 25 packed days before today: day i holds 4 catches at rank 19 + i; totals counted again.
    local function history()
        local Codec, today = w.ns.Codec, w.ns.Codec.Day(w.serverTime)
        local days = myChar().days
        for i = 1, 25 do
            local day, casts = today - 30 + i, {}
            for j = 1, 4 do
                casts[j] = {
                    t = day * 86400 + j * 20,
                    out = "catch",
                    rank = 19 + i,
                    map = 1411,
                    loot = { { id = 6303, qty = 1 } },
                }
            end
            days[#days + 1] = Codec.Encode(day, casts)[1]
        end
        myChar().totals = w.ns.Totals.Rebuild(myChar())
    end

    it("reads the history in steps, then draws the rank chart, pace, and forecast", function()
        history()
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[7]:Click()
        assert.are.equal("Reading your history for the Skill tab: 40 %", window.status:GetText())
        assert.is_nil(window.rankChart.drawn)
        assert.is_false(window.scopeButton:IsShown())
        w.runTimers(w.clock)
        assert.are.equal("Reading your history for the Skill tab: 80 %", window.status:GetText())
        w.runTimers(w.clock)
        assert.are.equal("", window.status:GetText())
        local text = window.skillText:GetText()
        assert.truthy(text:find("Fishing rank 45 of 75", 1, true))
        assert.truthy(text:find("10 points in 40 catches", 1, true))
        assert.truthy(text:find("To the rank cap 75: 30 points, about 120 catches", 1, true))
        -- 25 ranks with a first cast, then rank 45 from the game: 26 points, 25 segments.
        local chart = window.rankChart
        assert.are.equal(26, #chart.drawn.points)
        assert.are.equal(25, chart.lines.used)
        local line = chart.lines.list[1]
        assert.are.equal(2, line.thickness)
        assert.are.equal("BOTTOMLEFT", line.start[1])
        local hover = chart.hovers.list[1]
        hover:GetScript("OnEnter")(hover)
        assert.are.equal("Rank 20", _G.GameTooltip.lines[1])
        assert.are.equal(2, #window.paceChart.drawn.bars)

        -- A later visit reads only what is new.
        window.frame.Tabs[1]:Click()
        window.frame.Tabs[7]:Click()
        assert.are.equal("", window.status:GetText())
        assert.are.equal(25, window.skillScan.index)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("draws points as squares without CreateLine", function()
        history()
        local fakeui = require("spec.helpers.fakeui")
        local createLine = fakeui.Frame.CreateLine
        fakeui.Frame.CreateLine = nil
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[7]:Click()
        w.runTimers(w.clock)
        w.runTimers(w.clock)
        fakeui.Frame.CreateLine = createLine
        assert.are.equal(0, window.rankChart.lines.used)
        assert.is_true(window.rankChart.textures.used >= 26)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("compares lure on and off, switches kinds, and picks characters", function()
        w.game.lure = 7
        w.catch(5000, 9)
        w.catch(5020, 12)
        w.game.lure = nil
        w.catch(5040, 10)
        w.runTimers(5060)
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[8]:Click()
        assert.are.equal("Compare: lure on vs off", window.kindButton:GetText())
        assert.is_false(window.pickA:IsShown())
        assert.are.equal("With lure", window.compareList.headers[2]:GetText())
        assert.are.equal("No lure", window.compareList.headers[3]:GetText())
        local rows = texts(window.compareList)
        assert.are.same({ "Casts", "2", "1", "", "" }, rows[1])
        assert.are.same({ "Success rate", "2/2", "1/1", "-", "too few casts" }, rows[2])
        assert.are.same({ "Median bite time", "10.5 s", "10.0 s", "+0.5 s" }, {
            rows[6][1],
            rows[6][2],
            rows[6][3],
            rows[6][4],
        })
        assert.is_true(window.scopeButton:IsShown())

        window.kindButton:Click()
        assert.are.equal("Compare: day vs night", window.kindButton:GetText())
        window.kindButton:Click()
        assert.are.equal("Compare: zone A vs B", window.kindButton:GetText())
        assert.are.equal("Compare needs two groups with casts.", window.compareHint:GetText())
        assert.are.equal(0, #window.compareList.box.drawn)

        local other = { name = "Alt", subzones = {}, sessions = {} }
        other.totals = w.ns.Totals.New()
        w.ns.Totals.Add(other.totals, { t = w.serverTime, map = 1412, out = "timeout" })
        _G.FishingMasteryDB.chars["Player-5827-00000001"] = other
        window.kindButton:Click()
        assert.are.equal("Compare: character A vs B", window.kindButton:GetText())
        assert.is_false(window.scopeButton:IsShown())
        assert.are.equal("A: Dingel", window.pickA:GetText())
        assert.are.equal("B: Alt", window.pickB:GetText())
        window.pickB:Click() -- only two characters: B stays the other one
        assert.are.equal("B: Alt", window.pickB:GetText())
        window.pickA:Click()
        assert.are.equal("A: Dingel", window.pickA:GetText())
        window.kindButton:Click()
        assert.are.equal("Compare: lure on vs off", window.kindButton:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("draws the calendar heatmap of fishing days with numbers in the tooltips", function()
        w.catch(5000, 9)
        w.catch(5020, 12)
        w.runTimers(5040)
        _G.SlashCmdList.FM("stats")
        local heatmap = stats().heatmap
        assert.are.equal(1, heatmap.drawn.fishing)
        assert.truthy(heatmap.title:GetText():find("last 53 weeks: 1", 1, true))
        local today = heatmap.drawn.cells[#heatmap.drawn.cells]
        assert.are.equal(4, today.level)
        local cell = heatmap.cells[(today.row - 1) * 53 + today.col]
        assert.is_true(cell:IsShown())
        assert.are.equal(1, cell.texture.color[4])
        cell:GetScript("OnEnter")(cell)
        assert.are.equal(os.date("!%Y-%m-%d", today.day * 86400), _G.GameTooltip.lines[1])
        assert.are.equal("2 casts, 2 catches", _G.GameTooltip.lines[2])
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
