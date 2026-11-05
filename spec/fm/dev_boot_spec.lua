-- Boot tests for the developer tools: hidden without the dev flag, the stress test in steps,
-- load measurement across /reload, the line check, and the raw capture.
local fmboot = require("spec.helpers.fmboot")

local GUID = fmboot.GUID

describe("FishingMastery dev tools boot", function()
    local w

    before_each(function()
        w = fmboot.new()
    end)

    after_each(function()
        w.cleanup()
    end)

    local function devBoot()
        w.boot({ schemaVersion = 1, chars = {}, settings = { dev = true } }, nil)
        w.fire("PLAYER_ENTERING_WORLD", true, false)
    end

    -- Runs the due timers until the test history holds its target.
    local function runAll()
        local entry = _G.FishingMasteryDB.dev.stress
        local guard = 0
        while entry.written < entry.target do
            w.runTimers(w.clock)
            guard = guard + 1
            assert.is_true(guard < 1000)
        end
    end

    local function reload(clockAfter)
        w.fire("PLAYER_LOGOUT")
        w.bootClock = clockAfter
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
    end

    it("is hidden and unavailable without the dev flag", function()
        w.boot(nil, nil)
        _G.SlashCmdList.FM("")
        assert.is_nil(w.output():find("/fm dev", 1, true))
        w.printed = {}
        _G.SlashCmdList.FM("dev stress")
        assert.truthy(w.output():find("Unknown command: dev", 1, true))
        w.fire("PLAYER_LOGOUT")
        assert.is_nil(_G.FishingMasteryDB.dev)
    end)

    it("writes the test history in steps without touching real characters", function()
        devBoot()
        w.catch(5000, 8)
        local before = w.ns.Db.DeepCopy(_G.FishingMasteryDB.chars)
        _G.SlashCmdList.FM("")
        assert.truthy(w.output():find("/fm dev", 1, true))

        _G.SlashCmdList.FM("dev stress 12000")
        local entry = _G.FishingMasteryDB.dev.stress
        assert.are.equal(5000, entry.written)
        runAll()
        assert.are.equal(12000, entry.written)
        assert.are.same({}, entry.casts)
        assert.truthy(w.output():find("Test history ready: 12000 casts", 1, true))
        assert.are.same(before, _G.FishingMasteryDB.chars)

        w.printed = {}
        _G.SlashCmdList.FM("dev stress")
        assert.truthy(w.output():find("already present", 1, true))
        _G.SlashCmdList.FM("dev stress 0")
        assert.truthy(w.output():find("n from 1 to 500000", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("packs a test history that is still being written at logout", function()
        devBoot()
        _G.SlashCmdList.FM("dev stress 12000")
        reload(6000)
        local entry = _G.FishingMasteryDB.dev.stress
        assert.are.equal(5000, entry.written)
        assert.are.same({}, entry.casts)
        assert.is_true(#entry.days > 0)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("measures the reload and checks the test history and line chunks", function()
        devBoot()
        reload(5002.25)
        assert.truthy(w.output():find("Load: 2.250 s from logout to ADDON_LOADED", 1, true))
        assert.truthy(
            w.output():find("in 0 steps (longest 0.0 ms; 0 casts, 0 characters)", 1, true)
        )

        _G.SlashCmdList.FM("dev stress 30000")
        runAll()
        _G.SlashCmdList.FM("dev lines")
        assert.truthy(w.output():find("Line test chunks written", 1, true))
        w.clock = 7000
        reload(7001.5)
        local dev = _G.FishingMasteryDB.dev
        local chunks = #dev.stress.days
        assert.is_true(chunks > 100)
        assert.truthy(w.output():find("Line check: %d+%-character chunk: loaded and decoded"))
        -- The stress check runs one step of 10 chunks per frame; the load line follows at the end.
        assert.is_nil(w.output():find("Load: 1.500 s", 1, true))
        assert.are.equal(1, #dev.loads)
        local frames = 0
        while not w.output():find("Load: 1.500 s", 1, true) do
            w.runTimers(w.clock)
            frames = frames + 1
            assert.is_true(frames < 100)
        end
        assert.are.equal(math.ceil(chunks / 10) - 1, frames)
        local steps = math.ceil(chunks / 10)
        assert.truthy(w.output():find("in " .. steps .. " steps", 1, true))
        assert.truthy(w.output():find("; 30000 casts,", 1, true))
        assert.are.equal(2, #dev.loads)
        assert.is_nil(dev.logoutAt)

        w.printed = {}
        _G.SlashCmdList.FM("dev load")
        assert.truthy(w.output():find("Load: 2.250 s", 1, true))
        _G.SlashCmdList.FM("dev clear")
        assert.is_nil(dev.stress)
        assert.is_nil(dev.lines)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("says when the clock was reset between logout and load", function()
        devBoot()
        w.clock = 9000
        reload(10)
        assert.truthy(w.output():find("no reload time", 1, true))
    end)

    it("captures aura IDs at cast start and loot sources only when switched on", function()
        devBoot()
        w.game.auras = { 1234, 5678 }
        w.catch(5000, 8)
        assert.is_nil((_G.FishingMasteryDB.dev or {}).capture)

        _G.SlashCmdList.FM("dev capture on")
        w.game.modifier = 25
        w.catch(5020, 8)
        local capture = _G.FishingMasteryDB.dev.capture
        assert.are.equal(2, #capture.entries)
        local cast, loot = capture.entries[1], capture.entries[2]
        assert.are.same({ 1234, 5678 }, cast.auras)
        assert.are.equal(25, cast.mod)
        assert.are.same({ "GameObject:35591" }, loot.src)
        -- No names, aura casters, or GUIDs are kept.
        local saved = require("spec.helpers.synthetic").write("X", capture)
        assert.is_nil(saved:find("party1", 1, true))
        assert.is_nil(saved:find("Player-", 1, true))
        assert.is_nil(saved:find("0000ABCD", 1, true))

        w.printed = {}
        _G.SlashCmdList.FM("dev capture")
        assert.truthy(
            w.output():find("Raw capture on: 2 of 2000 entries (1 casts, 1 loots)", 1, true)
        )
        assert.truthy(w.output():find("1234 x1, 5678 x1", 1, true))

        _G.SlashCmdList.FM("dev capture off")
        w.catch(5040, 8)
        assert.are.equal(2, #capture.entries)
        assert.are.equal(GUID, next(_G.FishingMasteryDB.chars))
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
