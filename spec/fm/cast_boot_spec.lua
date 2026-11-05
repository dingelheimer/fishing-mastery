-- Boot tests from cast to saved data: records, sessions, skill-ups, packing at logout, totals,
-- and the load check, through every TOC file against the fake UI.
local fmboot = require("spec.helpers.fmboot")

local GUID = fmboot.GUID

describe("FishingMastery cast history boot", function()
    local w

    before_each(function()
        w = fmboot.new()
    end)

    after_each(function()
        w.cleanup()
    end)

    it("stores a cast record with context and loot from cast to SavedVariables", function()
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        _G.SlashCmdList.FM("status")
        assert.truthy(w.output():find("No open fishing session", 1, true))

        w.game.lure, w.game.modifier = 263, 25
        w.catch(5000, 10.1)
        local char = _G.FishingMasteryDB.chars[GUID]
        assert.are.equal(1, #char.casts)
        local cast = char.casts[1]
        assert.are.same({
            t = 1793836860,
            map = 1411,
            sub = 1,
            rank = 11,
            mod = 25,
            lure = 263,
            out = "catch",
            bite = 101,
            auto = false,
            loot = { { id = 6303, qty = 1, q = 1 } },
            srcType = "GameObject",
            srcId = 35591,
        }, cast)
        assert.are.same({ "Darkspear Strand" }, char.subzones)

        w.game.lure, w.game.modifier = nil, 0
        w.at(5020, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(5030, "UI_INFO_MESSAGE", 418, "Your fish got away!")
        w.at(5030.2, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.runTimers(5032)
        assert.are.equal(2, #char.casts)
        assert.are.equal("getaway", char.casts[2].out)
        assert.is_nil(char.casts[2].lure)
        assert.is_nil(char.casts[2].loot)

        w.printed = {}
        _G.SlashCmdList.FM("status")
        local text = w.output()
        assert.truthy(text:find("Session: 0 min, 2 casts, 1 catches", 1, true))
        assert.truthy(text:find("Getaways 1, early clicks 0", 1, true))
        assert.truthy(text:find("Fishing skill 11 -> 11 (+0)", 1, true))
        assert.truthy(text:find("Last: fish got away", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("counts a skill-up and keeps the session across /reload", function()
        w.boot(nil, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
        w.catch(5000, 8)
        -- The skill-up fires between the stop and the loot, as on live.
        w.at(5040, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(5050, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.game.rank = 12
        w.at(5050.05, "SKILL_LINES_CHANGED")
        w.at(5050.1, "LOOT_READY", true)
        w.at(5050.5, "LOOT_CLOSED")
        local char = _G.FishingMasteryDB.chars[GUID]
        local session = char.sessions[1]
        assert.are.equal(11, session.skillStart)
        assert.are.equal(12, session.skill)
        assert.are.equal(11, char.casts[2].rank)

        w.fire("PLAYER_LOGOUT")
        assert.are.equal("logout", session.endReason)
        -- Logout packs the open day into a chunk.
        assert.are.same({}, char.casts)
        assert.are.equal(1, #char.days)
        local savedTime = w.serverTime
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
        w.serverTime = savedTime + 30
        w.fire("PLAYER_ENTERING_WORLD", false, true)
        char = _G.FishingMasteryDB.chars[GUID]
        assert.is_nil(char.sessions[1].ended)
        w.catch(5000, 9)
        assert.are.equal(1, #char.sessions)
        assert.are.equal(3, char.sessions[1].casts)

        w.printed = {}
        _G.SlashCmdList.FM("status")
        assert.truthy(w.output():find("Fishing skill 11 -> 12 (+1)", 1, true))
        assert.truthy(w.output():find("Last: catch, bite time 9.0 s", 1, true))

        -- Totals were counted live; /fm rebuild counts the chunk and the open cast again.
        local live = w.ns.Db.DeepCopy(char.totals)
        w.printed = {}
        _G.SlashCmdList.FM("rebuild")
        assert.truthy(w.output():find("Totals rebuilt from 3 casts (3 catches) on 1 days", 1, true))
        assert.are.same(live, char.totals)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("sets a damaged chunk aside, reports it once, and loads the rest", function()
        local saved = {
            schemaVersion = 1,
            chars = {
                [GUID] = { days = { "20761|100,1,157,6303,1,1,1411", "20762|oops", "20763|5,2" } },
            },
        }
        w.boot(saved, nil)
        local char = _G.FishingMasteryDB.chars[GUID]
        assert.are.same({ "20761|100,1,157,6303,1,1,1411", "20763|5,2" }, char.days)
        assert.are.equal("20762|oops", char.quarantine[1].chunk)
        assert.truthy(w.output():find("1 damaged history chunk(s) were set aside", 1, true))
        w.boot(_G.FishingMasteryDB, nil)
        assert.is_nil(w.output():find("damaged", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("checks a large history in steps after login and reports damage at the end", function()
        local char = { casts = require("spec.helpers.synthetic").casts(20000), days = {} }
        w.boot({ schemaVersion = 1, chars = { [GUID] = char } }, nil)
        w.fire("PLAYER_LOGOUT")
        char = _G.FishingMasteryDB.chars[GUID]
        local good = #char.days
        assert.is_true(good > 50)
        char.days[good] = "20762|oops"

        w.boot(_G.FishingMasteryDB, nil)
        -- Only the first step runs at login; casts are tracked while the check goes on.
        assert.is_nil(w.output():find("damaged", 1, true))
        assert.are.same({}, char.quarantine)
        w.catch(5000, 8)
        local frames = 0
        while not w.output():find("damaged", 1, true) do
            w.runTimers(w.clock)
            frames = frames + 1
            assert.is_true(frames < 100)
        end
        assert.are.equal(math.ceil(good / 10) - 1, frames)
        assert.are.equal("20762|oops", char.quarantine[1].chunk)
        assert.are.equal(good - 1, #char.days)
        assert.are.equal(1, #char.casts)
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
