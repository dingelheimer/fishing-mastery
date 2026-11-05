local addon = require("spec.helpers.addon")

describe("Db", function()
    local Db

    before_each(function()
        Db = addon.load({ "Db.lua" }).Db
    end)

    it("creates a fresh database", function()
        local db = Db.Init(nil)
        assert.are.equal(Db.SCHEMA_VERSION, db.schemaVersion)
        assert.are.same({}, db.log.entries)
        assert.are.equal(0, db.log.dropped)
        assert.are.equal("S0", db.progress.step)
    end)

    it("keeps saved data", function()
        local saved = {
            schemaVersion = 1,
            log = { entries = { { kind = "x" } }, dropped = 3 },
            progress = { step = "S4" },
        }
        local db = Db.Init(saved)
        assert.are.equal(saved, db)
        assert.are.equal(1, #db.log.entries)
        assert.are.equal(3, db.log.dropped)
        assert.are.equal("S4", db.progress.step)
    end)

    it("writes a persistence marker and reports the previous one", function()
        local db = Db.Init(nil)
        assert.are.same({ found = false, sessions = 1 }, Db.Mark(db, "first"))
        assert.are.same({ sessions = 1, lastSessionId = "first" }, db.marker)
        local reloaded = Db.Init(db)
        assert.are.same(
            { found = true, previousSessionId = "first", sessions = 2 },
            Db.Mark(reloaded, "second")
        )
        assert.are.equal("second", reloaded.marker.lastSessionId)
    end)

    it("replaces an invalid marker", function()
        local db = Db.Init({ schemaVersion = 1, marker = "broken" })
        assert.are.same({ found = false, sessions = 1 }, Db.Mark(db, "x"))
    end)

    it("repairs invalid fields", function()
        local db = Db.Init({ schemaVersion = 1, log = "broken", progress = 5 })
        assert.are.same({}, db.log.entries)
        assert.are.equal("S0", db.progress.step)
    end)
end)
