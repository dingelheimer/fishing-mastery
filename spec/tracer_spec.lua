local addon = require("spec.helpers.addon")

describe("Tracer", function()
    local Tracer, ctx

    before_each(function()
        Tracer = addon.load({ "Serializer.lua", "Redact.lua", "Tracer.lua" }).Tracer
        ctx = {
            ownName = "Me",
            isOwnGuid = function(guid)
                return guid == "Player-1-OWN"
            end,
            messageName = function(_, text)
                return text == "Your fish got away!" and "ERR_FISH_ESCAPED" or nil
            end,
        }
    end)

    it("formats payloads with GUIDs reduced and the count kept", function()
        local data = Tracer.Format(
            ctx,
            "UNIT_SPELLCAST_CHANNEL_START",
            "player",
            "Cast-3-1-0-1-7620-0A",
            7620
        )
        assert.are.equal(3, data.n)
        assert.are.equal("player", data.args[1])
        assert.are.equal(7620, data.args[2].spellID)
        assert.are.equal(7620, data.args[3])
        assert.is_nil(data.secret)
    end)

    it("reduces the target name of UNIT_SPELLCAST_SENT", function()
        local data = Tracer.Format(
            ctx,
            "UNIT_SPELLCAST_SENT",
            "player",
            "Someone",
            "Cast-3-1-0-1-7620-0A",
            7620
        )
        assert.are.same(
            { present = true, length = 7, hasSpace = false, hasHyphen = false },
            data.args[2]
        )
    end)

    it("adds the message name to UI messages", function()
        local data = Tracer.Format(ctx, "UI_ERROR_MESSAGE", 51, "Your fish got away!")
        assert.are.equal("ERR_FISH_ESCAPED", data.msgName)
        assert.are.equal("Your fish got away!", data.args[2])
    end)

    it("keeps only the player's own chat text", function()
        local own = Tracer.Format(
            ctx,
            "CHAT_MSG_SKILL",
            "Me raised fishing",
            "",
            "",
            "",
            "",
            "",
            0,
            0,
            "",
            0,
            1,
            "Player-1-OWN"
        )
        assert.are.same(
            { name = "CHAT_MSG_SKILL", own = true, text = "<player> raised fishing" },
            own
        )
        local other = Tracer.Format(ctx, "CHAT_MSG_LOOT", "Bob loots", "Bob")
        assert.are.same({ name = "CHAT_MSG_LOOT", own = false }, other)
    end)

    it("flags secret positions", function()
        local secret = {}
        local original = _G.issecretvalue
        _G.issecretvalue = function(value)
            return value == secret
        end
        local ok, err = pcall(function()
            Tracer = addon.load({ "Serializer.lua", "Redact.lua", "Tracer.lua" }).Tracer
            local data = Tracer.Format(ctx, "UNIT_AURA", "player", secret)
            assert.are.same({ 2 }, data.secret)
            assert.are.equal(secret, data.args[2]) -- the logger's serializer marks it
        end)
        _G.issecretvalue = original
        assert(ok, err)
    end)

    it("throttles to one event per interval and counts suppressed ones", function()
        local throttle = Tracer.NewThrottle(1)
        assert.are.same({ true, 0 }, { throttle(10) })
        assert.is_false(throttle(10.5))
        assert.is_false(throttle(10.9))
        assert.are.same({ true, 2 }, { throttle(11) })
    end)

    it("traces only events that the login snapshot checks", function()
        local ns = addon.load({ "ApiList.lua" })
        local known = {}
        for _, event in ipairs(ns.ApiList.EVENTS) do
            known[event] = true
        end
        for _, spec in ipairs(Tracer.EVENTS) do
            assert(known[spec[1]], spec[1])
        end
    end)
end)
