-- Addon compartment entry (TOC AddonCompartmentFunc): opens or closes the stats window, or with
-- Shift held the journal window (Story 5.4). The
-- handler is the addon's only global besides the SavedVariables and the slash command; it runs
-- through the guard. Clicks are counted for the UI check while it runs (dev flag).
local _, ns = ...

local L = ns.L

local Compartment = {}
ns.Compartment = Compartment

function Compartment.Click()
    local result = ns.UiCheck and ns.UiCheck.result
    if result then
        result.compartmentClicks = (result.compartmentClicks or 0) + 1
    end
    if not (ns.stats and ns.castLog and ns.castLog.char) then
        ns.Print(L.STATUS_NOT_READY)
    elseif ns.journalWindow and ns.Context.Call(_G, "IsShiftKeyDown") then
        ns.journalWindow:Toggle()
    else
        ns.stats:Toggle()
    end
end

function FishingMastery_OnAddonCompartmentClick(...)
    ns.Guard.Call("compartment", Compartment.Click, ...)
end
