-- Runs handlers through xpcall. Errors are counted and handed to a sink (Core's recent-error
-- list) as { where, msg, stack }; they never propagate into the player's UI.
-- Copied from FishingMasteryProbe/Guard.lua; the addon never loads the probe.
local _, ns = ...

local xpcall, pcall, select, tostring, unpack = xpcall, pcall, select, tostring, unpack
local gmatch = string.gmatch
local isSecret = issecretvalue or function()
    return false
end
local getStack = debugstack and function()
    return debugstack(3)
end or function()
    return debug.traceback("", 3)
end

local Guard = {
    errors = 0,
    pending = {},
    sink = nil,
}
ns.Guard = Guard

Guard.MAX_PENDING = 50 -- errors kept while no sink is set
Guard.MAX_STACK_LINES = 20

local function stackLines(stack)
    local lines = {}
    for line in gmatch(stack or "", "[^\n]+") do
        if #lines >= Guard.MAX_STACK_LINES then
            break
        end
        if line:match("%S") then
            lines[#lines + 1] = line
        end
    end
    return lines
end

local function deliver(record)
    if Guard.sink then
        pcall(Guard.sink, record)
    elseif #Guard.pending < Guard.MAX_PENDING then
        Guard.pending[#Guard.pending + 1] = record
    end
end

-- Sets the error sink and flushes errors collected before it existed.
function Guard.SetSink(sink)
    Guard.sink = sink
    local pending = Guard.pending
    Guard.pending = {}
    for i = 1, #pending do
        deliver(pending[i])
    end
end

-- Calls fn(...) protected. Returns true plus results, or false plus the error message.
function Guard.Call(where, fn, ...)
    local count, args = select("#", ...), { ... }
    local function onError(err)
        local message = isSecret(err) and "<secret error>" or tostring(err)
        Guard.errors = Guard.errors + 1
        deliver({ where = where, msg = message, stack = stackLines(getStack()) })
        return message
    end
    return xpcall(function()
        return fn(unpack(args, 1, count))
    end, onError)
end

-- Returns a function that runs fn through Guard.Call.
function Guard.Wrap(where, fn)
    return function(...)
        return Guard.Call(where, fn, ...)
    end
end
