-- Developer tools, active only while FishingMasteryDB.settings.dev is true: the storage stress
-- test (/fm dev stress, lines, load, clear), load time measurement across /reload, the raw
-- capture (/fm dev capture), and the UI API check (/fm dev ui, UiCheck.lua). All test data
-- lives in db.dev, never in a real character entry.
local _, ns = ...

local format, match, lower, tonumber, ipairs, type, min, concat =
    string.format, string.match, string.lower, tonumber, ipairs, type, math.min, table.concat
local L = ns.L

local Stress, Capture = ns.Stress, ns.Capture

local Dev = { BATCH = 5000, PROGRESS = 50000, LOOT_GAP = 1 }
ns.Dev = Dev

function Dev.Enabled(db)
    return type(db) == "table" and type(db.settings) == "table" and db.settings.dev == true
end

-- Load measurement at PLAYER_LOGIN: reload time, tracker start, the stepped load check of the
-- stress entry (the same steps a real history gets), and the line test chunks. Prints the
-- results while the dev flag is set; the load line follows when the stress check is done.
local function measure(self)
    local db, deps = self.db, self.deps
    local dev = db.dev
    if not Dev.Enabled(db) or type(dev) ~= "table" then
        return
    end
    local show = deps.print
    local load = { at = deps.serverTime(), tracker = deps.trackerSec }
    if dev.logoutAt then
        load.reload = Stress.ReloadTime(dev, deps.loadedAt)
        dev.logoutAt = nil
        if not load.reload then
            show(L.DEV_NO_RELOAD)
        end
    end
    if type(dev.lines) == "table" then
        for _, result in ipairs(Stress.CheckLines(dev.lines)) do
            show(format(L.DEV_LINE, result.length, result.ok and L.DEV_OK or result.error))
        end
    end
    local function report()
        if load.reload then
            Stress.AddLoad(dev, load)
            show(Dev.FormatLoad(load))
        end
    end
    if type(dev.stress) ~= "table" then
        report()
        return
    end
    load.chunks, load.bytes = Stress.Size(dev.stress.days)
    local entry = dev.stress
    ns.CastLog.RunCheck(entry, load.at, deps.after, deps.now, function(check)
        load.check, load.longest, load.steps = check.seconds, check.longest, check.steps
        load.casts, load.quarantined = check.result.casts, check.result.quarantined
        local size = Stress.TotalsSize(entry.totals)
        load.totalsBytes = size.bytes
        report()
        show(
            format(
                L.DEV_TOTALS,
                size.bytes,
                size.items,
                size.maps,
                size.hours,
                size.bands,
                size.bites
            )
        )
    end, true)
end

function Dev.FormatLoad(load)
    return format(
        L.DEV_LOAD,
        load.reload or -1,
        load.tracker or -1,
        load.check or 0,
        load.steps or 0,
        (load.longest or 0) * 1000,
        load.casts or 0,
        load.bytes or 0
    )
end

local function onCast(self)
    local _, modifier = ns.Context.Fishing(self.deps.env)
    Capture.Add(self.db.dev.capture, {
        k = "cast",
        t = self.deps.serverTime(),
        mod = modifier,
        auras = Capture.Auras(self.deps.env),
    })
end

local function onLoot(self)
    local env, now = self.deps.env, self.deps.now()
    if ns.Context.Call(env, "IsFishingLoot") ~= true then
        return
    end
    if self.lastLoot and now - self.lastLoot < Dev.LOOT_GAP then
        return
    end
    self.lastLoot = now
    Capture.Add(
        self.db.dev.capture,
        { k = "loot", t = self.deps.serverTime(), src = Capture.Sources(env) }
    )
end

local function capturing(self)
    local db = self.db
    if not Dev.Enabled(db) or db.settings.capture ~= true then
        return false
    end
    local dev = Stress.Dev(db)
    dev.capture = Capture.Repair(dev.capture)
    return true
end

