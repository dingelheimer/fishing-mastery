local addon = require("spec.helpers.addon")

describe("Redact", function()
    local Redact

    before_each(function()
        Redact = addon.load({ "Redact.lua" }).Redact
    end)

    it("reduces a name to presence, length, and separator flags", function()
        assert.are.same(
            { present = true, length = 13, hasSpace = true, hasHyphen = false },
            Redact.Text("Synthia Brook")
        )
        assert.are.same(
            { present = true, length = 9, hasSpace = false, hasHyphen = true },
            Redact.Text("Name-Test")
        )
    end)

    it("reports empty and missing names", function()
        assert.are.same(
            { present = false, length = 0, hasSpace = false, hasHyphen = false },
            Redact.Text("")
        )
        assert.are.same({ present = false, type = "nil" }, Redact.Text(nil))
    end)

    it("reduces a GUID to type word and segment count", function()
        assert.are.same(
            { present = true, type = "Player", segments = 3 },
            Redact.Guid("Player-4321-0ABCDEF9")
        )
        assert.are.same(
            { present = true, type = "<other>", segments = 2 },
            Redact.Guid("12ab-Secretish")
        )
        assert.are.same({ present = false, type = "nil" }, Redact.Guid(nil))
    end)

    it("never returns any part of the input except a plain type word", function()
        local function containsInput(result, input)
            for _, value in pairs(result) do
                if type(value) == "string" and value ~= "Player" and input:find(value, 1, true) then
                    return true
                end
            end
            return false
        end
        assert.is_false(containsInput(Redact.Text("Synthia Brook"), "Synthia Brook"))
        assert.is_false(containsInput(Redact.Guid("Player-4321-0ABCDEF9"), "Player-4321-0ABCDEF9"))
    end)

    it("marks secret values without reading them", function()
        local secret = setmetatable({}, {
            __len = function()
                error("must not measure a secret")
            end,
        })
        local original = _G.issecretvalue
        _G.issecretvalue = function(value)
            return value == secret
        end
        local ok, err = pcall(function()
            Redact = addon.load({ "Redact.lua" }).Redact
            assert.are.same({ secret = true }, Redact.Text(secret))
            assert.are.same({ secret = true }, Redact.Guid(secret))
        end)
        _G.issecretvalue = original
        assert(ok, err)
    end)

    it("recognizes known GUID shapes only", function()
        assert.is_true(Redact.IsGuid("Player-4321-0ABCDEF9"))
        assert.is_true(Redact.IsGuid("GameObject-0-4321-0-12-180682-0000ABCDEF"))
        assert.is_false(Redact.IsGuid("Fishing-Bobber-Text"))
        assert.is_false(Redact.IsGuid("Player-1"))
        assert.is_false(Redact.IsGuid(12))
    end)

    it("keeps object IDs for objects and spell IDs for casts, nothing for players", function()
        assert.are.same(
            { present = true, type = "GameObject", segments = 7, id = 180682 },
            Redact.SourceGuid("GameObject-0-4321-0-12-180682-0000ABCDEF")
        )
        assert.are.same(
            { present = true, type = "Creature", segments = 7, id = 1234 },
            Redact.SourceGuid("Creature-0-4321-0-12-1234-0000ABCDEF")
        )
        assert.are.same(
            { present = true, type = "Cast", segments = 7, spellID = 7620, castID = "000CE1E4AF" },
            Redact.SourceGuid("Cast-3-4321-0-12-7620-000CE1E4AF")
        )
        assert.are.same(
            { present = true, type = "Player", segments = 3 },
            Redact.SourceGuid("Player-4321-0ABCDEF9")
        )
    end)

    it("replaces the own name, also with pattern characters", function()
        assert.are.equal("<player> and <player>", Redact.OwnName("Syn.th and Syn.th", "Syn.th"))
        assert.are.equal("Synxth", Redact.OwnName("Synxth", "Syn.th"))
        assert.are.equal("text", Redact.OwnName("text", nil))
        assert.are.equal(5, Redact.OwnName(5, "x"))
    end)

    it("reduces payload values", function()
        assert.are.equal("Player", Redact.Value("Player-4321-0ABCDEF9", "Me").type)
        assert.are.equal("<player> fishes", Redact.Value("Me fishes", "Me"))
    end)

    it("rounds positions to 0.1 percent", function()
        assert.are.equal(0.123, Redact.Position(0.123456))
        assert.are.equal(0.988, Redact.Position(0.987654))
        assert.is_nil(Redact.Position(nil))
    end)
end)
