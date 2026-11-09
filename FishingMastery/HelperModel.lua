-- Pure logic: the Helpers page of Draft 3 (Story 9.6): one row per helper with its live state tag,
-- the smart lure's "Right now" (what a lure would do in this water), and the "This login" counts.
-- States: off (grey), ready, on, or active (green), blocked with the reason (orange). No frame or
-- API calls; the page reads the game and passes the facts in.
local _, ns = ...

local format, floor, ipairs = string.format, math.floor, ipairs
local L, Options = ns.L, ns.Options

local HelperModel = {}
ns.HelperModel = HelperModel

-- Rows in page order: group, setting key, and whether a casting key is needed for it to act.
HelperModel.ROWS = {
    { group = "casting", key = "doubleClick" },
    { group = "casting", key = "autoLure", needsKey = true },
    { group = "fishing", key = "loudSplash" },
    { group = "fishing", key = "hideUI" },
}

local function tag(text, kind)
    return { text = text, kind = kind }
end

-- input: { settings, bound (the casting key has a key), blocked (DoubleClick.Blocked reason or
-- nil), splashActive (SoundBoost:Active), hidden (HideUI hid the interface) }.
local function state(row, input)
    if Options.Get(input.settings, row.key) ~= true then
        return tag(L.HSTATE_OFF, "off")
    end
    if row.needsKey and not input.bound then
        return tag(L.HSTATE_NO_KEY, "blocked")
    end
    if row.key == "doubleClick" then
        local reason = input.blocked
        if reason then
            return tag(L["HBLOCK_" .. reason] or reason, "blocked")
        end
        return tag(L.HSTATE_READY, "ready")
    end
    if row.key == "loudSplash" and input.splashActive then
        return tag(L.HSTATE_ACTIVE, "active")
    end
    if row.key == "hideUI" and input.hidden then
        return tag(L.HSTATE_ACTIVE, "active")
    end
    return tag(L.HSTATE_ON, "on")
end

-- The helper rows: { key, group, label, text (one line), on, state = { text, kind } }.
function HelperModel.Rows(input)
    local rows = {}
    for _, row in ipairs(HelperModel.ROWS) do
        rows[#rows + 1] = {
            key = row.key,
            group = row.group,
            label = L["HROW_" .. row.key],
            text = L["HROW_TEXT_" .. row.key],
            on = Options.Get(input.settings, row.key) == true,
            state = state(row, input),
        }
    end
    return rows
end

local function minutes(seconds)
    return floor(seconds / 60 + 0.5)
end

-- The detail line of a lure: how many are in the bags and the time left on the pole.
local function lureDetail(lure, active)
    local pole = L.HNOW_NO_LURE_ON
    if active and active.seconds then
        pole = format(L.HNOW_LEFT, minutes(active.seconds))
    end
    return format(L.HNOW_BAGS, lure.count or 0) .. "; " .. pole
end

-- input: { choice (LureChoice.Choose without the running lure, or nil when the bags cannot be
-- read), active (the running lure { bonus, seconds } or nil), name(id), zone (the water's name
-- or nil) }. Returns { title, sub, detail, lure (item ID for the icon, or nil) }.
function HelperModel.Now(input)
    local choice = input.choice
    if not choice then
        return { title = L.HNOW_NO_BAGS, sub = "", detail = "" }
    end
    local lure, reason, goal = choice.lure, choice.reason, choice.goal
    local where = input.zone and format(L.HNOW_IN, input.zone) or L.HNOW_HERE
    if reason == "reaches" or reason == "strongest" then
        local sub = reason == "reaches" and format(L.HNOW_REACHES, where)
            or format(L.HNOW_STRONGEST, goal)
        return {
            title = format(L.HNOW_LURE, input.name(lure.id), lure.bonus),
            sub = sub,
            detail = lureDetail(lure, input.active),
            lure = lure.id,
        }
    end
    if reason == "enough" then
        return { title = L.HNOW_ENOUGH, sub = format(L.HNOW_ENOUGH_SUB, where), detail = "" }
    end
    if reason == "no-lures" and goal then
        return { title = L.HNOW_NONE_OWNED, sub = format(L.HNOW_STOP_AT, goal), detail = "" }
    end
    if reason == "unknown-skill" then
        return { title = L.HNOW_NO_SKILL, sub = "", detail = "" }
    end
    return { title = L.HNOW_NO_WATER, sub = L.HNOW_NO_WATER_SUB, detail = "" }
end

-- status: the HelperStatus counts { presses = { spell, lure, wait }, casts }, doubled (presses
-- from a double right-click), hides. Returns { { label, value } } for the "This login" table.
function HelperModel.Login(status)
    local p = status.presses or {}
    return {
        { label = L.HLOGIN_KEY, value = p.spell or 0 },
        { label = L.HLOGIN_LURE, value = p.lure or 0 },
        { label = L.HLOGIN_WAIT, value = p.wait or 0 },
        { label = L.HLOGIN_DOUBLE, value = status.doubled or 0 },
        { label = L.HLOGIN_CASTS, value = status.casts or 0 },
        { label = L.HLOGIN_HIDES, value = status.hides or 0 },
    }
end
