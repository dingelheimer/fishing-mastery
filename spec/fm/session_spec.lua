local addon = require("spec.helpers.addon")

describe("FishingMastery sessions", function()
    local Session, char

    before_each(function()
        Session = addon.load({ "Session.lua" }, nil, "FishingMastery").Session
        char = { sessions = {} }
    end)

    local function cast(t, out, fields)
        local c = { t = t, out = out or "catch", map = 1411, rank = 11 }
        for key, value in pairs(fields or {}) do
            c[key] = value
        end
        return c
    end

    it("starts on the first cast and counts casts, catches, outcomes, and zones", function()
        assert.is_nil(Session.Current(char))
        Session.Add(char, cast(100))
        Session.Add(char, cast(130, "getaway"))
        Session.Add(char, cast(160, "catch", { map = 1454 }))
        Session.Add(char, cast(190, "timeout", { map = 1411 }))
        local s = Session.Current(char)
        assert.are.equal(100, s.start)
        assert.are.equal(190, s.last)
        assert.are.equal(4, s.casts)
        assert.are.equal(2, s.catches)
        assert.are.same({ catch = 2, getaway = 1, timeout = 1 }, s.counts)
        assert.are.same({ 1411, 1454 }, s.zones)
        assert.are.equal(1, #char.sessions)
    end)

    it("ends after 15 minutes without a cast and starts a new one", function()
        Session.Add(char, cast(100))
        assert.is_table(Session.Expire(char, 100 + Session.IDLE - 1))
        Session.Add(char, cast(100 + Session.IDLE + 10))
        assert.are.equal(2, #char.sessions)
        assert.are.equal(100, char.sessions[1].ended)
        assert.are.equal("idle", char.sessions[1].endReason)
        assert.is_nil(Session.Expire(char, 100 + 3 * Session.IDLE))
    end)

    it(
        "tracks the skill before and after, including a skill-up before the catch is saved",
        function()
            char.fishingRank = 11
            Session.Add(char, cast(100, "catch", { rank = 11 }))
            assert.is_true(Session.SkillChanged(char, 12, 120))
            Session.Add(char, cast(121, "catch", { rank = 11 }))
            assert.is_false(Session.SkillChanged(char, 12, 130))
            local s = Session.Current(char)
            assert.are.equal(11, s.skillStart)
            assert.are.equal(12, s.skill)
            assert.are.equal(1, Session.SkillUps(s))
        end
    )

    it("counts a skill-up on the first cast of a session", function()
        char.fishingRank = 11
        Session.SkillChanged(char, 12, 100) -- no session yet
        Session.Add(char, cast(101, "catch", { rank = 11 }))
        assert.are.equal(1, Session.SkillUps(Session.Current(char)))
    end)

    it("handles a missing rank", function()
        Session.Add(char, cast(100, "catch", { rank = false }))
        local s = Session.Current(char)
        s.skillStart, s.skill = nil, nil
        assert.are.equal(0, Session.SkillUps(s))
    end)

    it("ends at logout and reopens after a /reload", function()
        Session.Add(char, cast(100))
        Session.Logout(char, 200)
        assert.are.equal("logout", char.sessions[1].endReason)
        assert.is_nil(Session.Current(char))
        Session.Login(char, 210, true)
        assert.is_table(Session.Current(char))
        Session.Add(char, cast(220))
        assert.are.equal(1, #char.sessions)
        assert.are.equal(2, char.sessions[1].casts)
    end)

    it("does not reopen after a real logout or a long reload", function()
        Session.Add(char, cast(100))
        Session.Logout(char, 200)
        Session.Login(char, 210, false)
        assert.is_nil(Session.Current(char))
        Session.Login(char, 100 + Session.IDLE + 1, true)
        assert.is_nil(Session.Current(char))
    end)

    it("ends a session left open by a crash at its last cast", function()
        Session.Add(char, cast(100))
        Session.Login(char, 100 + Session.IDLE * 2, false)
        assert.are.equal(100, char.sessions[1].ended)
        assert.are.equal("idle", char.sessions[1].endReason)
        Session.Logout(char, 5000)
        assert.are.equal(100, char.sessions[1].ended)
    end)
end)
