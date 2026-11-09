-- The game's Options > AddOns entry (Story 9.7): a launcher with one button that opens the
-- Settings page of the main window, where every setting lives now. A canvas category with an own
-- frame when the client has RegisterCanvasLayoutCategory, else a vertical category with a button
-- initializer, else none. Also /fm settings (opens the page) and /fm minimap.
local _, ns = ...

local setmetatable, type, pcall = setmetatable, type, pcall
local L, Options = ns.L, ns.Options

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel
ns.SettingsPanel = SettingsPanel

local function canvas(self, S)
    local env = self.env
    local frame = env.CreateFrame("Frame")
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    title:SetText(L.PREFIX)
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    note:SetText(L.LAUNCHER_NOTE)
    local button = ns.Frames.Button(env, frame, L.LAUNCHER_BUTTON, 220, function()
        self:Launch()
    end)
    button:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
    self.frame, self.button = frame, button
    return S.RegisterCanvasLayoutCategory(frame, L.PREFIX)
end

local function vertical(self, S)
    local category, layout = S.RegisterVerticalLayoutCategory(L.PREFIX)
    local make = self.env.CreateSettingsButtonInitializer
    if type(make) == "function" and type(layout) == "table" and layout.AddInitializer then
        layout:AddInitializer(make(L.PREFIX, L.LAUNCHER_BUTTON, function()
            self:Launch()
        end, L.LAUNCHER_NOTE, true))
        self.kind = "button"
    end
    return category
end

-- deps: { env, open() (opens the Settings page) }. Without the Settings API, panel.category is
-- nil; panel.kind is "canvas", "button", or "none".
function SettingsPanel.Start(deps)
    local self = setmetatable({ env = deps.env, open = deps.open, kind = "none" }, SettingsPanel)
    local S = deps.env.Settings
    if type(S) ~= "table" or type(S.RegisterAddOnCategory) ~= "function" then
        return self
    end
    if type(S.RegisterCanvasLayoutCategory) == "function" then
        self.category, self.kind = canvas(self, S), "canvas"
    elseif type(S.RegisterVerticalLayoutCategory) == "function" then
        self.category = vertical(self, S)
    end
    if self.category then
        S.RegisterAddOnCategory(self.category)
    end
    return self
end

-- The launcher button: closes the game's settings window (out of combat) and opens the page.
function SettingsPanel:Launch()
    local panel = self.env.SettingsPanel
    local combat = ns.Context.Call(self.env, "InCombatLockdown") == true
    if not combat and type(panel) == "table" and type(panel.Close) == "function" then
        pcall(panel.Close, panel)
    end
    self.open()
end

ns.Commands.Register("settings", L.CMD_SETTINGS, function()
    if not ns.mainWindow then
        ns.Print(L.STATUS_NOT_READY)
        return
    end
    ns.mainWindow:Open(ns.SettingsPage.KEY)
end)

ns.Commands.Register("minimap", L.CMD_MINIMAP, function(rest)
    local value = (rest or ""):lower()
    if not (ns.db and (value == "show" or value == "hide")) then
        ns.Print(L.MINIMAP_USAGE)
        return
    end
    Options.Set(ns.db.settings, "minimapShown", value == "show")
    if ns.minimap then
        ns.minimap:Update()
    end
    ns.Print(value == "show" and L.MINIMAP_SHOWN or L.MINIMAP_HIDDEN)
end)
