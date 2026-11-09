-- Pure logic: the detail pane of the journal's Fish tab in the table and tooltip style (owner
-- finding after Story 9.9): the fish as the title (icon, quality color), its group and tag in
-- grey, gold label and value pairs (caught, first catch, skill, season, time of day, own catches
-- by hour and month), and two small tables: where it bites (Classic estimate and own share) and
-- the recipes it is used in. Drawn into a builder (DetailPane: Title, Line, Pair, Gap, Header,
-- Row). No frame or API calls.
local _, ns = ...

local format, ipairs, min, concat, type = string.format, ipairs, math.min, table.concat, type
local L, Style, JournalTable, StatsTables = ns.L, ns.Style, ns.JournalTable, ns.StatsTables

local JournalDetail = {}
ns.JournalDetail = JournalDetail

JournalDetail.RECIPES = 4 -- recipe rows; the rest as "+N more"
JournalDetail.HOURS = 4 -- busiest server hours in the "By hour" pair

local function pct(x)
    local value = x * 100
    if value < 1 then
        return format("%.1f %%", value)
    end
    return format("%d %%", value + 0.5)
end

local function identity(b, entry, input)
    local group = L["JOURNAL_GROUP_" .. entry.group]
    local tag = StatsTables.Tag(entry.season, entry.time)
    b:Line(tag and format(L.JDET_GROUP_TAG, group, tag.text) or group, Style.GREY)
    if entry.new then
        b:Line(L.JDET_NEW, Style.ORANGE)
    end
    if entry.questOnly then
        b:Line(L.JDET_QUEST, Style.ORANGE)
    end
    b:Gap()
    if entry.caught then
        local n, qty = entry.n, entry.qty or entry.n
        local value = qty == n and Style.Number(n)
            or format(L.JDET_CAUGHT_QTY, Style.Number(n), Style.Number(qty))
        b:Pair(L.JDET_CAUGHT, value)
        if entry.first then
            b:Pair(L.JDET_FIRST, input.formatDate(entry.first))
            b:Pair(
                L.JDET_FIRST_WATER,
                JournalTable.PlaceName(input, entry.firstMap, entry.firstSub)
            )
        end
        if entry.best then
            b:Pair(L.JDET_MOST, input.mapName(entry.best) or L.JOURNAL_NO_PLACE)
        end
    else
        b:Pair(L.JDET_CAUGHT, L.JDET_NOT_YET, Style.GREY)
    end
    if entry.base and entry.base < 1 then
        b:Pair(L.JDET_CATCHABLE, L.JDET_ANY_SKILL)
    elseif entry.base then
        b:Pair(L.JDET_CATCHABLE_FROM, entry.base)
        b:Pair(L.JDET_SAFE_FROM, entry.safe)
    else
        b:Pair(L.JDET_SKILL, L.JDET_UNKNOWN, Style.GREY)
    end
end

local function season(b, entry, input)
    local s = entry.season
    if not s then
        return
    end
    local start = input.formatMonthDay(s.month, s.day)
    b:Pair(L.JDET_SEASON, format(L.JDET_SEASON_VALUE, L["JOURNAL_SEASON_" .. s.season], start))
    b:Pair(L.JDET_LASTS, format(L.JDET_DAYS, s.days))
    local now = input.inSeason and input.inSeason(s)
    if now ~= nil then
        b:Pair(
            L.JDET_NOW,
            now and L.JDET_IN_SEASON or L.JDET_OUT_SEASON,
            now and Style.GREEN or Style.GREY
        )
    end
end

