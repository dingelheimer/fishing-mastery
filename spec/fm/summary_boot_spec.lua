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

    -- The shown texts of the summary card (Story 10.5), color codes removed, joined by " / ".
    local function card()
        local text = table.concat(summary().pane:Texts(), " / ")
        return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
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
        local text = card()
        -- The card: title, the water and active time, skill, the three numbers, pairs, caught.
        assert.truthy(
            text:find("^Fishing session summary / zone 1411 / 1 min / Fishing 11 %-> 11 / ")
        )
        assert.truthy(text:find("/ 2 /  / catches / 2/3 /  / success / - /  / per hour /", 1, true))
        assert.truthy(text:find("/ Casts / 3 (0 min) / Got away / 1 /", 1, true))
        assert.truthy(text:find("/ Vendor value / 2c (", 1, true))
        assert.truthy(
            text:find(
                "/ Caught / Count /  / |T133910:14:14|t Raw Slitherskin Mackerel / 2 / new",
                1,
                true
            )
        )
        assert.is_nil(text:find("Above your average", 1, true)) -- no clear difference
        for _, fs in ipairs(summary().pane.cells) do
            if fs:GetText() == "2/3" then
                assert.are.same(w.ns.Style.GREY, fs.color) -- few casts: grey
            end
        end
        assert.is_true(summary().frame.lookBacking ~= nil) -- the HUD background setting applies
        assert.are.equal(0, #w.printed)

        -- The card's text frame ends above the Close button, takes no mouse, and lies below it
        -- (owner check: /fstack showed the 2000 px text frame on top of the button).
        local pane, close = summary().pane, summary().closeButton
        assert.are.equal(pane:Height(), pane.frame.height)
        assert.is_false(pane.frame.mouse)
        assert.is_true(close:GetFrameLevel() > frame:GetFrameLevel())
        local _, _, _, _, bottom = close:GetPoint()
        assert.is_true(frame.height - pane:Height() - 12 > bottom + 22) -- no overlap
        -- Not top-level (it would raise itself over its button), and the button follows the
        -- window's level on every show.
        assert.is_falsy(frame.toplevel)
        frame:SetFrameLevel(20)
        _G.SlashCmdList.FM("summary")
        assert.is_true(close:GetFrameLevel() > 20)
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
        assert.truthy(card():find("^Fishing session so far / "))
        assert.truthy(card():find("/ Casts / 3 (", 1, true))
        w.runTimers(5040 + w.ns.Session.IDLE + 5)
        summary().frame:Hide()
        _G.SlashCmdList.FM("summary")
        assert.is_true(summary().frame:IsShown())
        assert.truthy(card():find("^Fishing session summary / "))
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
        local text = card()
        assert.truthy(text:find("t Item 6303 / 2 /", 1, true)) -- the icon is known from the loot
        assert.truthy(text:find("(prices loading)", 1, true))
        loaded = true
        w.fire("ITEM_DATA_LOAD_RESULT", 6303, true)
        text = card()
        assert.truthy(text:find("Raw Slitherskin Mackerel / 2 /", 1, true))
        assert.is_nil(text:find("prices loading", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
