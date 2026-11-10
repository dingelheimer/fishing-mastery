-- The HUD card's fish row (Story 9.8; its own file since Story 10.6): the water's fish as icons,
-- bright when caught here and dark when missing, with the name in a tooltip, and "N missing" on
-- the right. Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local L, Style = ns.L, ns.Style

local HudCardFish = {}
ns.HudCardFish = HudCardFish

local function place(...)
    return ns.HudCard.Place(...)
end

local function icon(parent)
    return ns.HudCard.Icon(parent)
end

-- One fish icon with its name in a tooltip.
local function fishIcon(card, f)
    local slot = card.env.CreateFrame("Frame", nil, f)
    slot:SetSize(ns.HudCard.ICON, ns.HudCard.ICON)
    slot.texture = icon(slot)
    slot.texture:SetAllPoints(slot)
    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(owner)
        local data = owner.data
        if data then
            ns.Tip.Open(card.env, owner, function(tip)
                tip:Title(data.name or "?")
                tip:Line(data.caught and L.HCARD_FISH_CAUGHT or L.HCARD_FISH_MISSING, Style.GREY)
            end)
        end
    end)
    slot:SetScript("OnLeave", function(owner)
        ns.Tip.Close(card.env, owner)
    end)
    return slot
end

-- Draws the fish row at y; returns the y under it (y itself without a fish list).
function HudCardFish.Draw(card, fish, missing, y)
    local pad = ns.HudCard.PAD
    for i, slot in ipairs(card.fishSlots) do
        local data = fish and fish[i]
        slot:SetShown(data ~= nil)
        slot.data = data
        if data then
            place(slot, card, "TOPLEFT", pad + (i - 1) * (ns.HudCard.ICON + 4), y - 2)
            slot.texture:SetTexture(data.icon)
            local light = data.caught and 1 or ns.HudCard.DARK
            slot.texture:SetVertexColor(light, light, light)
        end
    end
    card.missing:SetShown(fish ~= nil)
    if not fish then
        return y
    end
    place(card.missing, card, "TOPRIGHT", -pad, y - 4)
    card.missing:SetText(missing or "")
    return y - 22
end

-- The icon slots of a card (frame f).
function HudCardFish.Create(card, f)
    card.fishSlots = {}
    for i = 1, ns.HudCard.FISH_ICONS do
        card.fishSlots[i] = fishIcon(card, f)
    end
end
