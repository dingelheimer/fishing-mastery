local addon = require("spec.helpers.addon")

describe("Export", function()
    local ns = addon.load({ "Export.lua" })
    local Export = ns.Export

    local function store(entries)
        return {
            entries = entries,
            dropped = 3,
            cap = 20000,
            sessionId = "abc-01",
            probeVersion = "0.1.0",
        }
    end

    it("encodes plain values as compact JSON with sorted keys", function()
        assert.are.equal("null", Export.Encode(nil))
        assert.are.equal("true", Export.Encode(true))
        assert.are.equal("1.5", Export.Encode(1.5))
        assert.are.equal("16001", Export.Encode(16001))
        assert.are.equal("[1,2,3]", Export.Encode({ 1, 2, 3 }))
        assert.are.equal('{"a":1,"b":[true]}', Export.Encode({ b = { true }, a = 1 }))
        assert.are.equal("[]", Export.Encode({}))
        assert.are.equal('{"1":"x","n":1}', Export.Encode({ "x", n = 1 }))
        assert.are.equal('{"2":"y"}', Export.Encode({ [2] = "y" }))
        assert.are.equal('"<function>"', Export.Encode(print))
        assert.are.equal('"nan"', Export.Encode(0 / 0):gsub("-", ""))
    end)

    it("escapes quotes, control characters, and pipes", function()
        assert.are.equal('"a\\"b\\\\c\\nd\\te"', Export.Encode('a"b\\c\nd\te'))
        assert.are.equal('"\\u007ccff00ff00x\\u007cr"', Export.Encode("|cff00ff00x|r"))
        assert.are.equal('"\\u0001"', Export.Encode("\1"))
    end)

    it("writes one line per entry after a header", function()
        local pages = Export.Pages(store({
            { t = 1.25, step = "S0", q = "Q01", kind = "snapshot", data = { topic = "build" } },
            { t = 2, step = "S3", kind = "attempt", data = { outcome = "catch" } },
        }))
        assert.are.equal(1, #pages)
        local lines = {}
        for line in pages[1]:gmatch("[^\n]+") do
            lines[#lines + 1] = line
        end
        assert.are.equal(3, #lines)
        assert.are.equal(
            '{"cap":20000,"dropped":3,"entries":2,"format":"fmp-export-1","page":1,"pages":1,'
                .. '"session":"abc-01","version":"0.1.0"}',
            lines[1]
        )
        assert.are.equal('[1.25,"S0","Q01","snapshot",{"topic":"build"}]', lines[2])
        assert.are.equal('[2,"S3",null,"attempt",{"outcome":"catch"}]', lines[3])
    end)

    it("splits long logs into pages without losing or cutting entries", function()
        local entries = {}
        for i = 1, 50 do
            entries[i] =
                { t = i, step = "S3", kind = "event", data = { text = string.rep("x", 40) } }
        end
        local pages = Export.Pages(store(entries), 500)
        assert.is_true(#pages > 1)
        local count = 0
        for i, page in ipairs(pages) do
            local first = true
            for line in page:gmatch("[^\n]+") do
                if first then
                    assert.truthy(line:find('"page":' .. i .. ',"pages":' .. #pages, 1, true))
                    first = false
                else
                    count = count + 1
                    assert.truthy(line:match('^%[%d+,"S3",null,"event",{.*}%]$'))
                end
            end
            assert.is_true(#page <= 500 + 200) -- header line on top of the page budget
        end
        assert.are.equal(50, count)
    end)

    it("exports an empty log as a header page", function()
        local pages = Export.Pages(store({}))
        assert.are.equal(1, #pages)
        assert.truthy(pages[1]:find('"entries":0', 1, true))
    end)
end)
