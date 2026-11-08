-- Stats window boot tests through every TOC file: /fm stats opens the window, every tab draws
-- without Lua errors, the Overview matches /fm rebuild, Fish sorts and filters, the scope switch
-- merges characters, the position is saved, and the window waits for the count after login.
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")
local texts = statsui.texts

describe("FishingMastery stats window boot", function()
    local w, tabs

    before_each(function()
        w = fmboot.new()
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        tabs = statsui.stub(w)
    end)

    after_each(function()
        w.cleanup()
        statsui.cleanup()
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
        assert.are.same({ key = "n", descending = false }, window.sorts.fish)
        window.fish.headers[1]:Click()
        assert.are.same({ key = "name", descending = false }, window.sorts.fish)
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

    it("compares the selected zone with the Classic data, and places without data", function()
        fish()
        -- One catch in a Forever zone without Classic data.
        w.ns.Totals.Add(w.ns.char.totals, {
            t = w.serverTime,
            map = 9999,
            out = "catch",
            loot = { { id = 6303 } },
        })
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[3]:Click()
        -- The first row (Durotar) is selected: its list next to the 2 own catches.
        assert.are.equal("000001411", window.zoneKey)
        assert.truthy(window.zoneNote:GetText():find("^Durotar: Classic estimate", 1))
        local rows = texts(window.zoneDetail)
        assert.are.same(
            { "98 %", "", "2/2", "2" },
            { rows[1][2], rows[1][3], rows[1][4], rows[1][5] }
        )
        assert.are.same({ "2 %", "-", "0" }, { rows[2][2], rows[2][4], rows[2][5] })

        local other
        for _, row in ipairs(window.zones.box.drawn) do
            if row.data.map == 9999 then
                other = row
            end
        end
        other:GetScript("OnMouseUp")(other)
        assert.are.equal(other.data.key, window.zoneKey)
        assert.truthy(window.zoneNote:GetText():find("No reference data (new in Forever)", 1, true))
        rows = texts(window.zoneDetail)
        assert.are.equal(1, #rows)
        assert.are.same({ "-", "1/1", "1" }, { rows[1][2], rows[1][4], rows[1][5] })
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

        local main = w.ns.mainWindow
        main.frame:SetPoint("TOP", _G.UIParent, "TOP", 0, -50)
        main.frame.points = { main.frame.points[#main.frame.points] }
        main.handle:GetScript("OnDragStop")(main.handle)
        assert.are.equal(-50, _G.FishingMasteryCharDB.ui.main.y)
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
    it("draws the Failures charts, the bite histogram, and the sortable session list", function()
        fish()
        _G.GetGameMessageInfo = function(messageType)
            return ({ [418] = "ERR_FISH_ESCAPED", [419] = "ERR_FISH_NOT_HOOKED" })[messageType]
        end
        w.at(5060, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(5064.2, "UI_INFO_MESSAGE", 419, "No fish are hooked.")
        w.at(5064.3, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.runTimers(5066)
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[4]:Click()
        local rows = texts(window.failures)
        assert.are.same({ "catch", "2", "2/4", "2/3" }, rows[1])
        -- Skill chart in Durotar (base -70): skill 11 is band +80 above the base, with the model
        -- mark (bar + 3 range textures + mark), and the button to group by effective skill.
        local skill = window.skillChart
        assert.are.equal("Group: skill above water base", window.skillButton:GetText())
        assert.are.equal(1, #skill.drawn.bars)
        assert.are.equal("+80", skill.drawn.bars[1].label)
        assert.is_true(skill.textures.used >= 5)
        local hover = skill.hovers.list[1]
        hover:GetScript("OnEnter")(hover)
        local tip = table.concat(_G.GameTooltip.lines, " / ")
        assert.truthy(tip:find("water's base level: +80 to +84", 1, true))
        assert.truthy(tip:find("Classic model: 13 %", 1, true))
        window.skillButton:Click()
        assert.are.equal("Group: effective skill", window.skillButton:GetText())
        hover = skill.hovers.list[1]
        hover:GetScript("OnEnter")(hover)
        tip = table.concat(_G.GameTooltip.lines, " / ")
        assert.truthy(tip:find("Effective skill 10-14", 1, true))
        assert.are.equal(1, window.clickChart.drawn.total) -- the early click at 4.2 s

        window.frame.Tabs[5]:Click()
        assert.are.equal("Chart: All zones", window.biteButton:GetText())
        assert.truthy(window.biteText:GetText():find("(2 bites)", 1, true))
        assert.are.equal(30, #window.biteChart.drawn.bars)
        window.biteButton:Click()
        assert.are.equal("Chart: Durotar, no lure", window.biteButton:GetText())
        window.biteButton:Click() -- back to all zones (two groups)
        assert.are.equal("Chart: All zones", window.biteButton:GetText())

        window.frame.Tabs[6]:Click()
        rows = texts(window.sessions)
        assert.are.equal(1, #rows)
        assert.are.same({ "Durotar", "4", "2" }, { rows[1][3], rows[1][5], rows[1][6] })
        window.sessions.headers[5]:Click()
        assert.are.same({ key = "casts", descending = true }, window.sorts.sessions)
        window.sessions.headers[2]:Click()
        assert.are.same({ key = "name", descending = false }, window.sorts.sessions)
        assert.is_true(window.scopeButton:IsShown())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("shows a message instead of a chart when there is nothing to draw", function()
        _G.SlashCmdList.FM("stats")
        local window = stats()
        window.frame.Tabs[4]:Click()
        assert.is_nil(window.skillChart.drawn)
        assert.are.equal("No catches yet.", window.status:GetText())
        window.frame.Tabs[5]:Click()
        assert.is_false(window.biteButton:IsShown())
        window.frame.Tabs[6]:Click()
        assert.are.equal("No sessions yet.", window.status:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
