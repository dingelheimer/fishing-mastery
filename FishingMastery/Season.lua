-- Pure logic: Classic season windows and day/night counts for the journal. Realm time is the
-- server time (UTC epoch seconds) plus the realm offset in whole hours (the GetGameTime hour minus
-- the UTC hour, as -12..11). A season starts every year on its month and day at its hour (realm
-- time) and lasts its days, as the Classic game events do. No frame or API calls.
local _, ns = ...

local type, pairs, floor = type, pairs, math.floor

local Season = {}
ns.Season = Season

Season.DAY, Season.HOUR = 86400, 3600

-- Days since 1970-01-01 of a date (proleptic Gregorian; the inverse of Totals.Civil).
function Season.Days(year, month, day)
    local y = month <= 2 and year - 1 or year
    local era = floor(y / 400)
    local yoe = y - era * 400
    local mp = month > 2 and month - 3 or month + 9
    local doy = floor((153 * mp + 2) / 5) + day - 1
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- Realm offset in hours (-12..11) from the game hour and the server time; 0 when unknown.
function Season.Offset(gameHour, serverTime)
    if type(gameHour) ~= "number" or type(serverTime) ~= "number" then
        return 0
    end
    local offset = (gameHour - floor((serverTime % Season.DAY) / Season.HOUR)) % 24
    return offset >= 12 and offset - 24 or offset
end

-- True when realm time (t + offset hours) is inside the season's window that started this year
-- or last year. season: { month, day, hour, days } (Data/Journal.lua seasons).
function Season.InSeason(season, t, offset)
    local now = t + (offset or 0) * Season.HOUR
    local year = ns.Totals.Civil(floor(now / Season.DAY))
    for y = year - 1, year do
        local start = Season.Days(y, season.month, season.day) * Season.DAY
            + season.hour * Season.HOUR
        if now >= start and now < start + season.days * Season.DAY then
            return true
        end
    end
    return false
end

-- Catches per realm hour (0-23) from item hours keyed by UTC hour, and their total.
function Season.Hours(hours, offset)
    local out, total = {}, 0
    for hour = 0, 23 do
        out[hour] = 0
    end
    for hour, n in pairs(type(hours) == "table" and hours or {}) do
        if type(hour) == "number" and type(n) == "number" then
            local realm = (hour + (offset or 0)) % 24
            out[realm] = out[realm] + n
            total = total + n
        end
    end
    return out, total
end
