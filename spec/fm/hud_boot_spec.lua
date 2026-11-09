-- HUD boot tests through every TOC file (the card of Draft 5, Story 9.8): shown on the first
-- cast, hidden at the idle end, the numbers after a catch, the lure row with its timer, /fm hud
-- commands and the compact layout, /reload, the Draft 6 tooltip, item loading, and the water
-- (risk tag, risk line, fish icons).
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

    local function card()
        return hud().card
    end

    -- Text of a font string without color escapes.
    local function plain(fs)
        return (fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
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

    it(
        "shows the card on the first cast with the session values and hides at the idle end",
        function()
            login()
            _G.C_Item.GetItemIconByID = function()
                return 133910
            end
            assert.is_nil(hud().frame) -- nothing is built before the first cast
            w.catch(5000, 10.1)
            local frame, c = hud().frame, card()
            assert.is_true(frame:IsShown())
            assert.is_true(c.card:IsShown())
            assert.is_false(c.compact:IsShown())
            assert.are.equal("1", c.numbers[1].value:GetText())
            assert.are.equal("1/1", c.numbers[2].value:GetText())
            assert.are.same(w.ns.Style.GREY, c.numbers[2].value.color) -- few casts: grey
            assert.are.equal("-", c.numbers[3].value:GetText())
            assert.are.equal("Fishing 11 / 75", plain(c.bar.text))
            assert.is_false(c.mark:IsShown()) -- no modifier: no mark
            assert.are.equal("Raw Slitherskin Mackerel", c.lastText:GetText())
            assert.are.equal("10.1 s", c.lastBite:GetText())
            assert.are.equal(133910, c.lastIcon.texture)
            assert.are.equal("TOP", (frame:GetPoint(1)))
            assert.are.equal(c.card.height, frame.height) -- the frame takes the card's size

            -- A getaway 40 s later: the numbers follow.
            w.at(5050, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
            w.at(5060, "UI_INFO_MESSAGE", 418, "Your fish got away!")
            w.at(5060.2, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
            w.runTimers(5062)
            assert.are.equal("1/2", c.numbers[2].value:GetText())
            assert.are.equal(0, hudTimers()) -- no per-second updates without a lure

            -- 15 minutes without a cast end the session; the HUD hides.
            w.runTimers(5050 + w.ns.Session.IDLE - 60)
            assert.is_true(frame:IsShown())
            w.runTimers(5050 + w.ns.Session.IDLE + 5)
            assert.is_false(frame:IsShown())
            assert.are.equal(0, w.ns.Guard.errors)
        end
    )

    it("shows the lure row with a timer and updates once per second only then", function()
        login()
        w.game.lure, w.game.modifier = 263, 25
        w.catch(5000, 8)
        local c = card()
        assert.truthy(plain(c.lureText):find("^Lure"))
        assert.truthy(c.lureTimer:GetText():find("^%d+:%d%d$"))
        assert.is_true(c.mark:IsShown()) -- effective 36 of 75
        w.runTimers(5009.5) -- the attempt's grace timer and the first tick
        assert.are.equal(1, hudTimers())
        w.runTimers(5010.6)
        assert.are.equal(1, hudTimers()) -- one tick at a time
        w.game.lure, w.game.modifier = nil, 0
        w.runTimers(5011.7)
        assert.are.equal("", c.lureTimer:GetText())
        assert.is_false(c.mark:IsShown())
        assert.are.equal(0, hudTimers())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("handles /fm hud show, hide, lock, unlock, scale, layout, and reset", function()
        login()
        local settings = _G.FishingMasteryDB.settings.hud
        assert.are.same({
            enabled = true,
            locked = false,
            scale = 1,
            layout = "card",
            opacity = 1,
            zoneLine = true,
        }, settings)

        -- show without a session: shown with zeros so it can be placed.
        _G.SlashCmdList.FM("hud show")
        local frame = hud().frame
        assert.is_true(frame:IsShown())
        assert.are.equal("0", card().numbers[1].value:GetText())
        assert.is_false(card().lastText:IsShown()) -- no catch yet

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

        _G.SlashCmdList.FM("hud layout compact")
        assert.are.equal("compact", settings.layout)
        assert.is_true(card().compact:IsShown())
        assert.is_false(card().card:IsShown())
        assert.truthy(plain(card().line):find("0 catches", 1, true))
        assert.truthy(plain(card().line):find("Fishing 11", 1, true))
        assert.are.equal(card().compact.width, frame.width)
        _G.SlashCmdList.FM("hud layout CARD")
        assert.is_true(card().card:IsShown())

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
        assert.are.equal("Raw Slitherskin Mackerel", card().lastText:GetText())
    end)

    it("shows the session, getaways, and the Shift line in the tooltip", function()
        login()
        for i = 0, 11 do
            w.catch(5000 + i * 20, 9)
        end
        local frame = hud().frame
        frame:GetScript("OnEnter")(frame)
        local tip = _G.GameTooltip
        assert.is_true(tip.shown)
        assert.truthy(tip.lines[2]:find("^This session, %d+ min$"))
        assert.are.equal("Catches = 12 of 12 casts", tip.lines[3])
        assert.truthy(tip.lines[4]:find("^Success rate = 100 %% |cff8c8c8c%(76 %- 100%)|r$"))
        assert.are.equal("Hold Shift for how this is counted", tip.lines[#tip.lines])
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
        assert.are.equal("Item 6303", card().lastText:GetText())
        -- The last catch and the water's other fish (Durotar: 6356), each asked for once.
        assert.are.same({ 6303, 6356 }, requested)
        w.catch(5020, 9)
        assert.are.same({ 6303, 6356 }, requested)
        loaded = true
        w.fire("ITEM_DATA_LOAD_RESULT", 6303, true)
        assert.are.equal("Raw Slitherskin Mackerel", card().lastText:GetText())
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it(
        "shows the water's risk and fish, follows zone changes, and hides them by setting",
        function()
            login()
            _G.C_Map.GetMapInfo = function(map)
                return map == 1411 and { name = "Durotar" } or nil
            end
            -- Durotar (base -70, list 6303 and 6356) at skill 11: catch 86 %, none from skill 25.
            w.catch(5000, 9)
            local c, frame = card(), hud().frame
            assert.are.equal("14 % get away", c.tag:GetText())
            assert.are.same(w.ns.Style.ORANGE, c.tag.color)
            assert.is_true(c.riskLeft:IsShown())
            assert.are.equal("your skill 11", c.riskLeft:GetText())
            assert.are.equal("getaways stop at 25", plain(c.riskRight))
            assert.is_true(c.fishSlots[1]:IsShown() and c.fishSlots[2]:IsShown())
            assert.is_false(c.fishSlots[3]:IsShown())
            assert.are.equal("1 missing", c.missing:GetText())
            local caught = c.fishSlots[1].data.caught and c.fishSlots[1] or c.fishSlots[2]
            local dark = caught == c.fishSlots[1] and c.fishSlots[2] or c.fishSlots[1]
            assert.are.same({ 1, 1, 1 }, caught.texture.vertex)
            assert.is_true(dark.texture.vertex[1] < 1)
            dark:GetScript("OnEnter")(dark)
            assert.are.equal("not caught here yet", _G.GameTooltip.lines[2])
            frame:GetScript("OnEnter")(frame)
            local tip = table.concat(_G.GameTooltip.lines, " / ")
            assert.truthy(tip:find("Getaways here", 1, true))
            assert.truthy(tip:find("Classic, skill 11 = 14 %", 1, true))
            assert.truthy(tip:find("None from skill = 25", 1, true))

            w.game.map = 9999 -- a Forever zone without Classic data
            w.fire("ZONE_CHANGED_NEW_AREA")
            assert.are.equal("?", c.tag:GetText())
            assert.is_false(c.fishSlots[1]:IsShown())
            assert.is_false(c.missing:IsShown())

            _G.FishingMasteryDB.settings.hud.zoneLine = false
            hud():Refresh()
            assert.is_false(c.tagBack:IsShown())
            assert.are.equal("Fishing Mastery", c.zone:GetText())
            assert.is_false(c.riskLeft:IsShown())
            assert.are.equal(0, w.ns.Guard.errors)
        end
    )
    it("switches the layout and stops the session with its two buttons", function()
        login()
        w.catch(5000, 9)
        local c, frame = card(), hud().frame
        local settings = _G.FishingMasteryDB.settings.hud
        c.cardButtons.layout:Click()
        assert.are.equal("compact", settings.layout)
        assert.is_true(c.compact:IsShown())
        assert.are.equal(c.compact.width, frame.width)
        c.lineButtons.layout:Click()
        assert.are.equal("card", settings.layout)
        assert.is_true(c.card:IsShown())

        local stop = c.cardButtons.stop
        stop:GetScript("OnEnter")(stop)
        assert.are.same({ "Stop session", "Click: end the session now" }, _G.GameTooltip.lines)
        stop:GetScript("OnLeave")(stop)
        local ended = {}
        w.ns.castLog:OnSessionEnd(function(session)
            ended[#ended + 1] = session
        end)
        stop:Click()
        local sessions = w.ns.char.sessions
        assert.are.equal("stopped", sessions[#sessions].endReason)
        assert.are.equal(1, #ended) -- the summary and the HUD hear it like an idle end
        assert.is_nil(w.ns.castLog:Session())
        assert.is_false(frame:IsShown())
        stop:Click() -- nothing open: nothing happens
        assert.are.equal(1, #ended)

        w.catch(5100, 9) -- the next cast starts a new session
        assert.are.equal(2, #sessions)
        assert.is_true(frame:IsShown())
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
