-- Contribute.lua and /fm contribute: two characters merged per area (subzone texts resolved,
-- every character numbering its own subzones), an unresolved place, skill bands and lure lines,
-- no forbidden fields in the text, the checksum, empty totals, the account token, and the
-- fixture export spec/fixtures/contribution.txt that the Story 7.2 checker tests read.
local fmboot = require("spec.helpers.fmboot")

local FIXTURE = "spec/fixtures/contribution.txt"

-- Resolver with fixed answers: map 1411 is area 14, its subzone "Tor'kren Farm" area 2979; map 1412
-- is area 17; map 9999 has no area.
local AREAS = {
    Resolve = function(_, map, text)
        if map == 1411 then
            return text == "Tor'kren Farm" and 2979 or 14
        elseif map == 1412 then
            return 17
        end
        return nil
    end,
}

local function chars()
    return {
        ["Player-1-0000000A"] = {
            name = "Brannoc",
            part = "Brann",
            subzones = { "Tor'kren Farm" },
            totals = {
                subs = {
                    [1411] = {
                        [1] = { casts = 10, items = { [6303] = 6 } },
                        [0] = { casts = 4, items = { [6303] = 2, [6358] = 1 } },
                    },
                    [9999] = { [0] = { casts = 2, items = { [6291] = 1 } } },
                },
                subskills = {
                    [1411] = { [1] = { [10] = { hooked = 8, getaways = 2 } } },
                    [9999] = { [0] = { [0] = { hooked = 2, getaways = 1 } } },
                },
                zones = {
                    [1411] = {
                        on = { casts = 3, outcomes = { catch = 2 } },
                        off = { casts = 11, outcomes = { catch = 7 } },
                    },
                },
                days = { [20765] = { casts = 16, catches = 9 } },
                hours = { [14] = { casts = 16 } },
            },
        },
        ["Player-1-0000000B"] = {
            name = "Ysolde",
            part = "Ysol",
            subzones = { "Unknown Cove", "Tor'kren Farm" },
            totals = {
                subs = {
                    [1411] = {
                        [2] = { casts = 5, items = { [6303] = 3 } },
                        [1] = { casts = 1, items = {} },
                    },
                },
                subskills = {
                    [1411] = {
                        [2] = {
                            [10] = { hooked = 4, getaways = 1 },
                            [15] = { hooked = 1, getaways = 0 },
                        },
                    },
                },
                zones = {
                    [1411] = { on = { casts = 2, outcomes = { catch = 1, getaway = 1 } } },
                    [1412] = { off = { casts = 1, outcomes = {} } },
                },
            },
        },
    }
end

local INFO = { token = "0a1b2c3d", version = "1.0.0", build = "70790" }
local BODY = {
    "A!14!5!6303:2,6358:1",
    "A!2979!15!6303:9",
    "M!9999!2!6291:1",
    "S!2979!10!12!3",
    "S!2979!15!1!0",
    "S!m9999!0!2!1",
    "L!1411!5!3",
}

describe("FishingMastery contribution export", function()
    local w, ns

    before_each(function()
        w = fmboot.new()
        w.boot(nil, nil)
        ns = w.ns
    end)

    after_each(function()
        w.cleanup()
    end)

    it("merges both characters per area, with the unresolved place, bands, and lure", function()
        local text, lines = ns.Contribute.Build(chars(), AREAS, INFO)
        local body = table.concat(BODY, "\n")
        assert.are.equal(7, lines)
        assert.are.equal(
            "FMC!1!0a1b2c3d!1.0.0!70790!" .. ns.Export.Checksum(body) .. "\n" .. body,
            text
        )
    end)

    it("holds no names, keys, subzone texts, times, or pipes", function()
        local text = ns.Contribute.Build(chars(), AREAS, INFO)
        assert.truthy(text:match("^[%w!:,\n%.%-]+$"))
        for _, word in ipairs({ "Brann", "Ysol", "kren", "Cove", "Player", "20765" }) do
            assert.is_nil(text:find(word, 1, true), word)
        end
        -- Header fields lose separators and spaces.
        local header = ns.Contribute.Build({}, AREAS, {
            token = "0a1b2c3d",
            version = "1.0 !x|y",
            build = nil,
        })
        assert.are.equal("FMC!1!0a1b2c3d!1.0xy!-!" .. ns.Export.Checksum(""), header)
    end)

    it("has a checksum over every line after the header", function()
        local text = ns.Contribute.Build(chars(), AREAS, INFO)
        local header, body = text:match("^([^\n]+)\n(.*)$")
        local checksum = header:match("!(%x+)$")
        assert.are.equal(ns.Export.Checksum(body), checksum)
        assert.are_not.equal(ns.Export.Checksum((body:gsub("6303:9", "6303:90"))), checksum)
    end)

    it("is a header only for empty totals", function()
        local empty = { ["Player-1-0000000C"] = { subzones = {}, totals = {} } }
        local text, lines = ns.Contribute.Build(empty, AREAS, INFO)
        assert.are.equal(0, lines)
        assert.are.equal("FMC!1!0a1b2c3d!1.0.0!70790!" .. ns.Export.Checksum(""), text)
        assert.are.equal(0, select(2, ns.Contribute.Build(nil, nil, INFO)))
    end)

    it("makes a random token once and replaces it on request", function()
        local values = { 0, 10, 1, 11, 2, 12, 3, 13 }
        local i = 0
        local function random(lo, hi)
            assert.are.same({ 0, 15 }, { lo, hi })
            i = i + 1
            return values[(i - 1) % #values + 1]
        end
        assert.are.equal("0a1b2c3d", ns.Contribute.NewToken(random))
        local db = {}
        assert.are.equal("0a1b2c3d", ns.DataCommands.Token(db, false, random))
        assert.are.equal("0a1b2c3d", db.contributeToken)
        assert.are.equal("0a1b2c3d", ns.DataCommands.Token(db, false, error)) -- kept
        db.contributeToken = "not a token"
        assert.are.equal("0a1b2c3d", ns.DataCommands.Token(db, false, random))
        values = { 15 }
        assert.are.equal("ffffffff", ns.DataCommands.Token(db, true, random))
        assert.is_nil(ns.Contribute.ValidToken("12345"))
        assert.are.equal("abcdef12", ns.Contribute.ValidToken("ABCDEF12"))
    end)

    it("opens the text window with /fm contribute and keeps the token", function()
        w.catch(5000, 9)
        w.runTimers(5012)
        _G.SlashCmdList.FM("contribute")
        local window = ns.textWindow
        local text = window:Text()
        local token = _G.FishingMasteryDB.contributeToken
        assert.truthy(ns.Contribute.ValidToken(token))
        assert.truthy(text:find("^FMC!1!" .. token .. "!0%.1%.0!%-!%x+\n"))
        assert.truthy(text:find("\nL!", 1, true) == nil) -- no lure in this cast
        assert.truthy(w.output():find("Contribution ready: ", 1, true))
        _G.SlashCmdList.FM("contribute new-token")
        assert.are_not.equal(token, _G.FishingMasteryDB.contributeToken)
        assert.truthy(w.output():find("New random token made", 1, true))
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("matches the fixture the checker tests read", function()
        local text = ns.Contribute.Build(chars(), AREAS, INFO) .. "\n"
        local file = io.open(FIXTURE, "rb")
        if not file then
            file = assert(io.open(FIXTURE, "wb"))
            file:write(text)
            file:close()
            return
        end
        local saved = file:read("*a")
        file:close()
        assert.are.equal(saved, text)
    end)
end)
