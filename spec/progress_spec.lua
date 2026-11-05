local addon = require("spec.helpers.addon")

describe("Steps", function()
    local ns = addon.load({ "Steps.lua" })

    it("lists S0-S15 in order with texts and question IDs", function()
        assert.are.equal(16, #ns.Steps.list)
        for i, step in ipairs(ns.Steps.list) do
            assert.are.equal("S" .. (i - 1), step.id)
            assert.are.equal(i, step.index)
            assert.are.equal(step, ns.Steps.byId[step.id])
            for _, field in ipairs({ "title", "instruction", "why", "prereq" }) do
                assert.is_true(type(step[field]) == "string" and #step[field] > 0, step.id .. field)
            end
            assert.is_true(#step.questions > 0)
            for _, q in ipairs(step.questions) do
                assert.truthy(q:match("^Q%d%d$"))
            end
        end
    end)

    it("has the probe plan targets and optional steps", function()
        local expected = {
            S3 = { "catch", 5 },
            S4 = { "catch", 3 },
            S5 = { "attempt", 2 },
            S6 = { "timeout", 2 },
            S7 = { "cancel", 2 },
            S8 = { "attempt", 1 },
            S9 = { "catch", 2 },
            S10 = { "hover", 1 },
            S11 = { "catch", 2 },
            S12 = { "getaway", 1 },
            S13 = { "catch", 1 },
            S14 = { "check", 2 },
        }
        for _, step in ipairs(ns.Steps.list) do
            local want = expected[step.id]
            if want then
                assert.are.same({ kind = want[1], count = want[2] }, step.target)
            else
                assert.is_nil(step.target, step.id)
            end
        end
        local optional = {}
        for _, step in ipairs(ns.Steps.list) do
            if step.optional then
                optional[#optional + 1] = step.id
            end
        end
        assert.are.same({ "S11", "S12", "S13" }, optional)
    end)
end)

describe("Progress", function()
    local ns, store, logged, calls

    local function new()
        return ns.Progress.New(store, ns.Steps, {
            log = function(kind, data, q)
                logged[#logged + 1] = { kind = kind, data = data, q = q }
            end,
            setStep = function(id)
                calls.step = id
            end,
            snapshot = function(step, phase)
                calls.snapshots[#calls.snapshots + 1] = step.id .. ":" .. phase
            end,
            onChange = function()
                calls.changes = calls.changes + 1
            end,
            onAdvance = function(step)
                calls.advanced[#calls.advanced + 1] = step.id
            end,
        })
    end

    local function kinds()
        local list = {}
        for i, entry in ipairs(logged) do
            list[i] = entry.kind
        end
        return list
    end

    local function goTo(progress, id)
        while progress:Current().id ~= id do
            progress:Done(false)
        end
    end

    local function attempt(outcome)
        return { outcome = outcome }
    end

    before_each(function()
        ns = addon.load({ "Steps.lua", "Progress.lua" })
        store = { step = "S0" }
        logged = {}
        calls = { snapshots = {}, changes = 0, advanced = {} }
    end)

    it("repairs a missing or unknown step and sets the logger step", function()
        store = { step = "S99", started = "yes" }
        local progress = new()
        assert.are.equal("S0", progress:Current().id)
        assert.is_false(progress:Started())
        assert.are.equal("S0", calls.step)
        assert.are.same({}, store.status)
    end)

    it("counts only after Start and auto-advances at the target with a cue", function()
        local progress = new()
        goTo(progress, "S3")
        assert.is_false(progress:Observe("attempt", attempt("catch")))
        assert.are.equal(0, progress:Count())
        progress:Start()
        assert.are.equal("step_start", logged[#logged].kind)
        assert.are.equal("Q06", logged[#logged].q)
        for _ = 1, 4 do
            assert.is_false(progress:Observe("attempt", attempt("catch")))
        end
        progress:Observe("attempt", attempt("cancel"))
        assert.are.equal(4, progress:Count())
        assert.is_true(progress:Observe("attempt", attempt("catch")))
        assert.are.equal("S4", progress:Current().id)
        assert.are.equal("S4", calls.step)
        assert.is_false(progress:Started())
        assert.are.same({ "S3" }, calls.advanced)
        assert.are.equal("done", progress:Status("S3"))
        local done = logged[#logged]
        assert.are.equal("step_done", done.kind)
        assert.are.same({
            step = "S3",
            started = true,
            count = 5,
            target = 5,
            kind = "catch",
            outcomes = { catch = 5, cancel = 1 },
            auto = true,
        }, done.data)
    end)

    it("counts any attempt, hovers, and checks for their targets", function()
        local progress = new()
        goTo(progress, "S5")
        progress:Start()
        progress:Observe("attempt", attempt("early_click"))
        progress:Observe("tooltip", {})
        progress:Observe("attempt", attempt("unknown"))
        assert.are.equal("S6", progress:Current().id)
        goTo(progress, "S10")
        progress:Start()
        progress:Observe("attempt", attempt("timeout"))
        progress:Observe("tooltip", {})
        assert.are.equal("S11", progress:Current().id)
        goTo(progress, "S14")
        progress:Start()
        progress:Observe("probe_check", {})
        progress:Observe("probe_check", {})
        assert.are.equal("S15", progress:Current().id)
        assert.are.same({ "S5", "S10", "S14" }, calls.advanced)
    end)

    it("ignores other log kinds and attempts without an outcome", function()
        local progress = new()
        goTo(progress, "S6")
        progress:Start()
        assert.is_false(progress:Observe("loot", { outcome = "timeout" }))
        assert.is_false(progress:Observe("attempt", "timeout"))
        assert.is_false(progress:Observe("attempt", {}))
        assert.are.equal(0, progress:Count())
    end)

    it("takes snapshots on Done for S1/S2 and on Start for S9", function()
        local progress = new()
        progress:Done(false)
        progress:Done(false)
        progress:Done(false)
        assert.are.same({ "S1:done", "S2:done" }, calls.snapshots)
        goTo(progress, "S9")
        progress:Start()
        assert.are.same({ "S1:done", "S2:done", "S9:start" }, calls.snapshots)
        assert.is_false(progress:Start())
        assert.are.equal(3, #calls.snapshots)
    end)

    it("skips with a reason and maps unknown reasons to other", function()
        local progress = new()
        goTo(progress, "S9")
        progress:Skip("no_item")
        assert.are.equal("skipped", progress:Status("S9"))
        assert.are.equal("no_item", progress:Reason("S9"))
        assert.are.equal("S10", progress:Current().id)
        local skip = logged[#logged]
        assert.are.equal("step_skip", skip.kind)
        assert.are.equal("no_item", skip.data.reason)
        assert.are.equal("Q07", skip.q)
        progress:Skip("bogus")
        assert.are.equal("other", progress:Reason("S10"))
        assert.are.same({}, calls.advanced)
    end)

    it("goes back to redo a step and resets its counters on Start", function()
        local progress = new()
        assert.is_false(progress:Back())
        goTo(progress, "S3")
        progress:Start()
        progress:Observe("attempt", attempt("catch"))
        progress:Skip("other")
        assert.is_true(progress:Back())
        assert.are.equal("S3", progress:Current().id)
        assert.are.equal("S3", calls.step)
        assert.is_false(progress:Started())
        assert.are.equal("skipped", progress:Status("S3"))
        assert.are.equal(1, progress:Count())
        progress:Start()
        assert.are.equal(0, progress:Count())
        assert.are.same({}, progress:Outcomes())
        progress:Done(false)
        assert.are.equal("done", progress:Status("S3"))
        assert.is_nil(progress:Reason("S3"))
        local back
        for _, entry in ipairs(logged) do
            if entry.kind == "step_back" then
                back = entry
            end
        end
        assert.are.same({ from = "S4", to = "S3", started = false }, back.data)
    end)

    it("resumes from the saved store after a reload", function()
        local progress = new()
        goTo(progress, "S4")
        progress:Start()
        progress:Observe("attempt", attempt("catch"))
        progress:Skip("other")
        progress:Back()
        progress:Start()
        progress:Observe("attempt", attempt("catch"))
        progress:Observe("attempt", attempt("catch"))
        local reloaded = new()
        assert.are.equal("S4", reloaded:Current().id)
        assert.is_true(reloaded:Started())
        assert.are.equal(2, reloaded:Count())
        assert.are.equal("done", reloaded:Status("S3"))
        reloaded:Observe("attempt", attempt("catch"))
        assert.are.equal("S5", reloaded:Current().id)
    end)

    it("stays on the last step and reports the run as finished", function()
        local progress = new()
        goTo(progress, "S15")
        assert.is_false(progress:Finished())
        progress:Done(false)
        assert.are.equal("S15", progress:Current().id)
        assert.is_true(progress:Finished())
        assert.are.equal(16, #kinds())
    end)

    it("builds checklist rows with status, reason, optional, and current", function()
        local progress = new()
        progress:Done(false)
        progress:Skip("no_location")
        local rows = progress:Checklist()
        assert.are.equal(16, #rows)
        assert.are.same({
            id = "S0",
            title = "Login snapshot",
            status = "done",
            optional = false,
            current = false,
        }, rows[1])
        assert.are.equal("no_location", rows[2].reason)
        assert.is_true(rows[3].current)
        assert.are.equal("open", rows[3].status)
        assert.is_true(rows[12].optional)
    end)

    it("resets the whole run to S0 and keeps window position and first-login flag", function()
        store.window = { point = "TOP", x = 1, y = 2 }
        store.autoOpened = true
        local progress = new()
        progress:Done(false)
        progress:Skip("no_item")
        goTo(progress, "S3")
        progress:Start()
        progress:Observe("attempt", attempt("catch"))
        local changes = calls.changes
        progress:Reset()
        assert.are.equal("S0", progress:Current().id)
        assert.is_false(progress:Started())
        assert.are.equal("S0", calls.step)
        assert.are.equal(changes + 1, calls.changes)
        for _, field in ipairs(ns.Progress.TABLE_FIELDS) do
            assert.are.same({}, store[field])
        end
        assert.are.equal("open", progress:Status("S1"))
        assert.are.equal(0, progress:Count("S3"))
        assert.are.same({ point = "TOP", x = 1, y = 2 }, store.window)
        assert.is_true(store.autoOpened)
    end)

    it("works without optional callbacks", function()
        local progress = ns.Progress.New({}, ns.Steps, {
            log = function() end,
        })
        progress:Done(false)
        goTo(progress, "S3")
        progress:Start()
        for _ = 1, 5 do
            progress:Observe("attempt", attempt("catch"))
        end
        assert.are.equal("S4", progress:Current().id)
    end)
end)
