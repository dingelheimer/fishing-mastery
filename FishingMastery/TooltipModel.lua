-- Pure logic: the item tooltip lines of Draft 6 from one entry of the character's item totals
-- (Totals items[id]: n catches with the item, best map): an empty line, "Fishing Mastery" in the
-- addon color with "caught 412" on the right, and "Best water" as a pair. Items never caught get
-- nothing. No frame or API calls; the lines are drawn into a Tip builder.
local _, ns = ...

local type, format = type, string.format
local L, Style = ns.L, ns.Style

local TooltipModel = {}
ns.TooltipModel = TooltipModel

-- The draw(tip) of an item, or nil. entry: totals.items[id]; mapName(map): zone name or nil.
function TooltipModel.Draw(entry, mapName)
    if type(entry) ~= "table" or type(entry.n) ~= "number" or entry.n < 1 then
        return nil
    end
    local caught = format(L.TOOLTIP_CAUGHT, Style.Number(entry.n))
    local map = entry.best
    local zone
    if type(map) == "number" and map ~= 0 then
        zone = mapName(map) or format(L.SUMMARY_ZONE_ID, map)
    end
    return function(tip)
        tip:Gap()
        tip:Pair(L.PREFIX, caught, nil, Style.ADDON)
        if zone then
            tip:Pair(L.TOOLTIP_BEST, zone)
        end
    end
end
