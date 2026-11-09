-- Item tooltip lines: one TooltipDataProcessor post-call for items (confirmed on live in Story 3.1)
-- adds "Fishing Mastery  caught N" and "Best water" (Draft 6, TooltipModel) for items the
-- character caught, through Tip.Into. One lookup in the item totals per tooltip, never a history
-- scan; only appends its own lines (other lines are never changed). Switched off with the tooltip
-- setting. Post-calls cannot be removed, so the handler checks the setting on every call.
local _, ns = ...

local type = type
local Context, TooltipModel = ns.Context, ns.TooltipModel
local isSecret = issecretvalue or function()
    return false
end

local ItemTooltip = {}
ns.ItemTooltip = ItemTooltip

-- The draw(tip) for tooltip data { id }, or nil. deps: { settings, char (character entry),
-- mapName }.
function ItemTooltip.DrawFor(deps, data)
    if not ns.Options.Get(deps.settings, "tooltipLine") or type(data) ~= "table" then
        return nil
    end
    local id = data.id
    if isSecret(id) or type(id) ~= "number" then
        return nil
    end
    local char = deps.char
    local totals = type(char) == "table" and char.totals
    local items = type(totals) == "table" and totals.items
    return TooltipModel.Draw(type(items) == "table" and items[id] or nil, deps.mapName)
end

-- deps: { env, settings (db.settings), char }. Registers the post-call once; returns false when
-- the client has no TooltipDataProcessor.
function ItemTooltip.Start(deps)
    local env = deps.env
    local processor, enum = env.TooltipDataProcessor, env.Enum
    local itemType = type(enum) == "table"
        and type(enum.TooltipDataType) == "table"
        and enum.TooltipDataType.Item
    if
        type(processor) ~= "table"
        or type(processor.AddTooltipPostCall) ~= "function"
        or not itemType
    then
        return false
    end
    local names = {}
    local lineDeps = {
        settings = deps.settings,
        char = deps.char,
        mapName = function(map)
            if names[map] == nil then
                names[map] = Context.MapName(env, map) or false
            end
            return names[map] or nil
        end,
    }
    processor.AddTooltipPostCall(
        itemType,
        ns.Guard.Wrap("tooltip:item", function(tooltip, data)
            local draw = ItemTooltip.DrawFor(lineDeps, data)
            if draw then
                draw(ns.Tip.Into(tooltip))
            end
        end)
    )
    return true
end
