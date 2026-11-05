-- Pure logic: the calendar heatmap of fishing days on the Overview. One cell per day of the last
-- WEEKS weeks (columns, oldest first; rows Monday to Sunday) up to today, colored from a
-- sequential scale by the day's catches. Days are the UTC days of the server time, as in Totals.
-- No frame or API calls.
local _, ns = ...

local floor, ceil, max, type = math.floor, math.ceil, math.max, type

local CalendarModel = {}
ns.CalendarModel = CalendarModel

CalendarModel.WEEKS = 53
CalendarModel.LEVELS = 4
-- Level 0: no casts; 1-4: dark to bright blue (one hue, readable with common color vision
-- deficiencies; the numbers are in the tooltips).
CalendarModel.COLORS = {
    [0] = { 1, 1, 1, 0.07 },
    { 0.13, 0.27, 0.45, 1 },
    { 0.2, 0.42, 0.68, 1 },
    { 0.3, 0.6, 0.88, 1 },
    { 0.6, 0.85, 1, 1 },
}

-- Weekday row of a day number (days since 1970-01-01, a Thursday): 0 = Monday.
function CalendarModel.Row(day)
    return (day + 3) % 7
end

-- Color level of a day with casts: at least 1, the share of the busiest day's catches in LEVELS.
function CalendarModel.Level(catches, most)
    if most <= 0 then
        return 1
    end
    return max(1, ceil(CalendarModel.LEVELS * catches / most))
end

-- days: { [day] = { casts, catches } }; today: day number. Returns { cells = { { day, col, row,
-- casts, catches, level } } (oldest first), fishing (days with casts), most (catches) }.
function CalendarModel.Build(days, today)
    local first = today - CalendarModel.Row(today) - (CalendarModel.WEEKS - 1) * 7
    local most, fishing = 0, 0
    for day = first, today do
        local entry = days[day]
        if type(entry) == "table" and (entry.casts or 0) > 0 then
            most, fishing = max(most, entry.catches or 0), fishing + 1
        end
    end
    local cells = {}
    for day = first, today do
        local entry = days[day]
        local casts = type(entry) == "table" and entry.casts or 0
        local catches = type(entry) == "table" and entry.catches or 0
        cells[#cells + 1] = {
            day = day,
            col = floor((day - first) / 7) + 1,
            row = CalendarModel.Row(day) + 1,
            casts = casts,
            catches = catches,
            level = casts > 0 and CalendarModel.Level(catches, most) or 0,
        }
    end
    return { cells = cells, fishing = fishing, most = most }
end
