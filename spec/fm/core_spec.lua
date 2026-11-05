-- Boot test: loads every FishingMastery TOC file against the fake UI and drives the client
-- events and the slash command, so wiring errors in Core.lua show up without the game.
local fmboot = require("spec.helpers.fmboot")
local addon = require("spec.helpers.addon")

local ADDON, GUID = fmboot.ADDON, fmboot.GUID

describe("FishingMastery boot", function()
    local w

    before_each(function()
        w = fmboot.new()
    end)

    after_each(function()
        w.cleanup()
    end)

    it("loads every TOC file and creates the character entry without errors", function()
        w.boot(nil, nil)
        assert.are.equal(0, w.ns.Guard.errors)
        assert.are.equal(1, _G.FishingMasteryDB.schemaVersion)
        assert.are.equal(GUID, w.ns.charKey)
        local entry = _G.FishingMasteryDB.chars[GUID]
        assert.are.equal("Dingel", entry.name)
        assert.are.equal("Brightwater", entry.part)
        assert.are.same({ schemaVersion = 1, ui = {} }, _G.FishingMasteryCharDB)
        assert.are.equal("/fm", _G.SLASH_FM1)
        assert.are.equal("/fishingmastery", _G.SLASH_FM2)
        assert.are.same({}, w.printed)
    end)

    it("keeps the character entry across /reload", function()
        w.boot(nil, nil)
        local firstSeen = _G.FishingMasteryDB.chars[GUID].firstSeen
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
        local entry = _G.FishingMasteryDB.chars[GUID]
        assert.are.equal(firstSeen, entry.firstSeen)
        assert.is_true(entry.lastSeen > firstSeen)
        assert.are.equal(1, w.ns.Character.Count(_G.FishingMasteryDB))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("prints help, version, character count, and errors for /fm and its alias", function()
        w.boot({ schemaVersion = 1, chars = { ["Player-1-0A"] = {} } }, nil)
        _G.SlashCmdList.FM("")
        local text = w.output()
        assert.truthy(text:find("Version 0.1.0", 1, true))
        assert.truthy(text:find("/fm help", 1, true))
        assert.truthy(text:find("Characters with saved data: 2", 1, true))
        assert.truthy(text:find("Lua errors this session: 0", 1, true))

        w.printed = {}
        _G.SlashCmdList.FM("nonsense")
        assert.truthy(w.output():find("Unknown command: nonsense", 1, true))
        assert.truthy(w.output():find("Version 0.1.0", 1, true))
    end)

    it("lists recent Lua errors and keeps the UI running", function()
        w.boot(nil, nil)
        w.ns.Commands.Register("boom", "test", function()
            error("broken command")
        end)
        for _ = 1, w.ns.MAX_RECENT_ERRORS + 2 do
            _G.SlashCmdList.FM("boom")
        end
        assert.are.equal(w.ns.MAX_RECENT_ERRORS + 2, w.ns.Guard.errors)
        assert.are.equal(w.ns.MAX_RECENT_ERRORS, #w.ns.recentErrors)
        w.printed = {}
        _G.SlashCmdList.FM("help")
        local text = w.output()
        assert.truthy(text:find("Lua errors this session: 12 (last 3 shown)", 1, true))
        assert.truthy(text:find("slash: .*broken command"))
    end)

    it("drops a migration snapshot only on a later clean login", function()
        local snapshot = { fromVersion = 0, toVersion = 1, tables = {} }
        w.boot({ schemaVersion = 1, migrationSnapshot = snapshot }, nil)
        assert.is_nil(_G.FishingMasteryDB.migrationSnapshot)
    end)

    it("warns about a newer schema and leaves it unmigrated", function()
        w.boot({ schemaVersion = 9 }, nil)
        assert.truthy(w.output():find("newer version (schema 9", 1, true))
        assert.are.equal(9, _G.FishingMasteryDB.schemaVersion)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("saves no character entry without a GUID", function()
        w.boot(nil, nil, false)
        assert.truthy(w.output():find("Character not recognized yet", 1, true))
        assert.is_nil(w.ns.charKey)
        assert.are.same({}, _G.FishingMasteryDB.chars)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("declares no dependency on the probe", function()
        for line in io.lines(ADDON .. "/" .. ADDON .. ".toc") do
            assert.is_nil(line:find("Dep", 1, true))
            assert.is_nil(line:find("FishingMasteryProbe", 1, true))
        end
        for _, file in ipairs(addon.tocFiles(ADDON)) do
            assert.is_nil(file:find("..", 1, true))
        end
    end)
end)
