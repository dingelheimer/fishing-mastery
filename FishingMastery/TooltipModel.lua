-- Pure logic: the item tooltip line "Fishing Mastery: caught 37x (best: Darkspear Strand)" from
-- one entry of the character's item totals (Totals items[id]: n catches with the item, best map).
-- Items never caught give no line. No frame or API calls.
local _, ns = ...

local type, format = type, string.format
local L = ns.L

local TooltipModel = {}
ns.TooltipModel = TooltipModel

TooltipModel.COLOR = { 0.2, 0.73, 1 } -- the addon's chat prefix color

-- The line for an item, or nil. entry: totals.items[id]; mapName(map): zone name or nil.
function TooltipModel.Line(entry, mapName)
    if type(entry) ~= "table" or type(entry.n) ~= "number" or entry.n < 1 then
        return nil
    end
    local map = entry.best
    if type(map) ~= "number" or map == 0 then
        return format(L.TOOLTIP_CAUGHT, entry.n)
    end
    local zone = mapName(map) or format(L.SUMMARY_ZONE_ID, map)
    return format(L.TOOLTIP_CAUGHT_BEST, entry.n, zone)
end
