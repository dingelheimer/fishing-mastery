-- Event bus for the recorders: one frame, a dispatch table, and player-only unit events.
-- Events whose registration failed in the login snapshot are skipped and reported.
local _, ns = ...

local setmetatable, pcall, pairs, ipairs, sort = setmetatable, pcall, pairs, ipairs, table.sort
local isSecret = issecretvalue or function()
    return false
end

local Events = {}
Events.__index = Events
ns.Events = Events

-- frame: a WoW frame (or a test double with RegisterEvent and optional RegisterUnitEvent).
-- support: { [event] = bool } from the login snapshot; nil means "try every event".
function Events.New(frame, support)
    return setmetatable({
        frame = frame,
        support = support,
        handlers = {},
        units = {},
        skipped = {},
        failed = {},
    }, Events)
end

local function register(self, event, unit)
    local frame = self.frame
    if unit and frame.RegisterUnitEvent then
        local ok, result = pcall(frame.RegisterUnitEvent, frame, event, unit)
        if ok and result ~= false then
            return true
        end
    end
    local ok, result = pcall(frame.RegisterEvent, frame, event)
    return ok and result ~= false, not ok and result or nil
end

-- Subscribes fn(event, ...) to an event. unit limits unit events to one unit ("player").
-- Returns false when the event is unsupported or registration failed.
function Events:On(event, fn, unit)
    if self.support and self.support[event] == false then
        self.skipped[event] = true
        return false
    end
    local list = self.handlers[event]
    if not list then
        local ok, err = register(self, event, unit)
        if not ok then
            self.failed[event] = err or "returned false"
            return false
        end
        list = {}
        self.handlers[event] = list
        self.units[event] = unit
    end
    list[#list + 1] = fn
    return true
end

-- Calls every handler of the event through Guard; unit events of other units are dropped.
function Events:Dispatch(event, ...)
    local list = self.handlers[event]
    if not list then
        return
    end
    local unit = self.units[event]
    local first = ...
    if unit and (isSecret(first) or first ~= unit) then
        return
    end
    for _, fn in ipairs(list) do
        ns.Guard.Call("event:" .. event, fn, event, ...)
    end
end

-- Lists subscribed, skipped, and failed events for the log.
function Events:Summary()
    local summary = { subscribed = {}, skipped = {}, failed = self.failed }
    for event in pairs(self.handlers) do
        summary.subscribed[#summary.subscribed + 1] = event
    end
    for event in pairs(self.skipped) do
        summary.skipped[#summary.skipped + 1] = event
    end
    sort(summary.subscribed)
    sort(summary.skipped)
    return summary
end
