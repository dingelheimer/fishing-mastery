local addon = require("spec.helpers.addon")

describe("FishingMastery backups", function()
    local Backup, db

    local GUID, OTHER = "Player-1-0A", "Player-1-0B"

    before_each(function()
        Backup = addon.load({ "Db.lua", "Backup.lua" }, nil, "FishingMastery").Backup
        db = {
            settings = { reloadReminder = true },
            chars = {
                [GUID] = { totals = { outcomes = { catch = 1 } } },
                [OTHER] = { name = "no totals" },
            },
        }
    end)

    it("takes one snapshot per day of the settings and every character's totals", function()
        assert.is_true(Backup.Take(db, 100, 8640000))
        assert.is_false(Backup.Take(db, 100, 8640500))
        local snapshot = db.backups[1]
        assert.are.equal(100, snapshot.day)
        assert.are.same({ reloadReminder = true }, snapshot.settings)
        assert.are.same({ [GUID] = { outcomes = { catch = 1 } } }, snapshot.totals)
        -- A copy: later changes do not reach the snapshot.
        db.chars[GUID].totals.outcomes.catch = 99
        assert.are.equal(1, snapshot.totals[GUID].outcomes.catch)
        assert.is_nil(snapshot.days)
    end)

    it("keeps the last 3 days, newest first", function()
        for day = 100, 104 do
            Backup.Take(db, day, day * 86400)
        end
        local list = Backup.List(db)
        assert.are.equal(3, #list)
        assert.are.same({ 104, 103, 102 }, { list[1].day, list[2].day, list[3].day })
        assert.are.equal(1, list[1].chars)
    end)

    it("restores totals and settings and leaves unknown characters alone", function()
        Backup.Take(db, 100, 0)
        Backup.Take(db, 101, 0)
        db.backups[2].totals.gone = { outcomes = {} }
        db.chars[GUID].totals = { outcomes = { catch = 50 } }
        db.settings.reloadReminder = false
        assert.is_true(Backup.Restore(db, 2))
        assert.are.same({ outcomes = { catch = 1 } }, db.chars[GUID].totals)
        assert.is_true(db.settings.reloadReminder)
        assert.is_nil(db.chars.gone)
        assert.is_false(Backup.Restore(db, 3))
        assert.is_false(Backup.Restore(db, "x"))
    end)

    it("repairs a broken backup list", function()
        db.backups = "broken"
        assert.are.same({}, Backup.List(db))
        assert.is_true(Backup.Take(db, 1, 0))
    end)

    describe("reload reminder", function()
        it("reminds once per 2 hours of a session", function()
            local session = { start = 0, last = 7199 }
            assert.is_false(Backup.ShouldRemind(db.settings, session))
            session.last = 7200
            assert.is_true(Backup.ShouldRemind(db.settings, session))
            assert.is_false(Backup.ShouldRemind(db.settings, session))
            session.last = 14500
            assert.is_true(Backup.ShouldRemind(db.settings, session))
            assert.are.equal(2, session.reminders)
        end)

        it("is on by default and can be switched off", function()
            assert.is_true(Backup.ShouldRemind({}, { start = 0, last = 8000 }))
            assert.is_false(
                Backup.ShouldRemind({ reloadReminder = false }, { start = 0, last = 8000 })
            )
            assert.is_false(Backup.ShouldRemind({}, nil))
        end)
    end)
end)
