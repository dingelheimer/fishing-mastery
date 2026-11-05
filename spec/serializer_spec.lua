local addon = require("spec.helpers.addon")

describe("Serializer", function()
    local Serializer

    before_each(function()
        Serializer = addon.load({ "Serializer.lua" }).Serializer
    end)

    it("copies nested tables, booleans, and numbers", function()
        local input = { a = { b = { c = 1 } }, flag = false, list = { 1, 2, 3 } }
        local out = Serializer.Sanitize(input)
        assert.are.same(input, out)
        assert.are_not.equal(input.a, out.a)
    end)

    it("keeps nil and its position in packed arguments", function()
        local out = Serializer.Pack("x", nil, true)
        assert.are.equal(3, out.n)
        assert.are.equal("x", out[1])
        assert.is_nil(out[2])
        assert.is_true(out[3])
        assert.is_nil(Serializer.Sanitize(nil))
    end)

    it("cuts long strings and marks the original length", function()
        local out = Serializer.Sanitize(string.rep("a", 12), { maxString = 5 })
        assert.are.equal("aaaaa<cut:12>", out)
    end)

    it("stops at the depth cap", function()
        local out = Serializer.Sanitize({ { { "deep" } } }, { maxDepth = 2 })
        assert.are.same({ { "<depth>" } }, out)
    end)

    it("counts keys beyond the key cap", function()
        local out = Serializer.Sanitize({ 1, 2, 3, 4 }, { maxKeys = 2 })
        assert.are.equal(2, out.__cut)
    end)

    it("marks cycles, functions, and non-finite numbers", function()
        local cyclic = {}
        cyclic.self = cyclic
        assert.are.same({ self = "<cycle>" }, Serializer.Sanitize(cyclic))
        assert.are.equal("<function>", Serializer.Sanitize(print))
        assert.are.equal("<nan>", Serializer.Sanitize(0 / 0))
        assert.are.equal("<inf>", Serializer.Sanitize(math.huge))
    end)

    it("turns unusual keys into unique markers", function()
        local out = Serializer.Sanitize({ [true] = 1, [{}] = 2 })
        assert.are.equal(1, out["<true>"])
        local found = false
        for key in pairs(out) do
            if type(key) == "string" and key:match("^<table>#%d+$") then
                found = true
            end
        end
        assert.is_true(found)
    end)

    describe("with secret values", function()
        local secret = "SECRET-PAYLOAD"

        before_each(function()
            _G.issecretvalue = function(value)
                return value == secret
            end
            Serializer = addon.load({ "Serializer.lua" }).Serializer
        end)

        after_each(function()
            _G.issecretvalue = nil
        end)

        it("stores a marker instead of the value", function()
            local out = Serializer.Sanitize({ spell = 7620, name = secret, [secret] = 1 })
            assert.are.equal(7620, out.spell)
            assert.are.equal("<secret:string>", out.name)
            for key, value in pairs(out) do
                assert.are_not.equal(secret, key)
                assert.are_not.equal(secret, value)
            end
            assert.are.equal("<secret:string>", Serializer.Pack(secret)[1])
        end)
    end)
end)
