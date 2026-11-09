-- The Settings page of the main window (Draft 4, Story 9.7; /fm settings and the game's Options
-- entry open it): "HUD while fishing" with a live preview (HudCard) that follows layout, scale,
-- and opacity; "Information"; "Advanced: statistics" with the data buttons; "Defaults" with a
-- confirmation. Every control is an Options control with page = "settings"; a change is written
-- through Options.Set and applied at once (ns.ApplySetting). Only the addon's own saved settings
-- change. Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, ipairs, pairs, format, floor =
    setmetatable, ipairs, pairs, string.format, math.floor
local L, Style, Controls, Options = ns.L, ns.Style, ns.Controls, ns.Options
local MainWindow, HudCard = ns.MainWindow, ns.HudCard

local SettingsPage = {}
SettingsPage.__index = SettingsPage
ns.SettingsPage = SettingsPage

SettingsPage.KEY = "settings" -- MainWindow page key
SettingsPage.ICON = "Interface\\Icons\\INV_Misc_Gear_01"
SettingsPage.TOP, SettingsPage.LEFT_WIDTH, SettingsPage.GAP = 62, 380, 12
SettingsPage.TOP_HEIGHT = 236 -- the HUD and preview boxes
SettingsPage.SLIDER = 150
SettingsPage.PREVIEW_MAX = 1.3 -- the preview grows with the scale up to this, so it fits the box
-- Value texts of the sliders.
SettingsPage.FORMATS = {
    hudScale = "SET_PERCENT",
    hudOpacity = "SET_PERCENT",
    countBelow = "SET_CASTS",
    greyBelow = "SET_CASTS",
    activeCap = "SET_SECONDS",
}
SettingsPage.PERCENT = { hudScale = true, hudOpacity = true }
-- The data buttons: label and the /fm command they run.
SettingsPage.DATA =
    { { "SET_EXPORT", "export" }, { "SET_BACKUPS", "backup" }, { "SET_CONTRIBUTE", "contribute" } }

local function text(parent, font, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then
        fs:SetWidth(width)
    end
    fs:SetJustifyH("LEFT")
    return fs
end

local function change(self, key, value)
    if Options.Set(self.settings, key, value) and ns.ApplySetting then
        ns.ApplySetting(key)
    end
    self:Draw()
end

local function tooltip(self, owner, key)
    owner:SetScript("OnEnter", function(frame)
        ns.Tip.Open(self.env, frame, function(tip)
            tip:Title(L["OPT_" .. key])
            tip:Details({ L["OPT_TIP_" .. key] }, L.TIP_SHIFT_MORE)
        end)
    end)
    owner:SetScript("OnLeave", function(frame)
        ns.Tip.Close(self.env, frame)
    end)
end

-- A check box with the gold name and, when given, a short line under it.
local function check(self, box, key, y)
    local control = Controls.Check(self.env, box, function(checked)
        change(self, key, checked)
    end)
    control:SetPoint("TOPLEFT", box, "TOPLEFT", 8, y + 2)
    text(box, Style.FONTS.label, 38, y - 2):SetText(L["OPT_" .. key])
    local line = L["SET_LINE_" .. key]
    if line then
        text(box, Style.FONTS.small, 38, y - 18, SettingsPage.LEFT_WIDTH - 50):SetText(line)
    end
    tooltip(self, control, key)
    self.controls[key] = control
end

local function label(box, key, y)
    text(box, Style.FONTS.label, 12, y):SetText(L["OPT_" .. key])
end

local function slider(self, box, key, x, y)
    local control = Options.BY_KEY[key]
    label(box, key, y)
    local bar = Controls.Slider(
        self.env,
        box,
        SettingsPage.SLIDER,
        control.min,
        control.max,
        control.step,
        function(value)
            change(self, key, value)
        end
    )
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", x, y)
    bar.valueText = text(box, Style.FONTS.small, x + SettingsPage.SLIDER + 10, y - 1)
    tooltip(self, bar, key)
    self.controls[key] = bar
end

local function hudBox(self, panel)
    local box = Controls.Box(self.env, panel, L.SET_HUD)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -SettingsPage.TOP)
    box:SetSize(SettingsPage.LEFT_WIDTH, SettingsPage.TOP_HEIGHT)
    check(self, box, "hudEnabled", -30)
    check(self, box, "hudLocked", -70)
    check(self, box, "hudZone", -96)
    label(box, "hudLayout", -142)
    local layout = Controls.Dropdown(self.env, box, 120, function()
        local current = Options.Get(self.settings, "hudLayout")
        change(self, "hudLayout", current == "card" and "compact" or "card")
    end)
    layout:SetPoint("TOPLEFT", box, "TOPLEFT", 110, -138)
    self.controls.hudLayout = layout
    slider(self, box, "hudScale", 110, -172)
    slider(self, box, "hudOpacity", 110, -200)
end

