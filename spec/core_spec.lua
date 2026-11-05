-- Boot test: loads every file in TOC order against the fake UI and drives the client events,
-- the slash command, and the window, so wiring errors in Core.lua show up without the game.
local fakeui = require("spec.helpers.fakeui")

local ADDON = "FishingMasteryProbe"
local STUBS = {
    "CreateFrame",
    "UIParent",
    "GetServerTime",
    "GetTimePreciseSec",
    "DEFAULT_CHAT_FRAME",
    "SlashCmdList",
    "SLASH_FMP1",
    "FishingMasteryProbeDB",
    "SOUNDKIT",
    "PlaySound",
    "SPELL_FAILED_NOT_FISHABLE",
    "InCombatLockdown",
    "SetOverrideBindingClick",
    "ClearOverrideBindings",
    "GetProfessions",
    "GetProfessionInfo",
    "UnitName",
    "C_ChatInfo",
}

-- True when any key or value in a logged table contains the text.
local function contains(value, text)
    if type(value) == "table" then
        for key, child in pairs(value) do
            if contains(key, text) or contains(child, text) then
                return true
            end
        end
        return false
    end
    return tostring(value):find(text, 1, true) ~= nil
end

local function tocFiles()
    local files = {}
    for line in io.lines(ADDON .. "/" .. ADDON .. ".toc") do
        if line:match("%.lua%s*$") then
            files[#files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    return files
end

describe("Core boot", function()
    local env, ns, printed, sounds, clock

    local function fire(event, ...)
        for _, frame in ipairs(env.frames) do
            frame:Fire(event, ...)
        end
    end

    -- tick: seconds the fake clock advances per GetTimePreciseSec call (default 1).
    local function boot(saved, tick)
        env = fakeui.new()
        printed, sounds, clock = {}, {}, 1000
        _G.CreateFrame = env.CreateFrame
        _G.UIParent = env.UIParent
        _G.GetServerTime = function()
            return 1793836800
        end
        _G.GetTimePreciseSec = function()
            clock = clock + (tick or 1)
            return clock
        end
        _G.DEFAULT_CHAT_FRAME = {
            AddMessage = function(_, text)
                printed[#printed + 1] = text
            end,
        }
        _G.SlashCmdList = {}
        _G.SOUNDKIT = { READY_CHECK = 8960 }
        _G.PlaySound = function(id)
            sounds[#sounds + 1] = id
        end
        _G.FishingMasteryProbeDB = saved
        ns = {}
        for _, file in ipairs(tocFiles()) do
            assert(loadfile(ADDON .. "/" .. file))(ADDON, ns)
        end
        fire("ADDON_LOADED", ADDON)
        fire("PLAYER_LOGIN")
        fire("PLAYER_ENTERING_WORLD", true, false)
    end

    after_each(function()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
    end)

    it("loads every TOC file, logs in without errors, and opens the window once", function()
        boot(nil)
        assert.are.equal(0, ns.Guard.errors)
        assert.is_table(ns.progress)
        assert.is_table(ns.window)
        assert.is_true(ns.window.frame:IsShown())
        assert.is_true(_G.FishingMasteryProbeDB.progress.autoOpened)
        assert.truthy(ns.window.lines.extra:GetText():find("entries", 1, true))

        local saved = _G.FishingMasteryProbeDB
        boot(saved)
        assert.is_nil(ns.window)
        _G.SlashCmdList.FMP("")
        assert.is_true(ns.window.frame:IsShown())
        _G.SlashCmdList.FMP("")
        assert.is_false(ns.window.frame:IsShown())
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("runs steps from the window and counts recorder attempts", function()
        boot(nil)
        fakeui.button(env, "Done"):Click()
        fakeui.button(env, "Done"):Click()
        local context
        for _, entry in ipairs(_G.FishingMasteryProbeDB.log.entries) do
            if entry.kind == "context" then
                context = entry
            end
        end
        assert.are.equal("S1", context.step)
        assert.are.equal("Q07", context.q)
        assert.are.equal("done", context.data.phase)
        assert.are.equal("S2", ns.logger.step)

        _G.FishingMasteryProbeDB.progress.step = "S8"
        boot(_G.FishingMasteryProbeDB)
        assert.are.equal("S8", ns.logger.step)
        _G.SlashCmdList.FMP("")
        fakeui.button(env, "Start"):Click()
        -- An invalid-target message without a channel forms an attempt on its own.
        _G.SPELL_FAILED_NOT_FISHABLE = "Your cast didn't land in fishable water"
        fire("UI_ERROR_MESSAGE", 1, _G.SPELL_FAILED_NOT_FISHABLE)
        assert.are.equal("invalid_target", ns.recorders.stats.last)
        assert.are.equal("S9", ns.progress:Current().id)
        assert.are.same({ 8960 }, sounds)
        assert.are.equal(0, ns.Guard.errors)

        _G.SlashCmdList.FMP("status")
        assert.truthy(printed[#printed]:find("Guided run: step S9 (not started)", 1, true))
    end)

    it("runs both S14 helper tests from the window and removes the key", function()
        local bindings, sent = {}, {}
        _G.InCombatLockdown = function()
            return false
        end
        _G.SetOverrideBindingClick = function(owner, _, key)
            bindings[key] = owner
        end
        _G.ClearOverrideBindings = function()
            bindings = {}
        end
        _G.GetProfessions = function()
            return nil, nil, nil, 4
        end
        _G.GetProfessionInfo = function()
            return "Fishing"
        end
        _G.UnitName = function()
            return "Testchar"
        end
        _G.C_ChatInfo = {
            RegisterAddonMessagePrefix = function()
                return true
            end,
            SendAddonMessage = function(...)
                sent[#sent + 1] = { ... }
            end,
        }
        boot({ progress = { step = "S14", autoOpened = true } }, 0.001)
        _G.SlashCmdList.FMP("")
        local enable = fakeui.button(env, "Enable test key")
        assert.is_true(enable:IsShown())
        assert.is_false(enable:Click()) -- disabled until Start
        fakeui.button(env, "Start"):Click()
        assert.is_true(enable:Click())
        assert.is_table(bindings["CTRL-SHIFT-F"])
        assert.truthy(ns.window.lines.extra:GetText():find("is active", 1, true))

        bindings["CTRL-SHIFT-F"]:PressKey(true)
        fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-guid", 7620)
        assert.is_nil(next(bindings))
        assert.are.equal(1, ns.progress:Count("S14"))

        fakeui.button(env, "Send self-whisper"):Click()
        assert.are.equal("Testchar", sent[1][4])
        fire("CHAT_MSG_ADDON", "FMProbe", "FMProbe self-test 1", "WHISPER", "Testchar")
        assert.are.equal("S15", ns.progress:Current().id)
        assert.are.equal("done", ns.progress:Status("S14"))
        assert.is_false(enable:IsShown())
        assert.are.equal(0, ns.Guard.errors)

        local checks = {}
        for _, entry in ipairs(_G.FishingMasteryProbeDB.log.entries) do
            if entry.kind == "probe_check" then
                checks[#checks + 1] = entry.data.test
            end
            assert.is_false(contains(entry.data, "Testchar"))
        end
        assert.are.same({ "S14a", "S14b" }, checks)

        -- Logout removes a key that is still enabled.
        ns.progress:Back()
        ns.progress:Start()
        enable:Click()
        assert.is_table(bindings["CTRL-SHIFT-F"])
        fire("PLAYER_LOGOUT")
        assert.is_nil(next(bindings))
    end)

    it("reports, exports, and resets the log through /fmp", function()
        boot(nil)
        fakeui.button(env, "Done"):Click() -- S0 done
        local entries = _G.FishingMasteryProbeDB.log.entries
        local before = #entries

        _G.SlashCmdList.FMP("report")
        local report = entries[#entries]
        assert.are.equal("report", report.kind)
        assert.are.equal(before + 1, #entries)
        assert.are.equal(32, #report.data.rows)
        local t = report.data.totals
        assert.are.equal(32, t.answered + t.partial + t.skipped + t.missing)
        assert.truthy(printed[#printed]:find("Report: ", 1, true))
        local window = ns.textWindow
        assert.is_true(window:IsShown())
        assert.truthy(window:Text():find("Q01  ", 1, true))
        assert.truthy(window:Text():find("Q32  ", 1, true))
        assert.is_false(window.nextButton:IsShown()) -- one page only

        -- The text is read-only and can be selected for copying.
        local text = window:Text()
        window.edit:Type("typed over")
        assert.are.equal(text, window:Text())
        fakeui.button(env, "Select all"):Click()
        assert.is_true(window.edit.highlighted)
        assert.is_true(window.edit.focused)

        _G.SlashCmdList.FMP("export")
        local lines = 0
        for _ in window:Text():gmatch("[^\n]+") do
            lines = lines + 1
        end
        assert.are.equal(#entries + 1, lines) -- header + one line per entry
        assert.truthy(window:Text():find('"report"', 1, true))

        -- Reset asks first; Cancel keeps everything.
        _G.SlashCmdList.FMP("reset")
        assert.is_true(ns.confirm.frame:IsShown())
        ns.confirm.no:Click()
        assert.is_false(ns.confirm.frame:IsShown())
        assert.are.equal(before + 1, #_G.FishingMasteryProbeDB.log.entries)

        _G.SlashCmdList.FMP("reset")
        ns.confirm.yes:Click()
        local log = _G.FishingMasteryProbeDB.log
        assert.are.equal(0, log.dropped)
        assert.are.equal("log_reset", log.entries[1].kind)
        assert.are.equal(before + 1, log.entries[1].data.removed)
        assert.are.equal("snapshot", log.entries[2].kind) -- environment recorded again
        assert.are.equal("S0", log.entries[2].step)
        assert.are.equal("S0", ns.progress:Current().id)
        assert.are.equal("open", ns.progress:Status("S0"))
        assert.is_false(window:IsShown())
        assert.truthy(printed[#printed]:find("Log cleared", 1, true))
        assert.are.equal(0, ns.Guard.errors)

        -- Help lists the new commands.
        _G.SlashCmdList.FMP("help")
        local help = table.concat(printed, "\n")
        for _, name in ipairs({ "report", "export", "reset" }) do
            assert.truthy(help:find("/fmp " .. name, 1, true), name)
        end
    end)

    it("pages a long export", function()
        boot(nil)
        for i = 1, 3000 do
            ns.logger:Log("event", { name = "UNIT_AURA", n = i, pad = string.rep("x", 100) })
        end
        _G.SlashCmdList.FMP("export")
        local window = ns.textWindow
        assert.is_true(window.nextButton:IsShown())
        assert.is_false(window.prevButton:IsEnabled())
        local first = window:Text()
        window.nextButton:Click()
        assert.are_not.equal(first, window:Text())
        assert.truthy(window.pageText:GetText():find("Page 2 of", 1, true))
        assert.is_true(window.prevButton:IsEnabled())
        assert.are.equal(0, ns.Guard.errors)
    end)
end)
