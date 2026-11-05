-- HUD boot tests through every TOC file: shown on the first cast, hidden at the idle end,
-- values after a catch, the lure timer, /fm hud commands, /reload, tooltip, and item loading.
local fmboot = require("spec.helpers.fmboot")

describe("FishingMastery HUD boot", function()
    local w

    before_each(function()
        w = fmboot.new()
    end)

    after_each(function()
        w.cleanup()
    end)

    local function hud()
        return w.ns.hud
    end

    local function text(name)
        return hud().lines[name]:GetText()
    end

    local function hudTimers()
        local n = 0
        for _, timer in ipairs(w.timers) do
            if timer.at - w.clock <= 1.01 then
                n = n + 1
            end
        end
        return n
    end

    local function login()
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
    end

    it("shows on the first cast with the session values and hides at the idle end", function()
        login()
        _G.C_Item.GetItemIconByID = function()
            return 133910
        end
        assert.is_nil(hud().frame) -- nothing is built before the first cast
        w.catch(5000, 10.1)
        local frame = hud().frame
        assert.is_true(frame:IsShown())
        assert.are.equal("0 min active, 1 casts, 1 catches", text("session"))
        assert.are.equal("Success 1/1, -", text("rates"))
        assert.are.same(w.ns.Hud.GREY, hud().lines.rates.color)
        assert.are.equal("Fishing 11 (+0)", text("skill"))
        assert.are.equal("No lure", text("lure"))
        assert.are.equal("Raw Slitherskin Mackerel, bite 10.1 s", text("last"))
        assert.are.equal(133910, hud().icon.texture)
        assert.is_true(hud().icon:IsShown())
        assert.are.equal("TOP", (frame:GetPoint(1)))

        -- A getaway 40 s later: the numbers follow.
        w.at(5050, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(5060, "UI_INFO_MESSAGE", 418, "Your fish got away!")
        w.at(5060.2, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.runTimers(5062)
        assert.are.equal("1 min active, 2 casts, 1 catches", text("session"))
        assert.are.equal("Success 1/2, -", text("rates"))
        assert.are.equal(0, hudTimers()) -- no per-second updates without a lure

        -- 15 minutes without a cast end the session; the HUD hides.
        w.runTimers(5050 + w.ns.Session.IDLE - 60)
        assert.is_true(frame:IsShown())
        w.runTimers(5050 + w.ns.Session.IDLE + 5)
        assert.is_false(frame:IsShown())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("updates once per second only while a lure is shown", function()
        login()
        w.game.lure, w.game.modifier = 263, 25
        w.catch(5000, 8)
        assert.are.equal("Lure: 10 min left", text("lure"))
        assert.are.equal("Fishing 11 (+0), effective 36", text("skill"))
        w.runTimers(5009.5) -- the attempt's grace timer and the first tick
        assert.are.equal(1, hudTimers())
        w.runTimers(5010.6)
        assert.are.equal(1, hudTimers()) -- one tick at a time
        w.game.lure, w.game.modifier = nil, 0
        w.runTimers(5011.7)
        assert.are.equal("No lure", text("lure"))
        assert.are.equal(0, hudTimers())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("handles /fm hud show, hide, lock, unlock, scale, style, and reset", function()
        login()
        local settings = _G.FishingMasteryDB.settings.hud
        assert.are.same({ enabled = true, locked = false, scale = 1, style = "full" }, settings)

        -- show without a session: shown with zeros so it can be placed.
        _G.SlashCmdList.FM("hud show")
        local frame = hud().frame
        assert.is_true(frame:IsShown())
        assert.are.equal("0 min active, 0 casts, 0 catches", text("session"))
        assert.are.equal("No catch yet", text("last"))

        -- Drag when unlocked, not when locked; the position is saved per character.
        frame:GetScript("OnDragStart")(frame)
        assert.is_true(frame.moving)
        frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 40, -50)
        frame.points = { frame.points[#frame.points] }
        frame:GetScript("OnDragStop")(frame)
        assert.are.same(
            { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 40, y = -50 },
            _G.FishingMasteryCharDB.ui.hud
        )
        _G.SlashCmdList.FM("hud lock")
        assert.is_true(settings.locked)
        frame.moving = false
        frame:GetScript("OnDragStart")(frame)
        assert.is_false(frame.moving)
        _G.SlashCmdList.FM("hud unlock")
        assert.is_false(settings.locked)

        _G.SlashCmdList.FM("hud scale 1.25")
        assert.are.equal(1.25, frame:GetScale())
        w.printed = {}
        _G.SlashCmdList.FM("hud scale 7")
        assert.truthy(w.output():find("Usage: /fm hud", 1, true))
        assert.are.equal(1.25, settings.scale)

        _G.SlashCmdList.FM("hud style text")
        assert.are.equal("text", settings.style)
        assert.truthy(text("session"):find("0/0, -, -, Fishing 11 (+0), No lure", 1, true))
        assert.is_false(hud().lines.rates:IsShown())
        _G.SlashCmdList.FM("hud style FULL")
        assert.is_true(hud().lines.rates:IsShown())

        _G.SlashCmdList.FM("hud reset")
        assert.is_nil(_G.FishingMasteryCharDB.ui.hud)
        assert.are.equal(1, settings.scale)
        assert.are.equal("TOP", (frame:GetPoint(1)))

        _G.SlashCmdList.FM("hud hide")
        assert.is_false(frame:IsShown())
        w.catch(5000, 9)
        assert.is_false(frame:IsShown()) -- switched off: no HUD while fishing
        w.printed = {}
        _G.SlashCmdList.FM("hud")
        assert.truthy(w.output():find("Usage: /fm hud", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("keeps its position and the session across /reload", function()
        login()
        w.catch(5000, 9)
        _G.FishingMasteryCharDB.ui.hud = { point = "LEFT", relativePoint = "LEFT", x = 20, y = 5 }
        w.fire("PLAYER_LOGOUT")
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
        w.fire("PLAYER_ENTERING_WORLD", false, true)
        local frame = hud().frame
        assert.is_true(frame:IsShown())
        assert.are.same({ "LEFT", _G.UIParent, "LEFT", 20, 5 }, frame.points[1])
        assert.are.equal("Raw Slitherskin Mackerel, bite 9.0 s", text("last"))
    end)

    it("shows the rate ranges in the tooltip", function()
        login()
        for i = 0, 11 do
            w.catch(5000 + i * 20, 9)
        end
        local frame = hud().frame
        frame:GetScript("OnEnter")(frame)
        local tip = _G.GameTooltip
        assert.is_true(tip.shown)
        assert.are.equal("Fishing Mastery", tip.lines[1])
        assert.truthy(
            tip.lines[2]:find("^Success rate 100 %% %(95 %% range 76%-100 %%%), 12 of 12")
        )
        assert.truthy(tip.lines[3]:find("^Catches per hour"))
        assert.truthy(tip.lines[4]:find("^Grey"))
        frame:GetScript("OnLeave")(frame)
        assert.is_false(tip.shown)
    end)

    it("fills in the item name once its data has loaded", function()
        login()
        local loaded = false
        local requested = {}
        _G.C_Item.GetItemInfo = function()
            if loaded then
                return "Raw Slitherskin Mackerel", "link", 1
            end
            return nil
        end
        _G.C_Item.RequestLoadItemDataByID = function(id)
            requested[#requested + 1] = id
        end
        w.catch(5000, 9)
        assert.are.equal("Item 6303, bite 9.0 s", text("last"))
        assert.are.same({ 6303 }, requested) -- the loot window gave the quality; the HUD asks once
        w.catch(5020, 9)
        assert.are.same({ 6303 }, requested)
        loaded = true
        w.fire("ITEM_DATA_LOAD_RESULT", 6303, true)
        assert.are.equal("Raw Slitherskin Mackerel, bite 9.0 s", text("last"))
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
