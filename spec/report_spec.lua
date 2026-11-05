local addon = require("spec.helpers.addon")

local FILES = {
    "Locale.lua",
    "Steps.lua",
    "ReportRules.lua",
    "RulesLogin.lua",
    "RulesCasts.lua",
    "RulesPassive.lua",
    "Report.lua",
}

local function call(...)
    return { exists = true, ok = true, n = select("#", ...), values = { ... } }
end

local function entry(kind, data, step, q)
    return { t = 1, kind = kind, data = data, step = step or "S0", q = q }
end

local function snapshot(topic, data, q)
    data.topic = topic
    return entry("snapshot", data, "S0", q)
end

-- A context entry with fishing skill 75/150 (+mod) in the given step.
local function context(step, mod, extra)
    local data = {
        professions = {
            list = call(nil, nil, nil, 4),
            info = { [4] = call("Fishing", 1, 75, 150, 0, 0, 356, mod) },
        },
        mainHand = call(6256),
        weaponEnchant = call(true, 600000, 0, 263),
        buffs = { { spellId = 1234, duration = 600 } },
        location = { mapID = 1429 },
    }
    for key, value in pairs(extra or {}) do
        data[key] = value
    end
    return entry("context", data, step, "Q07")
end

local function attempt(step, outcome, bite)
    return entry("attempt", { outcome = outcome, biteTime = bite }, step)
end

local function loot(step, autoLoot, numItems, sourceId)
    return entry("loot", {
        isFishingLoot = call(true),
        numItems = call(numItems or 1),
        autoLoot = autoLoot,
        slots = {
            { itemID = 6291, sources = { { source = { type = "GameObject", id = sourceId } } } },
        },
    }, step, "Q09")
end

