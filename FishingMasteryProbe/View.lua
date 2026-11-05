-- Pure logic: turns the progress state into the texts and button states the window shows.
local _, ns = ...

local format, concat, ipairs = string.format, table.concat, ipairs
local L = ns.L

local View = {}
ns.View = View

View.COUNTER_LABELS = {
    catch = "Catches",
    attempt = "Attempts",
    timeout = "Timeouts",
    cancel = "Cancels",
    getaway = "Get-aways",
    hover = "Hovers",
    check = "Checks",
}

View.STATUS_LABELS = { open = "Open", done = "Done", skipped = "Skipped" }

-- "Catches: 3 / 5" for steps with a target, else nil.
function View.Counter(progress)
    local target = progress:Current().target
    if not target then
        return nil
    end
    local label = L[View.COUNTER_LABELS[target.kind] or target.kind]
    return format(L.COUNTER, label, progress:Count(), target.count)
end

-- S14 helper test lines from Helpers:Status(); a finished test shows its result.
function View.Helpers(status)
    if not status then
        return { L.HELPERS_PENDING }
    end
    local key = "KEY_" .. status.key
    if status.key == "done" then
        key = status.keyResult and "KEY_done_yes" or "KEY_done_no"
    end
    local whisper = "WHISPER_" .. status.whisper
    if status.whisper == "done" then
        whisper = status.whisperResult and "WHISPER_done_yes" or "WHISPER_done_no"
    end
    return { format(L[key], status.keyName), L[whisper] }
end

-- info: { snapshot = { count, supported } or nil, events = number of planned events,
-- helpers = Helpers:Status() or nil }.
local function extraLines(step, info)
    local lines = {}
    if step.helpers then
        for _, line in ipairs(View.Helpers(info and info.helpers)) do
            lines[#lines + 1] = line
        end
    end
    if step.showSnapshot then
        local snapshot = info and info.snapshot
        if snapshot then
            lines[#lines + 1] =
                format(L.SNAPSHOT, snapshot.count or 0, snapshot.supported or 0, info.events or 0)
        else
            lines[#lines + 1] = L.SNAPSHOT_PENDING
        end
    end
    if step.showLogPath then
        lines[#lines + 1] = L.LOG_PATH
        lines[#lines + 1] = L.LOG_PATH_VALUE
    end
    return concat(lines, "\n")
end

local function stateLine(progress, step)
    if progress:Finished() then
        return L.RUN_COMPLETE
    end
    local status = progress:Status(step.id)
    if status ~= "open" then
        return format(L.STEP_STATUS, L[View.STATUS_LABELS[status]])
    end
    if step.target and not progress:Started() then
        return L.PRESS_START
    end
    return ""
end

-- Everything the main window renders for the current step.
function View.Step(progress, info)
    local step = progress:Current()
    local total = #progress.steps.list
    local title = L[step.title]
    if step.optional then
        title = title .. " " .. L.OPTIONAL_TAG
    end
    return {
        id = step.id,
        header = format(L.STEP_HEADER, step.id, step.index, total),
        title = title,
        instruction = L[step.instruction],
        counter = View.Counter(progress) or "",
        state = stateLine(progress, step),
        extra = extraLines(step, info),
        prereq = format(L.PREREQ, L[step.prereq]),
        why = format(L.WHY, L[step.why]),
        questions = format(L.QUESTIONS, concat(step.questions, ", ")),
        optional = step.optional == true,
        buttons = {
            start = step.target ~= nil,
            startEnabled = step.target ~= nil and not progress:Started(),
            back = step.index > 1,
            -- Helper tests only count after Start, so their buttons wait for it.
            helpers = step.helpers == true,
            helpersEnabled = step.helpers == true and progress:Started(),
        },
    }
end

-- One text line per step for the checklist overview: { text, status, current }.
function View.Checklist(progress)
    local lines = {}
    for i, row in ipairs(progress:Checklist()) do
        local status = L[View.STATUS_LABELS[row.status]]
        if row.reason then
            status = format(L.SKIP_STATUS, status, L["SKIP_" .. row.reason])
        end
        local title = L[row.title]
        if row.optional then
            title = title .. " " .. L.OPTIONAL_TAG
        end
        lines[i] = {
            text = format(L.CHECKLIST_LINE, row.current and ">" or " ", row.id, title, status),
            status = row.status,
            current = row.current,
        }
    end
    return lines
end
