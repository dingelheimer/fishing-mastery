-- Pure logic: per-question summary (Q01-Q32) of the log for /fmp report. Status per question:
-- answered (enough entries, complete), partial (some entries), skipped (no entries and every
-- linked step skipped), missing (no entries).
local _, ns = ...

local ipairs, pairs, pcall, format, concat = ipairs, pairs, pcall, string.format, table.concat
local sub, sort = string.sub, table.sort
local L = ns.L

local Report = {}
ns.Report = Report

Report.STATUSES = { "answered", "partial", "skipped", "missing" }
Report.MAX_VALUE = 160 -- characters of the key value per question

-- Step IDs per question, from the step data.
function Report.LinkedSteps(steps)
    local byQ = {}
    for _, step in ipairs(steps.list) do
        for _, q in ipairs(step.questions or {}) do
            byQ[q] = byQ[q] or {}
            byQ[q][#byQ[q] + 1] = step.id
        end
    end
    return byQ
end

local function allSkipped(stepIds, status)
    if not stepIds or #stepIds == 0 then
        return false
    end
    for _, id in ipairs(stepIds) do
        if status(id) ~= "skipped" then
            return false
        end
    end
    return true
end

-- Runs a rule function protected: a broken rule or odd log data gives "error", not a failure.
local function safe(fn, list, fallback)
    if not fn then
        return true, fallback
    end
    local ok, result = pcall(fn, list)
    if not ok then
        return false, nil
    end
    return true, result
end

local function row(rule, list, linked, status)
    local result = { q = rule.q, count = #list, steps = linked }
    if #list == 0 then
        result.status = allSkipped(linked, status) and "skipped" or "missing"
        return result
    end
    local okComplete, complete = safe(rule.complete, list, true)
    local okValue, value = safe(rule.value, list, nil)
    if okValue and value ~= nil then
        result.value = sub(value, 1, Report.MAX_VALUE)
    end
    if not okComplete or not okValue then
        result.ruleError = true
    end
    local enough = #list >= (rule.min or 1)
    local answered = enough and okComplete and okValue and complete
    result.status = answered and "answered" or "partial"
    return result
end

-- entries: log entries. opts: { rules = ReportRules.list, steps = ns.Steps,
-- status(stepId) -> "open" / "done" / "skipped" }. Returns { rows, totals, entries }.
function Report.Build(entries, opts)
    local rules = {}
    for _, rule in ipairs(opts.rules) do
        rules[#rules + 1] = rule
    end
    sort(rules, function(a, b)
        return a.q < b.q
    end)
    local lists = {}
    for _, rule in ipairs(rules) do
        lists[rule.q] = {}
    end
    for _, entry in ipairs(entries) do
        if entry.kind ~= "report" then
            for _, rule in ipairs(rules) do
                local ok, matched = pcall(rule.match, entry)
                if ok and matched then
                    local list = lists[rule.q]
                    list[#list + 1] = entry
                end
            end
        end
    end
    local linked = Report.LinkedSteps(opts.steps)
    local totals = {}
    for _, name in ipairs(Report.STATUSES) do
        totals[name] = 0
    end
    local rows = {}
    for i, rule in ipairs(rules) do
        rows[i] = row(rule, lists[rule.q], linked[rule.q], opts.status)
        totals[rows[i].status] = totals[rows[i].status] + 1
    end
    return { rows = rows, totals = totals, entries = #entries }
end

-- Compact form for the log entry: rows without the linked step lists.
function Report.LogData(report)
    local rows = {}
    for i, r in ipairs(report.rows) do
        rows[i] = { q = r.q, status = r.status, count = r.count, value = r.value }
        if r.ruleError then
            rows[i].ruleError = true
        end
    end
    local data = { totals = {}, entries = report.entries, rows = rows }
    for name, n in pairs(report.totals) do
        data.totals[name] = n
    end
    return data
end

-- Plain text for the report window: a totals line, then one line per question.
function Report.Text(report)
    local t = report.totals
    local lines = {
        format(L.REPORT_TOTALS, t.answered, t.partial, t.skipped, t.missing, report.entries),
        "",
    }
    for _, r in ipairs(report.rows) do
        local value = r.value or (r.steps and concat(r.steps, ", ") or "")
        if not r.value and value ~= "" then
            value = format(L.REPORT_STEPS, value)
        end
        lines[#lines + 1] = format(L.REPORT_LINE, r.q, L["REPORT_" .. r.status], r.count, value)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.REPORT_FOOTER
    return concat(lines, "\n")
end
