local addon = require("spec.helpers.addon")

describe("FishingMastery Db", function()
    local Db

    before_each(function()
        Db = addon.load({ "Db.lua" }, nil, "FishingMastery").Db
    end)

    describe("schema", function()
        it("creates a fresh database at schema 2", function()
            local db, info = Db.Init(nil, { now = 100 })
            assert.are.equal(2, Db.SCHEMA_VERSION)
            assert.are.equal(2, db.schemaVersion)
            assert.are.same({}, db.chars)
            assert.are.same({}, db.settings)
            assert.is_true(info.fresh)
            assert.is_nil(info.migratedFrom)
            assert.is_nil(db.migrationSnapshot)
        end)

        it("keeps saved data", function()
            local saved = {
                schemaVersion = 2,
                chars = { ["Player-1-0A"] = { name = "A" } },
                settings = { x = 1 },
            }
            local db, info = Db.Init(saved)
            assert.are.equal(saved, db)
            assert.are.equal("A", db.chars["Player-1-0A"].name)
            assert.is_false(info.fresh)
            assert.are.equal(0, info.repaired)
        end)

        it("repairs missing and invalid fields", function()
            local db, info = Db.Init({
                schemaVersion = 2,
                chars = { ["Player-1-0A"] = "broken", [5] = {}, ["Player-1-0B"] = {} },
                settings = 7,
                migrationSnapshot = "bad",
            })
            assert.are.same({ ["Player-1-0B"] = {} }, db.chars)
            assert.are.same({}, db.settings)
            assert.is_nil(db.migrationSnapshot)
            assert.are.equal(4, info.repaired)
        end)

        it("leaves a newer schema unmigrated and reports it", function()
            local db, info = Db.Init({ schemaVersion = 3, chars = {} })
            assert.are.equal(3, db.schemaVersion)
            assert.are.equal(3, info.newer)
        end)
    end)

    describe("migrations", function()
        local migrations, calls

        before_each(function()
            calls = {}
            migrations = {
                [1] = {
                    tables = { "chars" },
                    run = function(db)
                        calls[#calls + 1] = 1
                        for _, entry in pairs(db.chars) do
                            entry.v2 = true
                        end
                    end,
                },
                [2] = {
                    tables = { "chars", "settings" },
                    run = function(db)
                        calls[#calls + 1] = 2
                        db.settings.v3 = true
                    end,
                },
            }
        end)

        local function oldDb()
            return {
                schemaVersion = 1,
                chars = { ["Player-1-0A"] = { name = "A" } },
                settings = { keep = 1 },
                other = { untouched = true },
            }
        end

        it("walks every step in order up to the target", function()
            local db, info =
                Db.Init(oldDb(), { migrations = migrations, schemaVersion = 3, now = 50 })
            assert.are.same({ 1, 2 }, calls)
            assert.are.equal(3, db.schemaVersion)
            assert.are.equal(1, info.migratedFrom)
            assert.is_true(db.chars["Player-1-0A"].v2)
            assert.is_true(db.settings.v3)
        end)

        it("keeps a snapshot of the affected tables only, as before the migration", function()
            local db, info =
                Db.Init(oldDb(), { migrations = migrations, schemaVersion = 3, now = 50 })
            local snapshot = db.migrationSnapshot
            assert.is_true(info.snapshotCreated)
            assert.are.equal(1, snapshot.fromVersion)
            assert.are.equal(3, snapshot.toVersion)
            assert.are.equal(50, snapshot.createdAt)
            assert.are.same({ ["Player-1-0A"] = { name = "A" } }, snapshot.tables.chars)
            assert.are.same({ keep = 1 }, snapshot.tables.settings)
            assert.is_nil(snapshot.tables.other)
            assert.are_not.equal(db.chars, snapshot.tables.chars)
        end)

        it("restores the snapshot and keeps the old version when a step fails", function()
            migrations[2].run = function(db)
                db.chars["Player-1-0A"].half = true
                error("step 2 broken")
            end
            local db, info = Db.Init(oldDb(), { migrations = migrations, schemaVersion = 3 })
            assert.are.equal(1, db.schemaVersion)
            assert.truthy(info.migrationError:find("step 2 broken", 1, true))
            assert.is_nil(info.migratedFrom)
            assert.are.same({ name = "A" }, db.chars["Player-1-0A"])
        end)

        it("does not start when a step is missing", function()
            migrations[2] = nil
            local db, info = Db.Init(oldDb(), { migrations = migrations, schemaVersion = 3 })
            assert.are.equal("missing migration 2", info.migrationError)
            assert.are.equal(1, db.schemaVersion)
            assert.is_nil(db.migrationSnapshot)
            assert.are.same({}, calls)
        end)

        it("drops the snapshot only on a later login without errors", function()
            local db, info = Db.Init(oldDb(), { migrations = migrations, schemaVersion = 3 })
            assert.is_false(Db.ConfirmLogin(db, info, 0))
            assert.is_table(db.migrationSnapshot)

            local reloaded, info2 = Db.Init(db, { migrations = migrations, schemaVersion = 3 })
            assert.is_false(Db.ConfirmLogin(reloaded, info2, 1))
            assert.is_table(reloaded.migrationSnapshot)
            assert.is_true(Db.ConfirmLogin(reloaded, info2, 0))
            assert.is_nil(reloaded.migrationSnapshot)
        end)
    end)

    describe("per-character variable", function()
        it("holds the UI layout only", function()
            assert.are.same({ schemaVersion = 1, ui = {} }, Db.InitChar(nil))
            local saved = { schemaVersion = 1, ui = { x = 5 } }
            assert.are.equal(saved, Db.InitChar(saved))
            assert.are.same({ schemaVersion = 1, ui = {} }, Db.InitChar({ ui = "bad" }))
        end)
    end)

    it("deep-copies nested and shared tables", function()
        local shared = { 1 }
        local copy = Db.DeepCopy({ a = shared, b = shared, c = { d = "x" } })
        assert.are.same({ 1 }, copy.a)
        assert.are.equal(copy.a, copy.b)
        assert.are_not.equal(shared, copy.a)
        assert.are.equal("x", copy.c.d)
    end)

    describe("schema 2 migration", function()
        it("marks every character's totals stale and keeps a snapshot of the characters", function()
            local totals = { version = 1, outcomes = { catch = 3 }, days = {}, maps = {} }
            local db, info = Db.Init({
                schemaVersion = 1,
                chars = {
                    ["Player-1-0A"] = { totals = totals, days = { "20763|5,1" } },
                    ["Player-1-0B"] = {},
                },
                settings = {},
            }, { now = 70 })
            assert.are.equal(1, info.migratedFrom)
            assert.are.equal(2, db.schemaVersion)
            assert.is_nil(db.chars["Player-1-0A"].totals.version)
            assert.are.same({ catch = 3 }, db.chars["Player-1-0A"].totals.outcomes)
            assert.are.same({ "20763|5,1" }, db.migrationSnapshot.tables.chars["Player-1-0A"].days)
            assert.are.equal(1, db.migrationSnapshot.fromVersion)
            assert.are.equal(2, db.migrationSnapshot.toVersion)
        end)
    end)
end)