-- A log in which every question has complete evidence.
local function fullLog()
    local log = {
        snapshot("build", { version = "1.16.1", build = 61000, interface = 16001 }, "Q01"),
        snapshot("project", { id = 2, total = 5 }, "Q02"),
        snapshot("game_rules", { members = { GetGameRuleAsFloat = "function" } }, "Q03"),
        snapshot("api_scan", { group = "loot", total = 10, missing = 2 }, "Q04"),
        snapshot("event_scan", { result = { LOOT_READY = { registered = true } } }, "Q04"),
        snapshot("global_strings", { total = 42, items = {} }, "Q05"),
        snapshot("time", { gameTime = call(12, 30), serverTime = call(1) }, "Q20"),
        snapshot("character_key", {
            guid = { exists = true, ok = true, value = { type = "Player", segments = 3 } },
        }, "Q21"),
        snapshot("persistence", { marker = { found = true, sessions = 2 } }, "Q22"),
        snapshot("restricted_actions", { members = { IsAddOnRestrictionActive = "function" } }),
        snapshot("restricted_getter", { name = "IsAddOnRestrictionActive" }, "Q29"),
        entry("cast", { spellID = 7620 }, "S3", "Q06"),
        context("S1", 0, { phase = "done", mainHand = call(nil) }),
        context("S2", 25, { phase = "done" }),
        context("S9", 50, { phase = "start" }),
        context("S13", 25),
        entry("event", { name = "UNIT_SPELLCAST_SENT", secret = { 4 } }, "S3"),
        entry("event", { name = "CHAT_MSG_SKILL", own = true }, "S3", "Q25"),
        entry("item_info", { itemID = 6291, cached = true, sellPrice = 1 }, "S3", "Q24"),
        entry("tooltip", { line1 = "Fishing Bobber" }, "S10", "Q26"),
        entry("probe_check", { test = "S14a", channelStarted = true }, "S14", "Q28"),
        entry("probe_check", { test = "S14b", received = true }, "S14", "Q27"),
        attempt("S5", "early_click"),
        attempt("S5", "early_click"),
        attempt("S6", "timeout"),
        attempt("S6", "timeout"),
        attempt("S7", "cancel"),
        attempt("S7", "cancel"),
        attempt("S8", "invalid_target"),
        attempt("S12", "getaway"),
    }
    for i = 1, 5 do
        log[#log + 1] = attempt("S3", "catch", 3 + i / 10)
        log[#log + 1] = loot("S3", false, i == 1 and 2 or 1)
    end
    log[#log + 1] = loot("S4", true)
    log[#log + 1] = loot("S11", false, 1, 180582)
    return log
end

describe("Report", function()
    local ns = addon.load(FILES)

    local function build(entries, skipped)
        return ns.Report.Build(entries, {
            rules = ns.ReportRules.list,
            steps = ns.Steps,
            status = function(id)
                return skipped and skipped[id] and "skipped" or "done"
            end,
        })
    end

    local function rowFor(report, q)
        for _, r in ipairs(report.rows) do
            if r.q == q then
                return r
            end
        end
    end

    it("has one rule per question Q01-Q32, in order", function()
        local report = build({})
        assert.are.equal(32, #report.rows)
        for i, r in ipairs(report.rows) do
            assert.are.equal(string.format("Q%02d", i), r.q)
        end
    end)

    it("marks every question answered for a complete run, with key values", function()
        local report = build(fullLog())
        for _, r in ipairs(report.rows) do
            assert.are.equal("answered", r.status, r.q .. " " .. tostring(r.value))
            assert.is_string(r.value, r.q)
            assert.is_nil(r.ruleError, r.q)
        end
        assert.are.same({ answered = 32, partial = 0, skipped = 0, missing = 0 }, report.totals)
        local values = {
            Q01 = "interface 16001, build 61000, version 1.16.1",
            Q06 = "1 casts, spell 7620 1",
            Q07 = "fishing skill S1 75/150 +0, S2 75/150 +25, S9 75/150 +50",
            Q08 = "5 catches, bite time 3.1-3.5 s",
            Q10 = "1 loots, sources: GameObject 180582 1",
            Q11 = "early_click 2",
            Q17 = "pole item 6256, fishing skill 75/150 +25",
            Q22 = "marker kept in 1 of 1 sessions, reload seen no",
            Q23 = "secret values in 1 of 10 entries",
            Q30 = "multi-item loots: 1 of 7",
            Q32 = "auto loot on: 1 loots, off: 6 loots",
        }
        for q, want in pairs(values) do
            assert.are.equal(want, rowFor(report, q).value, q)
        end
    end)

    it("reports missing and skipped questions for an empty log", function()
        local report = build({}, { S5 = true })
        assert.are.equal("skipped", rowFor(report, "Q11").status)
        assert.are.equal("missing", rowFor(report, "Q12").status)
        -- Questions without a step (passive recorders) are never skipped.
        assert.are.equal("missing", rowFor(report, "Q30").status)
        assert.are.equal(1, report.totals.skipped)
        assert.are.equal(31, report.totals.missing)
    end)

    it("needs every linked step skipped before a question counts as skipped", function()
        local report = build({}, { S3 = true })
        assert.are.equal("missing", rowFor(report, "Q09").status) -- S4 still open
        report = build({}, { S3 = true, S4 = true })
        assert.are.equal("skipped", rowFor(report, "Q09").status)
    end)

    it("marks partial evidence", function()
        local log = {
            attempt("S5", "unknown"),
            attempt("S5", "unknown"),
            attempt("S3", "catch"),
            snapshot("persistence", { marker = { found = false, sessions = 1 } }, "Q22"),
            entry("event", { name = "SKILL_LINES_CHANGED" }, "S3", "Q25"),
            loot("S3", false),
        }
        local report = build(log)
        local q11 = rowFor(report, "Q11")
        assert.are.equal("partial", q11.status) -- classifier missed: raw events need analysis
        assert.are.equal("unknown 2", q11.value)
        assert.are.equal("partial", rowFor(report, "Q08").status) -- 1 of 5 catches
        assert.are.equal("partial", rowFor(report, "Q22").status) -- first session only
        assert.are.equal("partial", rowFor(report, "Q25").status) -- no skill-up message
        assert.are.equal("partial", rowFor(report, "Q30").status) -- no multi-item loot
        assert.are.equal("partial", rowFor(report, "Q32").status) -- auto loot off only
    end)

    it("ignores earlier report entries and survives broken rules and odd data", function()
        local log = fullLog()
        log[#log + 1] = entry("report", { rows = {} })
        log[#log + 1] = { kind = "snapshot", data = "not a table" }
        local rules = {}
        for i, rule in ipairs(ns.ReportRules.list) do
            rules[i] = rule
        end
        rules[1] = {
            q = "Q01",
            match = ns.ReportRules.Topic("build"),
            value = function()
                error("boom")
            end,
        }
        local report = ns.Report.Build(log, {
            rules = rules,
            steps = ns.Steps,
            status = function()
                return "done"
            end,
        })
        assert.are.equal(#log, report.entries)
        local q01 = report.rows[1]
        assert.are.equal("partial", q01.status)
        assert.is_true(q01.ruleError)
        assert.are.equal("answered", rowFor(report, "Q02").status)
    end)

    it("shortens long key values", function()
        local log = { entry("tooltip", { line1 = string.rep("x", 400) }, "S10") }
        local q26 = rowFor(build(log), "Q26")
        assert.are.equal(ns.Report.MAX_VALUE, #q26.value)
    end)

    it("renders a text with totals and one line per question", function()
        local report = build({}, { S5 = true })
        local text = ns.Report.Text(report)
        assert.truthy(text:find("Answered 0, partial 0, skipped 1, missing 31", 1, true))
        for i = 1, 32 do
            assert.truthy(text:find(string.format("Q%02d  ", i), 1, true), i)
        end
        assert.truthy(text:find("Q11  skipped      0  steps S5", 1, true))
    end)

    it("keeps the log data compact", function()
        local data = ns.Report.LogData(build(fullLog()))
        assert.are.equal(32, #data.rows)
        assert.is_nil(data.rows[1].steps)
        assert.are.equal(32, data.totals.answered)
    end)
end)

describe("ReportRules helpers", function()
    local ns = addon.load(FILES)
    local R = ns.ReportRules

    it("finds secret markers and flags", function()
        assert.is_true(R.HasSecret({ a = { b = "<secret:number>" } }))
        assert.is_true(R.HasSecret({ secret = { 2 } }))
        assert.is_false(R.HasSecret({ a = "plain", secret = false }))
    end)

    it("reads the fishing skill only from a successful profession call", function()
        assert.is_nil(R.FishingSkill({}))
        assert.is_nil(R.FishingSkill({ professions = { info = { [4] = { ok = false } } } }))
    end)
end)