-- The busiest server hours, most catches first (ties: the earlier hour).
local function topHours(byHour)
    local hours = {}
    for hour = 0, 23 do
        if byHour[hour] > 0 then
            hours[#hours + 1] = hour
        end
    end
    table.sort(hours, function(a, b)
        if byHour[a] ~= byHour[b] then
            return byHour[a] > byHour[b]
        end
        return a < b
    end)
    local parts = {}
    for i = 1, min(#hours, JournalDetail.HOURS) do
        parts[i] = format(L.JOURNAL_D_HOUR, hours[i], byHour[hours[i]])
    end
    return parts
end

-- The guides' day or night claim with the own catches by server hour; "unconfirmed" below the
-- grey threshold (Statistics Methods). Own catches by month for every caught fish.
local function times(b, entry, input)
    if entry.time then
        local byHour, total = ns.Season.Hours(entry.hours, input.hourOffset)
        local need = input.thresholds.greyBelow
        b:Pair(L.JDET_BITES, format(L.JDET_GUIDES, L["JOURNAL_TIME_" .. entry.time]))
        if total < need then
            b:Pair(L.JDET_CHECKED, format(L.JDET_UNCONFIRMED, total, need), Style.GREY)
        else
            b:Pair(L.JDET_CHECKED, format(L.JDET_CATCHES, total))
        end
        local hours = topHours(byHour)
        if #hours > 0 then
            b:Pair(L.JDET_BY_HOUR, concat(hours, ", "))
        end
    end
    local months = {}
    for month = 1, 12 do
        local n = entry.months and entry.months[month]
        if type(n) == "number" and n > 0 then
            months[#months + 1] = format(L.JOURNAL_D_MONTH, input.monthName(month), n)
        end
    end
    if #months > 0 then
        b:Pair(L.JDET_BY_MONTH, concat(months, ", "))
    end
end

-- Own share in an area: grey "k/n" below the count threshold, "-" without own catches there.
local function ownShare(input, area, id)
    local k, n = input.ownShare(area, id)
    if not (n and n > 0) then
        return L.JOURNAL_NO_PLACE, Style.GREY
    end
    if n < input.thresholds.countBelow then
        return format("%d/%d", k, n), Style.GREY
    end
    return pct(k / n)
end

local function places(b, entry, input)
    b:Gap()
    if #entry.places == 0 then
        b:Pair(L.JDET_WHERE, L.JDET_NO_DATA, Style.GREY)
        return
    end
    b:Header({ L.JDET_WHERE, L.JDET_CLASSIC, L.JDET_YOURS })
    for _, place in ipairs(entry.places) do
        local own, color = ownShare(input, place.area, entry.id)
        b:Row(
            { JournalTable.AreaName(input, place.area, true), pct(place.chance / 100), own },
            { nil, nil, color }
        )
    end
    if entry.placeCount > #entry.places then
        b:Line(format(L.JDET_MORE, entry.placeCount - #entry.places), Style.GREY)
    end
end

local function recipes(b, entry, input)
    if #entry.recipes == 0 then
        return
    end
    b:Gap()
    b:Header({ L.JDET_USED_IN, L.JDET_PROFESSION, "" })
    for i = 1, min(#entry.recipes, JournalDetail.RECIPES) do
        local spell = entry.recipes[i]
        local recipe = input.recipe(spell)
        local skill = recipe and recipe.profession and L["JOURNAL_SKILL_" .. recipe.profession]
        local known = input.known and input.known(spell)
        b:Row({
            input.spellName(spell) or format(L.JOURNAL_SPELL_LOADING, spell),
            skill or L.JOURNAL_NO_PLACE,
            known and L.JDET_KNOWN or "",
        }, { nil, nil, Style.GREEN })
    end
    if #entry.recipes > JournalDetail.RECIPES then
        b:Line(format(L.JDET_MORE_RECIPES, #entry.recipes - JournalDetail.RECIPES), Style.GREY)
    end
end

-- draw(builder) of one entry (nil: the "click a fish" line). input as for JournalTable.Rows plus
-- formatDate(t), spellName(id), ownShare(area, id) -> k, n (own catches of the item and all
-- catches in that area) or nil, recipe(spell) -> the RecipeModel entry, known(spell) (optional),
-- formatMonthDay(month, day), monthName(month), hourOffset, inSeason(season) (optional),
-- thresholds.
function JournalDetail.Draw(entry, input)
    return function(b)
        if not entry then
            b:Line(L.JOURNAL_SELECT, Style.GREY)
            return
        end
        b:Title(JournalTable.ItemText(entry.id, input.info(entry.id), entry.caught))
        identity(b, entry, input)
        season(b, entry, input)
        times(b, entry, input)
        places(b, entry, input)
        recipes(b, entry, input)
    end
end
