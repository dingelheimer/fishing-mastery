local addon = require("spec.helpers.addon")

describe("Scan", function()
    local Scan

    before_each(function()
        Scan = addon.load({ "Scan.lua" }).Scan
    end)

    local function forbidden()
        error("the scan must never call a function")
    end

    it("resolves dotted paths without calling anything", function()
        local env = { C_Spell = { GetSpellInfo = forbidden }, NUMBER = 3 }
        assert.are.equal(forbidden, Scan.Resolve(env, "C_Spell.GetSpellInfo"))
        assert.are.equal(env.C_Spell, Scan.Resolve(env, "C_Spell"))
        assert.is_nil(Scan.Resolve(env, "C_Missing.Fn"))
        assert.is_nil(Scan.Resolve(env, "NUMBER.Field"))
    end)

    it("survives a namespace whose index raises an error", function()
        local env = {
            C_Broken = setmetatable({}, { __index = forbidden }),
        }
        assert.is_nil(Scan.Resolve(env, "C_Broken.Fn"))
    end)

    it("reports function, table, nil, and other types per name", function()
        local env = {
            IsFishingLoot = forbidden,
            C_Map = { GetBestMapForUnit = forbidden },
            WOW_PROJECT_ID = 18,
        }
        assert.are.same(
            {
                IsFishingLoot = "function",
                C_Map = "table",
                ["C_Map.GetBestMapForUnit"] = "function",
                ["C_Map.GetMapInfo"] = "nil",
                GetSkillLineInfo = "nil",
                WOW_PROJECT_ID = "number",
            },
            Scan.Existence(env, {
                "IsFishingLoot",
                "C_Map",
                "C_Map.GetBestMapForUnit",
                "C_Map.GetMapInfo",
                "GetSkillLineInfo",
                "WOW_PROJECT_ID",
            })
        )
    end)

    it("lists namespace members by type and rejects non-tables", function()
        assert.are.same(
            { GetA = "function", VALUE = "number" },
            Scan.Members({ GetA = forbidden, VALUE = 1, [1] = "array" })
        )
        assert.is_nil(Scan.Members(nil))
        assert.is_nil(Scan.Members("text"))
    end)

    it("collects matching string globals sorted by name and capped", function()
        local env = {
            ERR_FISH_NOT_HOOKED = "No fish are hooked.",
            ERR_FISH_ESCAPED = "Your fish got away!",
            LURE_TEXT = "Lure",
            FISHING_COUNT = 5,
            IsFishingLoot = forbidden,
            OTHER = "text",
        }
        local found = Scan.Collect(env, Scan.NameContains({ "FISH", "LURE" }, "string"), 2)
        assert.are.equal(3, found.total)
        assert.are.equal(1, found.cut)
        assert.are.same({
            { name = "ERR_FISH_ESCAPED", value = "Your fish got away!" },
            { name = "ERR_FISH_NOT_HOOKED", value = "No fish are hooked." },
        }, found.items)
    end)

    it("matches names case-sensitively", function()
        local found =
            Scan.Collect({ fish_lower = "x", Fishing = "y" }, Scan.NameContains({ "FISH" }))
        assert.are.equal(0, found.total)
    end)

    it("collects by prefix with any value type", function()
        local env = { WOW_PROJECT_ID = 18, WOW_PROJECT_CAMELOT = 18, WOW_PROJECT_MAINLINE = 1 }
        local found = Scan.Collect(env, Scan.NameStartsWith("WOW_PROJECT_"))
        assert.are.equal(3, found.total)
        assert.are.equal(0, found.cut)
        assert.are.equal("WOW_PROJECT_CAMELOT", found.items[1].name)
    end)

    it("returns an empty result for a missing table", function()
        assert.are.same(
            { items = {}, total = 0, cut = 0 },
            Scan.Collect(nil, Scan.NameStartsWith("X"))
        )
    end)

    it("skips secret keys and secret values of a typed match", function()
        local secret = setmetatable({}, { __index = forbidden, __tostring = forbidden })
        local original = _G.issecretvalue
        _G.issecretvalue = function(value)
            return value == secret
        end
        local ok, err = pcall(function()
            Scan = addon.load({ "Scan.lua" }).Scan
            local env = { [secret] = "hidden", FISH_SECRET = secret, FISH_TEXT = "ok" }
            local found = Scan.Collect(env, Scan.NameContains({ "FISH" }, "string"))
            assert.are.equal(1, found.total)
            assert.are.equal("FISH_TEXT", found.items[1].name)
            assert.are.equal("<secret>", Scan.Existence(env, { "FISH_SECRET" }).FISH_SECRET)
        end)
        _G.issecretvalue = original
        assert(ok, err)
    end)

    it("splits lists into chunks", function()
        assert.are.same({ { 1, 2 }, { 3, 4 }, { 5 } }, Scan.Chunk({ 1, 2, 3, 4, 5 }, 2))
        assert.are.same({}, Scan.Chunk({}, 2))
    end)
end)
