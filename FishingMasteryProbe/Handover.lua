-- /fmp report, /fmp export, and /fmp reset: summarize the log, show it for copying, and clear it
-- after a confirmation. Windows are created on first use.
local _, ns = ...

local format, _G = string.format, _G
local L = ns.L

local Handover = {}
ns.Handover = Handover

local function textWindow()
    if not ns.textWindow then
        ns.textWindow = ns.TextWindow.Create(_G, ns.db.progress)
    end
    return ns.textWindow
end

local function ready()
    if not (ns.logger and ns.progress) then
        ns.Print(L.NOT_READY)
        return false
    end
    return true
end

-- Builds the report from the whole log and stores it as a "report" entry.
function Handover.Report()
    local progress = ns.progress
    local report = ns.Report.Build(ns.logger.store.entries, {
        rules = ns.ReportRules.list,
        steps = ns.Steps,
        status = function(id)
            return progress:Status(id)
        end,
    })
    ns.logger:Log("report", ns.Report.LogData(report))
    return report
end

-- Clears the log and the guided run, then records the environment again (step S0).
function Handover.Reset()
    local store = ns.logger.store
    local removed = #store.entries
    store.entries, store.dropped = {}, 0
    if ns.recorders then
        ns.recorders.stats = { total = 0, byOutcome = {} }
    end
    ns.progress:Reset()
    ns.logger:Log("log_reset", {
        removed = removed,
        sessionId = store.sessionId,
        probeVersion = store.probeVersion,
    })
    if ns.RunSnapshot then
        ns.RunSnapshot()
    end
    return removed
end

ns.Commands.Register("report", L.CMD_REPORT, function()
    if not ready() then
        return
    end
    local report = Handover.Report()
    local t = report.totals
    ns.Print(format(L.REPORT_PRINT, t.answered, t.partial, t.skipped, t.missing))
    textWindow():Open(L.REPORT_TITLE, L.REPORT_HINT, { ns.Report.Text(report) })
end)

ns.Commands.Register("export", L.CMD_EXPORT, function()
    if not ready() then
        return
    end
    local pages = ns.Export.Pages(ns.logger.store)
    ns.Print(format(L.EXPORT_PRINT, ns.logger:Count(), #pages))
    textWindow():Open(L.EXPORT_TITLE, L.EXPORT_HINT, pages)
end)

ns.Commands.Register("reset", L.CMD_RESET, function()
    if not ready() then
        return
    end
    if not ns.confirm then
        ns.confirm = ns.Confirm.Create(_G)
    end
    ns.confirm:Ask(format(L.RESET_QUESTION, ns.logger:Count()), L.BUTTON_RESET, function()
        local removed = Handover.Reset()
        if ns.textWindow then
            ns.textWindow.frame:Hide()
        end
        ns.Print(format(L.RESET_DONE, removed))
    end)
end)
