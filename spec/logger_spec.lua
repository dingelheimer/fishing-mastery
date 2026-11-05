local addon = require("spec.helpers.addon")

describe("Logger", function()
    local ns, clock

    local function newLogger(store)
        return ns.Logger.New(store, {
            now = function()
                clock = clock + 1
                return clock
            end,
            sanitize = ns.Serializer.Sanitize,
        })
    end

    before_each(function()
        ns = addon.load({ "Serializer.lua", "Logger.lua" })
        clock = 0
    end)

    it("defaults to a cap of 20,000 entries", function()
        local store = {}
        newLogger(store)
        assert.are.equal(20000, store.cap)
        assert.are.equal(0, store.dropped)
    end)

    it("appends entries with t, step, q, kind, and sanitized data", function()
        local logger = newLogger({})
        logger:SetStep("S3")
        local entry = logger:Log("event", { name = "LOOT_READY", fn = print }, "Q09")
        assert.are.same({
            t = 1,
            step = "S3",
            q = "Q09",
            kind = "event",
            data = { name = "LOOT_READY", fn = "<function>" },
        }, entry)
        assert.are.equal(1, logger:Count())
    end)

    it("lets one entry override the current step", function()
        local logger = newLogger({})
        logger:SetStep("S5")
        assert.are.equal("S0", logger:Log("snapshot", nil, "Q01", "S0").step)
        assert.are.equal("S5", logger:Log("event").step)
    end)

    it("drops the oldest entries above the cap and counts them", function()
        local store = { cap = 3 }
        local logger = newLogger(store)
        for i = 1, 5 do
            logger:Log("n", i)
        end
        assert.are.equal(3, logger:Count())
        assert.are.equal(2, logger:Dropped())
        assert.are.equal(3, store.entries[1].data)
        assert.are.equal(5, store.entries[3].data)
    end)

    it("keeps existing entries and the drop counter from a saved store", function()
        local store = { entries = { { kind = "old" } }, dropped = 7, cap = 10 }
        local logger = newLogger(store)
        logger:Log("new")
        assert.are.equal(2, logger:Count())
        assert.are.equal(7, logger:Dropped())
    end)

    it("records session ID and probe version", function()
        local store = {}
        local logger = newLogger(store)
        local entry = logger:StartSession("abc", "0.1.0")
        assert.are.equal("abc", store.sessionId)
        assert.are.equal("0.1.0", store.probeVersion)
        assert.are.equal("session_start", entry.kind)
        assert.are.same({ sessionId = "abc", probeVersion = "0.1.0" }, entry.data)
    end)

    it("builds session IDs from time and a random number only", function()
        assert.are.equal("6728f000-00ff", ns.Logger.MakeSessionId(0x6728f000, 255))
    end)
end)
