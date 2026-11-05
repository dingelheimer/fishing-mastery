-- Boot tests for the data commands: /fm backup with the confirmation dialog, /fm export and
-- /fm import through the text window, and the reload reminder, through every TOC file.
local fmboot = require("spec.helpers.fmboot")
local fakeui = require("spec.helpers.fakeui")

local GUID = fmboot.GUID

describe("FishingMastery data commands boot", function()
    local w

    before_each(function()
        w = fmboot.new()
    end)

    after_each(function()
        w.cleanup()
    end)

    local function char()
        return _G.FishingMasteryDB.chars[GUID]
    end

    local function editBox()
        return fakeui.frames(w.env, "EditBox")[1]
    end

    it("takes a snapshot at login and restores it after confirmation", function()
        w.boot(nil, nil)
        w.catch(5000, 10)
        assert.are.equal(1, #_G.FishingMasteryDB.backups)
        _G.SlashCmdList.FM("backup list")
        assert.truthy(w.output():find("1: %d+, totals of 1 character%(s%)"))

        local saved = char().totals
        char().totals = { outcomes = { catch = 999 }, days = {}, maps = {} }
        w.printed = {}
        _G.SlashCmdList.FM("backup restore 1")
        assert.are.equal(0, #w.printed) -- nothing happens before the click
        assert.are.equal(999, char().totals.outcomes.catch)
        fakeui.button(w.env, "Restore"):Click()
        assert.truthy(w.output():find("Snapshot 1 from", 1, true))
        -- The login snapshot was taken before the catch.
        assert.is_nil(char().totals.outcomes.catch)
        assert.are_not.equal(saved, char().totals)

        w.printed = {}
        _G.SlashCmdList.FM("backup restore 7")
        assert.truthy(w.output():find("Usage: /fm backup", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("exports into a read-only window and imports a pasted page", function()
        w.boot(nil, nil)
        w.catch(5000, 10)
        w.catch(5030, 12)
        _G.SlashCmdList.FM("export")
        local box = editBox()
        local text = box:GetText()
        assert.truthy(text:find("^FMX!1!char!1!1!"))
        assert.is_nil(text:find("|", 1, true))
        assert.is_nil(text:find(GUID, 1, true))
        assert.truthy(w.output():find("Export ready: 1 page(s).", 1, true))
        box:Type("changed")
        assert.are.equal(text, box:GetText()) -- read-only
        fakeui.button(w.env, "Select all"):Click()
        assert.is_true(box.highlighted)

        -- Lose the history, then import the page again.
        char().days, char().casts = {}, {}
        w.printed = {}
        _G.SlashCmdList.FM("import")
        assert.are.equal("", box:GetText())
        box:Type(text)
        fakeui.button(w.env, "Import"):Click()
        assert.truthy(w.output():find("Import done: 1 day(s) with 2 casts added", 1, true))
        assert.are.equal(2, char().totals.outcomes.catch)

        w.printed = {}
        box:Type("not an export")
        fakeui.button(w.env, "Import"):Click()
        assert.truthy(w.output():find("Import failed, nothing was changed", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("includes the character GUID only in the full backup export", function()
        w.boot(nil, nil)
        w.catch(5000, 10)
        _G.SlashCmdList.FM("export all")
        assert.truthy(editBox():GetText():find("C!" .. GUID .. "!Dingel!Brightwater!", 1, true))
    end)

    it("reminds to /reload after 2 hours of fishing unless switched off", function()
        w.boot(nil, nil)
        for i = 0, 12 do
            w.catch(5000 + i * 600, 10)
        end
        assert.truthy(w.output():find("Type /reload now and then", 1, true))

        w.printed = {}
        _G.SlashCmdList.FM("reminder off")
        assert.truthy(w.output():find("Reload reminder: off", 1, true))
        for i = 13, 26 do
            w.catch(5000 + i * 600, 10)
        end
        assert.is_nil(w.output():find("Type /reload", 1, true))
        assert.is_false(_G.FishingMasteryDB.settings.reloadReminder)
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
