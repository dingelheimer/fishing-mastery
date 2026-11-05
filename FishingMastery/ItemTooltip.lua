-- Item tooltip line: one TooltipDataProcessor post-call for items (confirmed on live in Story 3.1)
-- adds "Fishing Mastery: caught Nx (best: <zone>)" for items the character caught. One lookup in
-- the item totals per tooltip, never a history scan; only appends its own line (other lines are
-- never changed). Switched off with the tooltip setting. Post-calls cannot be removed, so the
-- handler checks the setting on every call.
local _, ns = ...

local type = type
local Context, TooltipModel = ns.Context, ns.TooltipModel
local isSecret = issecretvalue or function()
    return false
end

local ItemTooltip = {}
ns.ItemTooltip = ItemTooltip

-- The line for tooltip data { id }, or nil. deps: { settings, char (character entry), mapName }.
function ItemTooltip.LineFor(deps, data)
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
    return TooltipModel.Line(type(items) == "table" and items[id] or nil, deps.mapName)
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
            local line = ItemTooltip.LineFor(lineDeps, data)
            if line then
                local c = TooltipModel.COLOR
                tooltip:AddLine(line, c[1], c[2], c[3])
            end
        end)
    )
    return true
end
