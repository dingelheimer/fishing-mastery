-- Event bus: one frame, a dispatch table, and player-only unit events. Events the client cannot
-- register are skipped and listed, so a missing event never breaks loading.
-- Adapted from FishingMasteryProbe/Events.lua (no login snapshot; adds Off).
local _, ns = ...

local setmetatable, pcall, pairs, ipairs, sort = setmetatable, pcall, pairs, ipairs, table.sort
local isSecret = issecretvalue or function()
    return false
end

local Events = {}
Events.__index = Events
ns.Events = Events

-- frame: a WoW frame (or a test double with RegisterEvent and optional RegisterUnitEvent).
function Events.New(frame)
    return setmetatable({
        frame = frame,
        handlers = {},
        units = {},
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
-- Returns false when registration failed; the event is then listed in Summary().failed.
function Events:On(event, fn, unit)
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

-- Removes every handler of the event and unregisters it from the frame.
function Events:Off(event)
    if not self.handlers[event] then
        return
    end
    self.handlers[event] = nil
    self.units[event] = nil
    if self.frame.UnregisterEvent then
        pcall(self.frame.UnregisterEvent, self.frame, event)
    end
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

-- Lists subscribed and failed events.
function Events:Summary()
    local summary = { subscribed = {}, failed = self.failed }
    for event in pairs(self.handlers) do
        summary.subscribed[#summary.subscribed + 1] = event
    end
    sort(summary.subscribed)
    return summary
end
