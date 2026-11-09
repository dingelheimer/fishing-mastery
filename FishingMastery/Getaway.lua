-- Pure logic: the getaway risk. The Classic model from the server code (Zone Data research):
-- catch chance = clamp(skill - base + 5, 0, 100) % of hooked fish, no catch below the base
-- (every fish gets away), no getaways from base + 95. skill is the effective skill (rank + lure
-- and gear). The own getaway rate (getaways / hooked) per resolved area and skill band comes
-- from the stats view, with its Wilson range; it is compared with the model only when it is
-- shown (display thresholds), and "differs" when its range excludes the model value. No frame
-- or API calls.
local _, ns = ...

local type, pairs, floor, max, min = type, pairs, math.floor, math.max, math.min
local Stats, Totals = ns.Stats, ns.Totals

local Getaway = {}
ns.Getaway = Getaway

Getaway.OFFSET = 5 -- catch chance at the base skill, in percent
Getaway.SPAN = 95 -- getaways stop at base + SPAN

-- The model at an effective skill and base skill: { catch, getaway (fractions), below (no catch
-- below the base), stopsAt (base + SPAN) }, or nil when either is unknown.
function Getaway.Model(skill, base)
    if type(skill) ~= "number" or type(base) ~= "number" then
        return nil
    end
    local catch = 0
    if skill >= base then
        catch = max(0, min(100, skill - base + Getaway.OFFSET)) / 100
    end
    return {
        catch = catch,
        getaway = 1 - catch,
        below = skill < base,
        stopsAt = base + Getaway.SPAN,
    }
end

-- Mean model getaway share over the skills from .. from + size - 1 (one skill band), or nil.
function Getaway.BandModel(from, size, base)
    if type(from) ~= "number" or type(base) ~= "number" then
        return nil
    end
    size = size or Totals.SKILL_BAND
    local sum = 0
    for skill = from, from + size - 1 do
        sum = sum + Getaway.Model(skill, base).getaway
    end
    return sum / size
end

-- Compares an own rate (Stats.Proportion) with a model value: { shown (above the count-only
-- threshold), differs (shown and the range excludes the model) }.
function Getaway.Compare(rate, model)
    local shown = rate ~= nil and rate.display ~= "count" and rate.low ~= nil
    return {
        shown = shown,
        differs = shown and type(model) == "number" and (model < rate.low or model > rate.high),
    }
end

local function child(list, key)
    local value = list[key]
    if not value then
        value = {}
        list[key] = value
    end
    return value
end

local function addBand(bands, band, entry)
    local into = child(bands, band)
    into.hooked = (into.hooked or 0) + (entry.hooked or 0)
    into.getaways = (into.getaways or 0) + (entry.getaways or 0)
end

-- Hooked casts per resolved area (areas: an Area resolver) from view.subskills:
-- byArea = { [area] = { [band] = { hooked, getaways } } }, and the hooked casts without an area.
function Getaway.ByArea(view, areas)
    local byArea, unknown = {}, 0
    for map, subs in pairs(view.subskills or {}) do
        for text, bands in pairs(subs) do
            local area = areas and areas:Resolve(map, text ~= "" and text or nil) or nil
            for band, entry in pairs(bands) do
                if area then
                    addBand(child(byArea, area), band, entry)
                else
                    unknown = unknown + (entry.hooked or 0)
                end
            end
        end
    end
    return byArea, unknown
end

-- Hooked casts per band of effective skill minus the area's base (aligned to SKILL_BAND):
-- { [band] = { hooked, getaways } }, and the hooked casts whose area has no base.
function Getaway.Relative(byArea, areas)
    local size, relative, unknown = Totals.SKILL_BAND, {}, 0
    for area, bands in pairs(byArea) do
        local base = areas and areas:Base(area)
        for band, entry in pairs(bands) do
            if base then
                addBand(relative, floor((band - base) / size) * size, entry)
            else
                unknown = unknown + (entry.hooked or 0)
            end
        end
    end
    return relative, unknown
end

-- Risk at an effective skill in one area: bands = byArea[area] (may be nil), base = the area's
-- base (nil: unknown). Returns { skill, band, model (Getaway.Model or nil), bandModel, own
-- (Stats.Proportion of the skill's band, nil without hooked casts there), shown, differs }.
function Getaway.Risk(bands, skill, base, t)
    local size = Totals.SKILL_BAND
    local band = floor(skill / size) * size
    local entry = bands and bands[band]
    local own = entry
            and (entry.hooked or 0) > 0
            and Stats.Proportion(entry.getaways or 0, entry.hooked, t)
        or nil
    local bandModel = Getaway.BandModel(band, size, base)
    local result = Getaway.Compare(own, bandModel)
    result.skill, result.band, result.own, result.bandModel = skill, band, own, bandModel
    result.model = Getaway.Model(skill, base)
    return result
end
