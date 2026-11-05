-- Pure logic: guided test run progression over the saved progress table (db.progress).
-- Store fields: step, started, status[id], counts[id], outcomes[id], reasons[id].
-- Counting only happens while the current step is started; reaching a target finishes the step.
local _, ns = ...

local setmetatable, type, ipairs = setmetatable, type, ipairs

local Progress = {}
Progress.__index = Progress
ns.Progress = Progress

Progress.SKIP_REASONS = { no_item = true, no_location = true, other = true, optional = true }
Progress.TABLE_FIELDS = { "status", "counts", "outcomes", "reasons" }

-- Counter keys fed by a log entry: attempts count as "attempt" and as their outcome.
function Progress.CounterKeys(kind, data)
    if kind == "attempt" and type(data) == "table" then
        return "attempt", data.outcome
    elseif kind == "tooltip" then
        return "hover"
    elseif kind == "probe_check" then
        return "check"
    end
    return nil
end

local function repair(store, steps)
    if not steps.byId[store.step] then
        store.step = steps.list[1].id
        store.started = false
    end
    store.started = store.started == true
    for _, field in ipairs(Progress.TABLE_FIELDS) do
        if type(store[field]) ~= "table" then
            store[field] = {}
        end
    end
end

local function noop() end

-- store: db.progress. steps: ns.Steps. deps: { log(kind, data, q), setStep(id),
-- snapshot(step, phase), onChange(), onAdvance(step) }; all but log are optional.
function Progress.New(store, steps, deps)
    repair(store, steps)
    local self = setmetatable({
        store = store,
        steps = steps,
        log = deps.log,
        setStep = deps.setStep or noop,
        snapshot = deps.snapshot or noop,
        onChange = deps.onChange or noop,
        onAdvance = deps.onAdvance or noop,
    }, Progress)
    self.setStep(store.step)
    return self
end

function Progress:Current()
    return self.steps.byId[self.store.step]
end

function Progress:Started()
    return self.store.started
end

function Progress:Count(id)
    return self.store.counts[id or self.store.step] or 0
end

function Progress:Outcomes(id)
    return self.store.outcomes[id or self.store.step] or {}
end

-- "open", "done", or "skipped".
function Progress:Status(id)
    return self.store.status[id] or "open"
end

function Progress:Reason(id)
    return self.store.reasons[id]
end

-- True when no step is open any more.
function Progress:Finished()
    for _, step in ipairs(self.steps.list) do
        if self:Status(step.id) == "open" then
            return false
        end
    end
    return true
end

local function question(step)
    return step.questions and step.questions[1]
end

local function moveTo(self, step)
    self.store.step = step.id
    self.store.started = false
    self.setStep(step.id)
end

-- Moves to the next step; the last step stays current but is no longer started.
local function advance(self, step)
    local nextStep = self.steps.list[step.index + 1]
    if nextStep then
        moveTo(self, nextStep)
    else
        self.store.started = false
    end
end

local function summary(self, step)
    return {
        step = step.id,
        started = self.store.started,
        count = self:Count(step.id),
        target = step.target and step.target.count,
        kind = step.target and step.target.kind,
        outcomes = self:Outcomes(step.id),
    }
end

-- Starts counting for the current step; a restart (after Back) resets its counters.
function Progress:Start()
    local step = self:Current()
    if self.store.started then
        return false
    end
    self.store.started = true
    self.store.counts[step.id] = 0
    self.store.outcomes[step.id] = {}
    self.log("step_start", { step = step.id, target = step.target }, question(step))
    if step.snapshot == "start" then
        self.snapshot(step, "start")
    end
    self.onChange()
    return true
end

-- Finishes the current step. auto = true when the target was reached.
function Progress:Done(auto)
    local step = self:Current()
    if step.snapshot == "done" then
        self.snapshot(step, "done")
    end
    local data = summary(self, step)
    data.auto = auto == true
    self.log("step_done", data, question(step))
    self.store.status[step.id] = "done"
    self.store.reasons[step.id] = nil
    advance(self, step)
    if auto then
        self.onAdvance(step)
    end
    self.onChange()
    return true
end

-- Skips the current step with one of SKIP_REASONS (unknown reasons become "other").
function Progress:Skip(reason)
    local step = self:Current()
    if not Progress.SKIP_REASONS[reason] then
        reason = "other"
    end
    local data = summary(self, step)
    data.reason = reason
    self.log("step_skip", data, question(step))
    self.store.status[step.id] = "skipped"
    self.store.reasons[step.id] = reason
    advance(self, step)
    self.onChange()
    return true
end

-- Goes back one step to redo it. Its status stays until it is done or skipped again.
function Progress:Back()
    local step = self:Current()
    local previous = self.steps.list[step.index - 1]
    if not previous then
        return false
    end
    self.log("step_back", { from = step.id, to = previous.id, started = self.store.started })
    moveTo(self, previous)
    self.onChange()
    return true
end

-- Clears the whole run (statuses, counters, skip reasons) and returns to the first step.
-- Window position and the first-login flag are kept. Used by /fmp reset.
function Progress:Reset()
    for _, field in ipairs(Progress.TABLE_FIELDS) do
        self.store[field] = {}
    end
    moveTo(self, self.steps.list[1])
    self.onChange()
end

-- Feeds a log entry. Returns true when it finished the current step.
function Progress:Observe(kind, data)
    if not self.store.started then
        return false
    end
    local key, outcome = Progress.CounterKeys(kind, data)
    if not key then
        return false
    end
    local step = self:Current()
    if key == "attempt" and type(outcome) == "string" then
        local outcomes = self.store.outcomes[step.id] or {}
        self.store.outcomes[step.id] = outcomes
        outcomes[outcome] = (outcomes[outcome] or 0) + 1
    end
    local target = step.target
    if target and (target.kind == key or target.kind == outcome) then
        local count = self:Count(step.id) + 1
        self.store.counts[step.id] = count
        if count >= target.count then
            return self:Done(true)
        end
    end
    self.onChange()
    return false
end

-- Overview rows: { id, title, status, reason, optional, current }.
function Progress:Checklist()
    local rows, currentId = {}, self.store.step
    for i, step in ipairs(self.steps.list) do
        rows[i] = {
            id = step.id,
            title = step.title,
            status = self:Status(step.id),
            reason = self:Reason(step.id),
            optional = step.optional == true,
            current = step.id == currentId,
        }
    end
    return rows
end