-- deps: { db, bus, env, now (GetTimePreciseSec), serverTime, after(seconds, fn) or nil,
-- print(text), loadedAt (GetTimePreciseSec at ADDON_LOADED), trackerSec, isFishingSpell }.
function Dev.Start(deps)
    local self = { db = deps.db, deps = deps }
    Dev.state = self
    measure(self)
    local bus = deps.bus
    bus:On("PLAYER_LOGOUT", function()
        if self.job then
            Stress.Finish(self.job.entry)
            self.job = nil
        end
        if Dev.Enabled(self.db) then
            Stress.Dev(self.db).logoutAt = deps.now()
        end
    end)
    bus:On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, _, spellID)
        if capturing(self) and deps.isFishingSpell(spellID) then
            onCast(self)
        end
    end, "player")
    bus:On("LOOT_READY", function()
        if capturing(self) then
            onLoot(self)
        end
    end)
    return self
end

-- Writes count synthetic casts into db.dev.stress in steps of Dev.BATCH per frame.
function Dev.StartStress(self, count)
    local dev = Stress.Dev(self.db)
    if dev.stress or self.job then
        ns.Print(L.DEV_STRESS_EXISTS)
        return
    end
    local entry = Stress.NewEntry(count)
    dev.stress = entry
    local job = { entry = entry, nextCast = Stress.Generator() }
    self.job = job
    ns.Print(format(L.DEV_STRESS_START, count))
    local after = self.deps.after
    local function step()
        if self.job ~= job then
            return
        end
        local before = entry.written
        local done = Stress.Fill(entry, job.nextCast, Dev.BATCH)
        if done then
            self.job = nil
            local chunks, bytes = Stress.Finish(entry)
            ns.Print(format(L.DEV_STRESS_DONE, entry.written, chunks, bytes))
        else
            if before % Dev.PROGRESS > entry.written % Dev.PROGRESS then
                ns.Print(format(L.DEV_STRESS_PROGRESS, entry.written, count))
            end
            if after then
                after(0, step)
            else
                step()
            end
        end
    end
    step()
end

local function captureCommand(self, value)
    local db = self.db
    if value == "on" or value == "off" then
        db.settings.capture = value == "on"
    elseif value == "clear" then
        Stress.Dev(db).capture = nil
    end
    local dev = Stress.Dev(db)
    dev.capture = Capture.Repair(dev.capture)
    local summary = Capture.Summary(dev.capture)
    ns.Print(
        format(
            L.DEV_CAPTURE,
            db.settings.capture == true and L.DEV_ON or L.DEV_OFF,
            #dev.capture.entries,
            Capture.CAP,
            summary.casts,
            summary.loots
        )
    )
    for _, list in ipairs({ { L.DEV_AURAS, summary.auras }, { L.DEV_SOURCES, summary.sources } }) do
        local parts = {}
        for i = 1, min(#list[2], 8) do
            parts[i] = format("%s x%d", list[2][i].key, list[2][i].count)
        end
        ns.Print(format(list[1], #parts > 0 and concat(parts, ", ") or "-"))
    end
end

local function command(rest)
    local self = Dev.state
    if not self then
        ns.Print(L.STATUS_NOT_READY)
        return
    end
    local action, value = match(rest or "", "^(%S*)%s*(%S*)")
    action, value = lower(action or ""), lower(value or "")
    local dev = Stress.Dev(self.db)
    if action == "stress" then
        local count = tonumber(value) or Stress.DEFAULT_CASTS
        if count < 1 or count > Stress.MAX_CASTS or count % 1 ~= 0 then
            ns.Print(format(L.DEV_STRESS_RANGE, Stress.MAX_CASTS))
            return
        end
        Dev.StartStress(self, count)
    elseif action == "lines" then
        dev.lines = Stress.Lines()
        ns.Print(format(L.DEV_LINES, dev.lines[1].length, dev.lines[2].length))
    elseif action == "load" then
        if type(dev.loads) ~= "table" or #dev.loads == 0 then
            ns.Print(L.DEV_LOADS_NONE)
        end
        for _, load in ipairs(dev.loads or {}) do
            ns.Print(Dev.FormatLoad(load))
        end
    elseif action == "clear" then
        self.job = nil
        dev.stress, dev.lines = nil, nil
        ns.Print(L.DEV_CLEARED)
    elseif action == "capture" then
        captureCommand(self, value)
    elseif action == "ui" then
        ns.UiCheck.Run({
            env = self.deps.env,
            db = self.db,
            charDb = ns.charDb,
            serverTime = self.deps.serverTime,
        })
    else
        ns.Print(L.DEV_USAGE)
    end
end

ns.Commands.Register("dev", L.CMD_DEV, command, function()
    return Dev.Enabled(ns.db)
end)
