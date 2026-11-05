-- Replays fixture event sequences (spec/fixtures/live_attempts.lua) through the real Tracker with
-- a fake game environment, a fake clock, and fake C_Timer timers.
local M = {}

-- Live texts and message types from the Epic 1 run (global string values on an English client).
M.GLOBALS = {
    ERR_FISH_ESCAPED = "Your fish got away!",
    ERR_FISH_NOT_HOOKED = "No fish are hooked.",
    SPELL_FAILED_NOT_FISHABLE = "Your cast didn't land in fishable water",
    SPELL_FAILED_TOO_SHALLOW = "Water too shallow",
}
M.MESSAGE_NAMES = {
    [57] = "ERR_SPELL_FAILED_S",
    [280] = "ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS",
    [412] = "ERR_ZONE_EXPLORED",
    [417] = "ERR_FISH_NOT_HOOKED",
    [418] = "ERR_FISH_ESCAPED",
    [858] = "ERR_TOO_FAR_TO_INTERACT",
}
M.SPELL_NAMES = { [7620] = "Fishing", [1260270] = "Rapid Regeneration", [2366] = "Herb Gathering" }

-- Returns a runner: { env, clock, Feed(event), Run(events), Finish(), records }.
-- opts.globals overrides M.GLOBALS (false removes one); opts.messageNames overrides the
-- GetGameMessageInfo table (false makes it return nil for every type).
function M.new(ns, opts)
    opts = opts or {}
    local runner = { records = {}, timers = {}, clock = 0 }
    local state = { channel = nil, fishing = false }
    local env = {
        C_Spell = {
            GetSpellInfo = function(spellID)
                local name = M.SPELL_NAMES[spellID]
                return name and { name = name, spellID = spellID } or nil
            end,
        },
        UnitChannelInfo = function()
            if state.channel then
                local startMs = runner.clock * 1000
                return "x", "x", 0, startMs, startMs + state.channel * 1000
            end
        end,
        IsFishingLoot = function()
            return state.fishing
        end,
    }
    if opts.messageNames ~= false then
        local names = opts.messageNames or M.MESSAGE_NAMES
        env.GetGameMessageInfo = function(messageType)
            return names[messageType]
        end
    end
    for name, value in pairs(M.GLOBALS) do
        env[name] = value
    end
    for name, value in pairs(opts.globals or {}) do
        env[name] = value or nil
    end
    runner.env = env

    local frame = {}
    function frame.RegisterEvent()
        return true
    end
    local bus = ns.Events.New(frame)
    runner.tracker = ns.Tracker.Start({
        env = env,
        bus = bus,
        now = function()
            return runner.clock
        end,
        after = function(seconds, fn)
            runner.timers[#runner.timers + 1] = { at = runner.clock + seconds, fn = fn }
        end,
        onAttempt = function(record)
            runner.records[#runner.records + 1] = record
        end,
    })

    -- Runs timers that are due by time t, earliest first.
    local function runTimers(t)
        while true do
            local index
            for i, timer in ipairs(runner.timers) do
                if timer.at <= t and (not index or timer.at < runner.timers[index].at) then
                    index = i
                end
            end
            if not index then
                return
            end
            local timer = table.remove(runner.timers, index)
            runner.clock = timer.at
            timer.fn()
        end
    end

    -- event: { t, name, args..., channel = seconds, fishing = bool }, t relative to base.
    function runner.Feed(event, base)
        local t = (base or 0) + event[1]
        runTimers(t)
        runner.clock = t
        state.channel = event.channel
        if event.fishing ~= nil then
            state.fishing = event.fishing
        end
        bus:Dispatch(event[2], unpack(event, 3, table.maxn(event)))
    end

    function runner.Run(events, base)
        for _, event in ipairs(events) do
            runner.Feed(event, base)
        end
    end

    -- Lets every pending timer fire (the attempt ends by grace time or maximum age).
    function runner.Finish()
        runTimers(math.huge)
    end

    -- Outcomes of the finished records, in order.
    function runner.Outcomes()
        local list = {}
        for i, record in ipairs(runner.records) do
            list[i] = record.outcome
        end
        return list
    end

    return runner
end

return M
