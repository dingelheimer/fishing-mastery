-- Small confirmation dialog (used by /fmp reset). Unnamed frame, so no global is created.
local _, ns = ...

local setmetatable = setmetatable
local L = ns.L

local Confirm = {}
Confirm.__index = Confirm
ns.Confirm = Confirm

Confirm.WIDTH = 360
Confirm.HEIGHT = 130

function Confirm.Create(env)
    local self = setmetatable({}, Confirm)
    local frame = ns.Window.CreateFrame(env, "Frame", env.UIParent, ns.Window.TEMPLATE)
    frame:SetSize(Confirm.WIDTH, Confirm.HEIGHT)
    frame:SetPoint("CENTER", env.UIParent, "CENTER", 0, 120)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    self.frame = frame
    self.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    self.text:SetWidth(Confirm.WIDTH - 32)
    self.text:SetJustifyH("LEFT")
    self.text:SetWordWrap(true)

    local yes = ns.Window.CreateFrame(env, "Button", frame, ns.Window.BUTTON_TEMPLATE)
    yes:SetSize(120, 22)
    yes:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    yes:SetScript(
        "OnClick",
        ns.Guard.Wrap("confirm:yes", function()
            local onYes = self.onYes
            self.onYes = nil
            frame:Hide()
            if onYes then
                onYes()
            end
        end)
    )
    self.yes = yes
    local no = ns.Window.CreateFrame(env, "Button", frame, ns.Window.BUTTON_TEMPLATE)
    no:SetSize(90, 22)
    no:SetPoint("LEFT", yes, "RIGHT", 8, 0)
    no:SetText(L.BUTTON_CANCEL)
    no:SetScript(
        "OnClick",
        ns.Guard.Wrap("confirm:no", function()
            self.onYes = nil
            frame:Hide()
        end)
    )
    self.no = no
    frame:Hide()
    return self
end

-- Asks a question; onYes runs only when the confirm button is clicked.
function Confirm:Ask(text, yesLabel, onYes)
    self.text:SetText(text)
    self.yes:SetText(yesLabel)
    self.onYes = onYes
    self.frame:Show()
end
