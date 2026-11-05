local addon = require("spec.helpers.addon")

describe("Guard", function()
    local Guard, records

    before_each(function()
        Guard = addon.load({ "Guard.lua" }).Guard
        records = {}
    end)

    local function collect(record)
        records[#records + 1] = record
    end

    it("passes arguments and returns results when nothing fails", function()
        local ok, a, b = Guard.Call("test", function(x, y)
            return x + 1, y
        end, 1, nil)
        assert.is_true(ok)
        assert.are.equal(2, a)
        assert.is_nil(b)
        assert.are.equal(0, Guard.errors)
    end)

    it("captures an error with where, message, and stack", function()
        Guard.SetSink(collect)
        local ok = Guard.Call("event:LOOT_READY", function()
            error("boom")
        end)
        assert.is_false(ok)
        assert.are.equal(1, Guard.errors)
        assert.are.equal(1, #records)
        assert.are.equal("event:LOOT_READY", records[1].where)
        assert.truthy(records[1].msg:find("boom", 1, true))
        assert.are.equal("table", type(records[1].stack))
        assert.truthy(#records[1].stack > 0)
        assert.truthy(#records[1].stack <= Guard.MAX_STACK_LINES)
    end)

    it("keeps errors from before the sink exists and flushes them", function()
        Guard.Call("early", error, "first")
        assert.are.equal(1, #Guard.pending)
        Guard.SetSink(collect)
        assert.are.equal(0, #Guard.pending)
        assert.are.equal("early", records[1].where)
    end)

    it("caps pending errors", function()
        for _ = 1, Guard.MAX_PENDING + 5 do
            Guard.Call("early", error, "x")
        end
        assert.are.equal(Guard.MAX_PENDING, #Guard.pending)
    end)

    it("survives a failing sink", function()
        Guard.SetSink(function()
            error("sink broken")
        end)
        local ok = Guard.Call("test", error, "boom")
        assert.is_false(ok)
        assert.are.equal(1, Guard.errors)
    end)

    it("wraps functions", function()
        Guard.SetSink(collect)
        local wrapped = Guard.Wrap("slash", function(message)
            error(message)
        end)
        assert.is_false((wrapped("bad")))
        assert.are.equal("slash", records[1].where)
    end)
end)
