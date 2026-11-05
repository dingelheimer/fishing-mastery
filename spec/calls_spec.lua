local addon = require("spec.helpers.addon")

describe("Calls", function()
    local Calls

    before_each(function()
        Calls = addon.load({ "Serializer.lua", "Scan.lua", "Calls.lua" }).Calls
    end)

    it("reports a missing function", function()
        assert.are.same({ exists = false }, Calls.Call({}, "C_Missing.Fn"))
        assert.are.same({ exists = false }, Calls.Call({ NOT_FN = 1 }, "NOT_FN"))
    end)

    it("keeps nil positions and the value count", function()
        local env = {
            Fn = function(a)
                return a, nil, true
            end,
        }
        assert.are.same(
            { exists = true, ok = true, n = 3, values = { n = 3, "x", nil, true } },
            Calls.Call(env, "Fn", "x")
        )
    end)

    it("returns an error as a result", function()
        local result = Calls.Call({
            Fn = function()
                error("boom", 0)
            end,
        }, "Fn")
        assert.is_true(result.exists)
        assert.is_false(result.ok)
        assert.are.equal("boom", result.values[1])
    end)

    it("returns raw values from Invoke", function()
        local raw = { 1 }
        assert.are.same({ true, true, raw }, {
            Calls.Invoke({
                Fn = function()
                    return raw
                end,
            }, "Fn"),
        })
    end)
end)
