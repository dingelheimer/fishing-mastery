-- Addon compartment entry (TOC AddonCompartmentFunc). The handler is the addon's only global
-- besides the SavedVariables and the slash command; it runs through the guard. Until the stats
-- window exists (Story 3.7) a click prints a test line.
local _, ns = ...

local L = ns.L

local Compartment = {}
ns.Compartment = Compartment

function Compartment.Click()
    local result = ns.UiCheck and ns.UiCheck.result
    if result then
        result.compartmentClicks = (result.compartmentClicks or 0) + 1
    end
    ns.Print(L.COMPARTMENT_TEST)
end

function FishingMastery_OnAddonCompartmentClick(...)
    ns.Guard.Call("compartment", Compartment.Click, ...)
end
