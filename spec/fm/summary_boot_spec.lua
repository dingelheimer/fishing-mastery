-- Session summary boot tests through every TOC file: the window at the idle end, the chat
-- block setting, /fm summary for the current and last session, and item data loading later.
local fmboot = require("spec.helpers.fmboot")

describe("FishingMastery session summary boot", function()
    local w

    before_each(function()
        w = fmboot.new()
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        _G.C_Item.GetItemInfo = function()
            return "Raw Slitherskin Mackerel",
                "link",
                1,
                5,
                0,
                "Trade Goods",
                "Meat",
                20,
                "",
                133910,
                1
        end
        _G.C_Item.GetItemIconByID = function()
            return 133910
        end
    end)

    after_each(function()
        w.cleanup()
    end)

    local function summary()
        return w.ns.summary
    end

    local function session()
        w.catch(5000, 9)
        w.catch(5020, 12)
        w.at(5040, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(5050, "UI_INFO_MESSAGE", 418, "Your fish got away!")
        w.at(5050.2, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.runTimers(5052)
    end

    it("opens the summary window when the session ends after 15 minutes", function()
        session()
        assert.is_nil(summary().frame)
        w.runTimers(5040 + w.ns.Session.IDLE - 30)
        assert.is_nil(summary().frame) -- not yet
        w.runTimers(5040 + w.ns.Session.IDLE + 5)
        local frame = summary().frame
        assert.is_true(frame:IsShown())
        assert.is_false(w.ns.hud.frame:IsShown()) -- the same end hides the HUD
        assert.are.equal("Fishing session summary", summary().title:GetText())
        local body = summary().body:GetText()
        assert.truthy(body:find("1 min active of 0 min", 1, true))
        assert.truthy(body:find("3 casts, 2 catches", 1, true))
        assert.truthy(body:find("Success: 2 of 3 fair casts", 1, true))
        assert.truthy(body:find("Failures: fish got away 1", 1, true))
        assert.truthy(body:find("Fishing skill 11 -> 11 (+0)", 1, true))
        assert.truthy(body:find("Best fish: |T133910:14:14|t Raw Slitherskin Mackerel x2", 1, true))
        assert.truthy(
            body:find("New for this character: |T133910:14:14|t Raw Slitherskin", 1, true)
        )
        assert.truthy(body:find("Vendor value 2c (", 1, true))
        assert.are.equal(0, #w.printed)

        summary().closeButton:Click()
        assert.is_false(frame:IsShown())
        -- The window position is saved per character.
        frame:SetPoint("TOP", _G.UIParent, "TOP", 0, -80)
        frame.points = { frame.points[#frame.points] }
        frame:GetScript("OnDragStop")(frame)
        assert.are.equal(-80, _G.FishingMasteryCharDB.ui.summary.y)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("prints a chat block instead when set to chat, and shows nothing at logout", function()
        _G.SlashCmdList.FM("summary chat")
        assert.are.equal("chat", _G.FishingMasteryDB.settings.summary.style)
        assert.truthy(w.output():find("printed in your chat frame", 1, true))
        session()
        w.printed = {}
        w.runTimers(5040 + w.ns.Session.IDLE + 5)
        local text = w.output()
        assert.truthy(text:find("Fishing session summary", 1, true))
        assert.truthy(text:find("3 casts, 2 catches", 1, true))
        assert.is_nil(summary().frame)

        -- A logout ends the next session without a summary.
        w.catch(7000, 9)
        w.printed = {}
        w.fire("PLAYER_LOGOUT")
        assert.are.equal("", w.output())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("shows the current or last session with /fm summary", function()
        _G.SlashCmdList.FM("summary")
        assert.truthy(w.output():find("No fishing session yet.", 1, true))
        session()
        _G.SlashCmdList.FM("summary")
        assert.are.equal("Fishing session so far", summary().title:GetText())
        assert.truthy(summary().body:GetText():find("3 casts, 2 catches", 1, true))
        w.runTimers(5040 + w.ns.Session.IDLE + 5)
        summary().frame:Hide()
        _G.SlashCmdList.FM("summary")
        assert.is_true(summary().frame:IsShown())
        assert.are.equal("Fishing session summary", summary().title:GetText())
        w.printed = {}
        _G.SlashCmdList.FM("summary popup")
        assert.truthy(w.output():find("Usage: /fm summary", 1, true))
        assert.are.equal("window", _G.FishingMasteryDB.settings.summary.style)
    end)

    it("fills in item names that load after the window opened", function()
        local loaded = false
        _G.C_Item.GetItemInfo = function()
            if loaded then
                return "Raw Slitherskin Mackerel",
                    "link",
                    1,
                    5,
                    0,
                    "Trade Goods",
                    "Meat",
                    20,
                    "",
                    133910,
                    1
            end
        end
        _G.C_Item.RequestLoadItemDataByID = function() end
        session()
        _G.SlashCmdList.FM("summary")
        local body = summary().body:GetText()
        assert.truthy(body:find("Item 6303 x2", 1, true))
        assert.truthy(body:find("some prices are still loading", 1, true))
        loaded = true
        w.fire("ITEM_DATA_LOAD_RESULT", 6303, true)
        body = summary().body:GetText()
        assert.truthy(body:find("Raw Slitherskin Mackerel x2", 1, true))
        assert.is_nil(body:find("still loading", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
