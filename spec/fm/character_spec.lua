local addon = require("spec.helpers.addon")

describe("FishingMastery Character", function()
    local Character, db

    local GUID = "Player-5827-0ABCDEF0"

    local function env(guid, name, part)
        return {
            UnitGUID = function(unit)
                assert.are.equal("player", unit)
                return guid
            end,
            UnitFullName = function()
                return name, part
            end,
            GetRealmName = function()
                error("GetRealmName must not be used")
            end,
        }
    end

    before_each(function()
        Character = addon.load({ "Character.lua" }, nil, "FishingMastery").Character
        db = { chars = {} }
    end)

    after_each(function()
        _G.issecretvalue = nil
    end)

    it("uses the player GUID as key", function()
        assert.are.equal(GUID, Character.Key(env(GUID)))
    end)

    it("rejects missing, empty, and non-player GUIDs", function()
        assert.is_nil(Character.Key({}))
        assert.is_nil(Character.Key(env(nil)))
        assert.is_nil(Character.Key(env("")))
        assert.is_nil(Character.Key(env("Creature-0-1-2-3-4-5")))
    end)

    it("rejects a secret GUID", function()
        _G.issecretvalue = function(value)
            return value == GUID
        end
        Character = addon.load({ "Character.lua" }, nil, "FishingMastery").Character
        assert.is_nil(Character.Key(env(GUID)))
    end)

    it("creates an entry with both name parts for display", function()
        local key, entry = Character.Ensure(db, env(GUID, "Dingel", "Brightwater"), 100)
        assert.are.equal(GUID, key)
        assert.are.same(
            { name = "Dingel", part = "Brightwater", firstSeen = 100, lastSeen = 100 },
            entry
        )
        assert.are.equal(entry, db.chars[GUID])
    end)

    it("updates the same entry on the next login and keeps known names", function()
        Character.Ensure(db, env(GUID, "Dingel", "Brightwater"), 100)
        local _, entry = Character.Ensure(db, env(GUID, nil, nil), 200)
        assert.are.same(
            { name = "Dingel", part = "Brightwater", firstSeen = 100, lastSeen = 200 },
            entry
        )
        assert.are.equal(1, Character.Count(db))
    end)

    it("falls back to UnitName", function()
        local e = env(GUID)
        e.UnitFullName = nil
        e.UnitName = function()
            return "Dingel", "Brightwater"
        end
        local _, entry = Character.Ensure(db, e, 1)
        assert.are.equal("Brightwater", entry.part)
    end)

    it("stores nothing without a GUID", function()
        assert.is_nil(Character.Ensure(db, env(nil, "Dingel", "Brightwater"), 1))
        assert.are.same({}, db.chars)
        assert.are.equal(0, Character.Count(db))
        assert.are.equal(0, Character.Count(nil))
    end)
end)