local function infoBox(self, panel, height)
    local box = Controls.Box(self.env, panel, L.SET_INFO)
    local top = SettingsPage.TOP + SettingsPage.TOP_HEIGHT + 6
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -top)
    box:SetSize(SettingsPage.LEFT_WIDTH, height)
    check(self, box, "tooltipLine", -30)
    check(self, box, "summaryChat", -70)
    check(self, box, "minimapShown", -110)
    check(self, box, "reloadReminder", -136)
end

local function previewBox(self, panel, x, width)
    local box = Controls.Box(self.env, panel, L.SET_PREVIEW)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -SettingsPage.TOP)
    box:SetSize(width, SettingsPage.TOP_HEIGHT)
    self.preview = HudCard.Create(self.env, box)
    for _, view in ipairs({ self.preview.card, self.preview.compact }) do
        view:SetPoint("TOP", box, "TOP", 0, -36)
    end
    local note = box:CreateFontString(nil, "OVERLAY", Style.FONTS.secondary)
    note:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
    note:SetWidth(width - 24)
    note:SetJustifyH("LEFT")
    note:SetText(L.SET_PREVIEW_NOTE)
end

local function advancedBox(self, panel, x, width, height)
    local box = Controls.Box(self.env, panel, L.SET_ADVANCED)
    local top = SettingsPage.TOP + SettingsPage.TOP_HEIGHT + 6
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -top)
    box:SetSize(width, height)
    slider(self, box, "countBelow", 150, -30)
    slider(self, box, "greyBelow", 150, -54)
    slider(self, box, "activeCap", 150, -78)
    text(box, Style.FONTS.secondary, 12, -102, width - 24):SetText(L.SET_ADVANCED_NOTE)
    local previous
    for _, data in ipairs(SettingsPage.DATA) do
        local button = Controls.Button(self.env, box, 104, function()
            ns.Commands.Dispatch(data[2])
        end)
        button:SetText(L[data[1]])
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            button:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
        end
        previous = button
    end
end

-- Puts every setting of this page back to its default (the helpers and positions stay).
function SettingsPage:Defaults()
    for _, control in ipairs(Options.CONTROLS) do
        if control.page == SettingsPage.KEY then
            if
                Options.Set(self.settings, control.key, Options.Default(control.key))
                and ns.ApplySetting
            then
                ns.ApplySetting(control.key)
            end
        end
    end
    self:Draw()
end

local function defaultsButton(self, panel)
    local button = Controls.Button(self.env, panel, 100, function()
        self.confirm = self.confirm or ns.Confirm.Create(self.env)
        self.confirm:Ask(L.SET_DEFAULTS_ASK, L.SET_DEFAULTS, function()
            self:Defaults()
        end)
    end)
    button:SetText(L.SET_DEFAULTS)
    button:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, MainWindow.CONTROLS_Y)
    self.defaultsButton = button
end

-- Builds the page on panel (the main window's page frame).
function SettingsPage.Build(window, panel)
    local self = setmetatable(
        { env = window.env, settings = ns.db.settings, panel = panel, controls = {} },
        SettingsPage
    )
    local height = MainWindow.HEIGHT - SettingsPage.TOP - SettingsPage.TOP_HEIGHT - 6 - 14
    local x = 14 + SettingsPage.LEFT_WIDTH + SettingsPage.GAP
    local width = MainWindow.WIDTH - 14 - x
    hudBox(self, panel)
    infoBox(self, panel, height)
    previewBox(self, panel, x, width)
    advancedBox(self, panel, x, width, height)
    defaultsButton(self, panel)
    ns.settingsPage = self
    return self
end

local function valueText(key, value)
    if SettingsPage.PERCENT[key] then
        value = floor(value * 100 + 0.5)
    end
    return format(L[SettingsPage.FORMATS[key]], value)
end

-- Shows every control's saved value and draws the preview.
function SettingsPage:Draw()
    for key, control in pairs(self.controls) do
        local value = Options.Get(self.settings, key)
        local kind = Options.BY_KEY[key].kind
        if kind == "checkbox" then
            control:SetChecked(value)
        elseif kind == "slider" then
            control:SetValue(value)
            control.valueText:SetText(valueText(key, value))
        else
            control:SetText(L["SET_LAYOUT_" .. value])
        end
    end
    local layout = Options.Get(self.settings, "hudLayout")
    HudCard.Draw(self.preview, ns.HudCardModel.Sample(), layout)
    local view = HudCard.Shown(self.preview, layout)
    local scale = Options.Get(self.settings, "hudScale")
    view:SetScale(scale > SettingsPage.PREVIEW_MAX and SettingsPage.PREVIEW_MAX or scale)
    view:SetAlpha(Options.Get(self.settings, "hudOpacity"))
end

MainWindow.Register({
    key = SettingsPage.KEY,
    icon = SettingsPage.ICON,
    label = L.PAGE_SETTINGS,
    order = 40,
    build = SettingsPage.Build,
    show = function()
        ns.settingsPage:Draw()
    end,
})
