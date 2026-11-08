local addon = require("spec.helpers.addon")
local synthetic = require("spec.helpers.synthetic")

local FILES = {
    "Db.lua",
    "Records.lua",
    "Codec.lua",
    "CodecDecode.lua",
    "History.lua",
    "Options.lua",
    "Totals.lua",
    "Export.lua",
    "Import.lua",
}
local GUID, OTHER = "Player-5827-0ABCDEF0", "Player-5827-0ABCDEF1"

describe("FishingMastery export and import", function()
    local ns, db

    local function prepare(entry)
        for _, name in ipairs({ "casts", "days", "quarantine", "subzones", "sessions" }) do
            entry[name] = entry[name] or {}
        end
        entry.totals = ns.Totals.Repair(entry.totals)
        return entry
    end

    -- A character with packed days, one open cast, and subzone texts.
    local function character(seed, count)
        local entry = prepare({ name = "Dingel", part = "Brightwater" })
        entry.subzones =
            { "Darkspear Strand", "Sen'jin | Village", "Razor Hill/Coast", "Echo Isles" }
        entry.casts = synthetic.casts(count or 600, 1793836800, seed)
        ns.History.Pack(entry)
        entry.casts = { { t = 1893836800, out = "cancel", map = 1411, sub = 2 } }
        entry.totals = ns.Totals.Rebuild(entry)
        return entry
    end

    local function casts(entry)
        local list = {}
        for cast in ns.History.Iterate(entry) do
            local copy = ns.Db.DeepCopy(cast)
            copy.sub = copy.sub and entry.subzones[copy.sub] or nil -- compare by subzone text
            list[#list + 1] = copy
        end
        return list
    end

    local function import(text, key)
        local staged, err = ns.Import.Parse(text)
        if not staged then
            return nil, err
        end
        return ns.Import.Merge(db, staged, key or GUID, prepare)
    end

    before_each(function()
        ns = addon.load(FILES, nil, "FishingMastery")
        db = { chars = { [GUID] = character(5) } }
    end)

    it("round-trips a character's history into an empty character", function()
        local pages = ns.Export.Build(db, "char", GUID)
        assert.are.equal(1, #pages)
        local source = db.chars[GUID]
        db.chars[GUID] = prepare({})
        local summary = assert(import(pages[1]))
        assert.are.equal(601, summary.casts)
        assert.are.equal(0, summary.skipped)
        assert.are.same(casts(source), casts(db.chars[GUID]))
        assert.are.same(source.totals, db.chars[GUID].totals)
    end)

    it("leaves GUID and names out of a character export and keeps them in a full backup", function()
        local text = ns.Export.Build(db, "char", GUID)[1]
        assert.truthy(text:find("^FMX!1!char!1!1!%x+\nC!%-!%-!%-!"))
        assert.is_nil(text:find("|", 1, true)) -- the client edit box treats "|" as an escape
        assert.is_nil(text:find("Player-", 1, true))
        assert.is_nil(text:find("Dingel", 1, true))
        db.chars[OTHER] = character(6, 100)
        local full = ns.Export.Build(db, "all")[1]
        assert.truthy(full:find("C!" .. GUID .. "!Dingel!Brightwater!", 1, true))
        assert.truthy(full:find("C!" .. OTHER .. "!", 1, true))
    end)

    it("restores every character from a full backup, creating missing ones", function()
        db.chars[OTHER] = character(6, 100)
        local expected = { [GUID] = casts(db.chars[GUID]), [OTHER] = casts(db.chars[OTHER]) }
        local text = ns.Export.Build(db, "all")[1]
        db.chars = { [GUID] = prepare({}) }
        local summary = assert(import(text))
        assert.are.equal(2, summary.chars)
        assert.are.same(expected[GUID], casts(db.chars[GUID]))
        assert.are.same(expected[OTHER], casts(db.chars[OTHER]))
        assert.are.equal("Dingel", db.chars[OTHER].name)
    end)

    it("skips days that are already present, so a second import adds nothing", function()
        local text = ns.Export.Build(db, "char", GUID)[1]
        local before = ns.Db.DeepCopy(db.chars[GUID])
        local summary = assert(import(text))
        assert.are.equal(0, summary.days)
        assert.is_true(summary.skipped > 0)
        assert.are.same(before, db.chars[GUID])
    end)

    it("adds only the missing days and keeps chunks in day order", function()
        -- 2,000 casts span several days (600 span only two).
        local full = character(5, 2000)
        local text = ns.Export.Build({ chars = { [GUID] = full } }, "char", GUID)[1]
        db.chars[GUID] = character(5, 2000)
        local entry = db.chars[GUID]
        -- Keep every chunk of the first and the last day (a busy day spans several chunks;
        -- import skips a day that is present at all).
        local function dayOf(chunk)
            return tonumber(chunk:match("^(%d+)|"))
        end
        local firstDay, lastDay = dayOf(entry.days[1]), dayOf(entry.days[#entry.days])
        local keep = {}
        for _, chunk in ipairs(entry.days) do
            if dayOf(chunk) == firstDay or dayOf(chunk) == lastDay then
                keep[#keep + 1] = chunk
            end
        end
        assert.is_true(#keep < #entry.days)
        entry.days = keep
        entry.casts = {}
        local summary = assert(import(text))
        assert.is_true(summary.skipped >= 1)
        -- The export packed the open cast into a chunk of its own day.
        assert.are.equal(#full.days + 1, #entry.days)
        local last = -1
        for _, chunk in ipairs(entry.days) do
            local day = tonumber(chunk:match("^(%d+)|"))
            assert.is_true(day >= last)
            last = day
        end
        assert.are.same(ns.Totals.Rebuild(entry), entry.totals)
    end)

    it("maps subzone indexes onto the target's subzone table", function()
        local text = ns.Export.Build(db, "char", GUID)[1]
        local expected = casts(db.chars[GUID])
        db.chars[GUID] = prepare({ subzones = { "Orgrimmar", "Razor Hill/Coast" } })
        assert(import(text))
        local entry = db.chars[GUID]
        assert.are.equal("Orgrimmar", entry.subzones[1])
        assert.are.same(expected, casts(entry))
    end)

    it("splits long histories into standalone pages without splitting a day", function()
        db.chars[GUID] = character(8, 3000)
        local expected = casts(db.chars[GUID])
        local pages = ns.Export.Build(db, "char", GUID, 6000)
        assert.is_true(#pages > 2)
        db.chars[GUID] = prepare({})
        for i = #pages, 1, -1 do -- any order works
            assert.truthy(pages[i]:find("^FMX!1!char!" .. i .. "!" .. #pages .. "!"))
            assert(import(pages[i]))
        end
        assert.are.same(expected, casts(db.chars[GUID]))
    end)

    it("accepts Windows line endings and surrounding blanks", function()
        local text = ns.Export.Build(db, "char", GUID)[1]
        db.chars[GUID] = prepare({})
        assert(import("  \r\n" .. text:gsub("\n", "\r\n") .. "\r\n\r\n"))
        assert.are.equal(601, #casts(db.chars[GUID]))
    end)

    it("survives the edit box: doubled pipes on paste and '!' in a subzone name", function()
        db.chars[GUID].subzones[2] = "Sen'jin! Village"
        local expected = casts(db.chars[GUID])
        local shown = ns.Export.Build(db, "char", GUID)[1]
        assert.is_nil(shown:find("|", 1, true))
        db.chars[GUID] = prepare({})
        -- An edit box doubles every "|" it is given; the import undoes that too.
        local pasted = ns.Export.FromShown(shown):gsub("|", "||")
        assert(import(pasted))
        assert.are.same(expected, casts(db.chars[GUID]))
    end)

    it("rejects damaged or foreign text and changes nothing", function()
        -- Cases are written in the internal "|" form, which the import also accepts.
        local text = ns.Export.FromShown(ns.Export.Build(db, "char", GUID)[1])
        local header, body = text:match("^([^\n]*)\n(.*)$")
        local function signed(newBody)
            return header:gsub("%x+$", ns.Export.Checksum(newBody)) .. "\n" .. newBody
        end
        local cases = {
            { nil, "no text" },
            { "hello", "missing header" },
            { "hello\nworld", "not a Fishing Mastery export" },
            { (text:gsub("^FMX|1|", "FMX|2|")), "unsupported version" },
            { (text:gsub("^FMX|1|char|", "FMX|1|mine|")), "unknown scope" },
            { text:sub(1, #text - 10), "checksum mismatch" },
            { (text:gsub(";", ";x", 1)), "checksum mismatch" },
            { signed((body:gsub(";", ";x", 1))), "bad history chunk" },
            { signed("D|20763|5,2"), "unexpected line" },
            { signed("C|nobody|-|-|"), "bad character line" },
            { signed(body .. "\nC|-|-|-|\nD|20763|5,2"), "one character" },
            { signed("C|-|-|-|\nD|20763|5,2,,,,,,9"), "bad subzone index" },
        }
        local before = ns.Db.DeepCopy(db)
        for _, case in ipairs(cases) do
            local summary, err = import(case[1])
            assert.is_nil(summary)
            assert.truthy(err:find(case[2], 1, true), tostring(err))
        end
        local full = ns.Export.FromShown(ns.Export.Build(db, "all")[1])
        local fullHeader, fullBody = full:match("^([^\n]*)\n(.*)$")
        local noGuid = (fullBody:gsub("^C|[^|]+|", "C|-|"))
        local _, err = import(fullHeader:gsub("%x+$", ns.Export.Checksum(noGuid)) .. "\n" .. noGuid)
        assert.truthy(err:find("without GUID", 1, true))
        assert.are.same(before, db)
    end)

    it("treats imported text as data and never runs it", function()
        local ran = false
        _G.__fm_import_probe = function()
            ran = true
        end
        local body = "C|-|-|-|\nD|20763|__fm_import_probe()"
        local text = "FMX|1|char|1|1|" .. ns.Export.Checksum(body) .. "\n" .. body
        assert.is_nil(import(text))
        assert.is_false(ran)
        _G.__fm_import_probe = nil
    end)
end)
