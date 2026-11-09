-- The Helpers page of the main window (Draft 3, Story 9.6; /fm helpers opens it): "Casting" and
-- "While fishing" with one row per helper (check box, one line, live state tag), the casting key
-- with its key-binding button, "Right now" (what the smart lure would do in this water), "This
-- login" (the /fm helpers counts), and the other-addon warning. The settings are the same keys as
-- before (Options); a change applies at once (ns.ApplySetting). Redrawn every second while shown.
-- Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, ipairs, format = setmetatable, ipairs, string.format
local L, Style, Controls, Options, Context = ns.L, ns.Style, ns.Controls, ns.Options, ns.Context
local HelperModel, MainWindow = ns.HelperModel, ns.MainWindow

local HelpersPage = {}
HelpersPage.__index = HelpersPage
ns.HelpersPage = HelpersPage

HelpersPage.KEY = "helpers" -- MainWindow page key
HelpersPage.ICON = "Interface\\Icons\\INV_Fishingpole_02"
HelpersPage.CAST_ICON = "Interface\\Icons\\Trade_Fishing"
HelpersPage.TOP, HelpersPage.LEFT_WIDTH, HelpersPage.GAP = 62, 440, 12
HelpersPage.NOW_HEIGHT = 110
HelpersPage.REFRESH = 1 -- seconds between redraws while the page is shown
-- Tag colors by state kind: text color and background tint.
HelpersPage.TAGS = {
    ready = { Style.GREEN, { 0.12, 1, 0, 0.15 } },
    on = { Style.GREEN, { 0.12, 1, 0, 0.15 } },
    active = { Style.GREEN, { 0.12, 1, 0, 0.15 } },
    off = { Style.GREY, { 1, 1, 1, 0.08 } },
    blocked = { Style.ORANGE, { 1, 0.5, 0, 0.15 } },
}

local function text(parent, font, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then
        fs:SetWidth(width)
    end
    fs:SetJustifyH("LEFT")
    return fs
end

local function header(box, label, y)
    text(box, Style.FONTS.label, 10, y):SetText(label)
end

-- One helper row: check box, gold name with the state tag after it, the one-line explanation.
local function helperRow(self, box, key, y)
    local row = {}
    row.check = Controls.Check(self.env, box, function(checked)
        if Options.Set(self.settings, key, checked) and ns.ApplySetting then
            ns.ApplySetting(key)
        end
        self:Draw()
    end)
    row.check:SetPoint("TOPLEFT", box, "TOPLEFT", 8, y + 2)
    row.label = text(box, Style.FONTS.label, 38, y - 2)
    row.label:SetText(L["HROW_" .. key])
    row.tag = box:CreateFontString(nil, "OVERLAY", Style.FONTS.smallLabel)
    row.tag:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
    row.back = box:CreateTexture(nil, "BORDER")
    row.back:SetPoint("TOPLEFT", row.tag, "TOPLEFT", -4, 2)
    row.back:SetPoint("BOTTOMRIGHT", row.tag, "BOTTOMRIGHT", 4, -2)
    local line = text(box, Style.FONTS.small, 38, y - 18, HelpersPage.LEFT_WIDTH - 50)
    line:SetText(L["HROW_TEXT_" .. key])
    -- The long explanation behind Shift in a tooltip over the name and the line.
    local hover = self.env.CreateFrame("Frame", nil, box)
    hover:SetPoint("TOPLEFT", box, "TOPLEFT", 36, y)
    hover:SetSize(HelpersPage.LEFT_WIDTH - 48, 36)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(owner)
        ns.Tip.Open(self.env, owner, function(tip)
            tip:Title(L["HROW_" .. key])
            tip:Details({ L["OPT_TIP_" .. key] }, L.TIP_SHIFT_MORE)
        end)
    end)
    hover:SetScript("OnLeave", function(owner)
        ns.Tip.Close(self.env, owner)
    end)
    row.hover = hover
    self.rows[key] = row
end

local function castingKey(self, box)
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -32)
    icon:SetTexture(HelpersPage.CAST_ICON)
    text(box, Style.FONTS.label, 48, -32):SetText(L.HKEY)
    text(box, Style.FONTS.small, 48, -48, 250):SetText(L.HKEY_TEXT)
    self.keyButton = ns.KeyButton.Create(self.env, box, 120)
    self.keyButton:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -34)
end

local function helpersBox(self, panel, height)
    local box = Controls.Box(self.env, panel, L.HGROUP_casting)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -HelpersPage.TOP)
    box:SetSize(HelpersPage.LEFT_WIDTH, height)
    castingKey(self, box)
    helperRow(self, box, "doubleClick", -92)
    helperRow(self, box, "autoLure", -136)
    header(box, L.HGROUP_fishing, -188)
    helperRow(self, box, "loudSplash", -212)
    helperRow(self, box, "hideUI", -256)
    self.conflict = text(box, Style.FONTS.small, 12, -310, HelpersPage.LEFT_WIDTH - 24)
    self.conflict:SetTextColor(Style.ORANGE[1], Style.ORANGE[2], Style.ORANGE[3])
end

local function nowBox(self, panel, x, width)
    local box = Controls.Box(self.env, panel, L.HNOW)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -HelpersPage.TOP)
    box:SetSize(width, HelpersPage.NOW_HEIGHT)
    self.nowIcon = box:CreateTexture(nil, "ARTWORK")
    self.nowIcon:SetSize(30, 30)
    self.nowIcon:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -32)
    self.nowTitle = text(box, Style.FONTS.value, 48, -32, width - 58)
    self.nowSub = text(box, Style.FONTS.small, 48, -50, width - 58)
    self.nowDetail = text(box, Style.FONTS.secondary, 48, -66, width - 58)
end

local function loginBox(self, panel, x, width, height)
    local box = Controls.Box(self.env, panel, L.HLOGIN)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -HelpersPage.TOP - HelpersPage.NOW_HEIGHT - 6)
    box:SetSize(width, height)
    self.loginRows = {}
    for i = 1, #HelperModel.Login({}) do
        local y = -32 - (i - 1) * 22
        local stripe = box:CreateTexture(nil, "BACKGROUND")
        stripe:SetPoint("TOPLEFT", box, "TOPLEFT", 6, y + 3)
        stripe:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -6, y - 19)
        stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and Style.STRIPE[4] or 0)
        local value = box:CreateFontString(nil, "OVERLAY", Style.FONTS.small)
        value:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, y)
        value:SetJustifyH("RIGHT")
        self.loginRows[i] = { label = text(box, Style.FONTS.small, 12, y), value = value }
    end
    local note = box:CreateFontString(nil, "OVERLAY", Style.FONTS.secondary)
    note:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
    note:SetWidth(width - 24)
    note:SetJustifyH("LEFT")
    note:SetText(L.HLOGIN_NOTE)
end

-- Builds the page on panel (the main window's page frame).
function HelpersPage.Build(window, panel)
    local self = setmetatable({
        env = window.env,
        settings = ns.db.settings,
        panel = panel,
        rows = {},
    }, HelpersPage)
    local height = MainWindow.HEIGHT - HelpersPage.TOP - 14
    local x = 14 + HelpersPage.LEFT_WIDTH + HelpersPage.GAP
    local width = MainWindow.WIDTH - 14 - x
    local note = panel:CreateFontString(nil, "OVERLAY", Style.FONTS.secondary)
    note:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, MainWindow.NAME_Y)
    note:SetText(L.HELPERS_NOTE)
    helpersBox(self, panel, height)
    nowBox(self, panel, x, width)
    loginBox(self, panel, x, width, height - HelpersPage.NOW_HEIGHT - 6)
    ns.helpersPage = self
    return self
end

local function drawRows(self)
    local env = self.env
    local doubleCast = ns.doubleCast
    local rows = HelperModel.Rows({
        settings = self.settings,
        bound = ns.KeyButton.Current(env) ~= nil,
        blocked = doubleCast and ns.DoubleClick.Blocked(doubleCast:State()) or nil,
        splashActive = ns.soundBoost and ns.soundBoost:Active() or false,
        hidden = ns.hideUI and ns.hideUI.hidden or false,
    })
    for _, data in ipairs(rows) do
        local row = self.rows[data.key]
        local colors = HelpersPage.TAGS[data.state.kind]
        row.check:SetChecked(data.on)
        row.tag:SetText(data.state.text)
        row.tag:SetTextColor(colors[1][1], colors[1][2], colors[1][3])
        row.back:SetColorTexture(colors[2][1], colors[2][2], colors[2][3], colors[2][4])
    end
end

local function drawNow(self)
    local env = self.env
    local now = HelperModel.Now(ns.SmartLure.Now(env, ns.area, ns.Journal))
    local icon = now.lure and Context.Call(env, "C_Item.GetItemIconByID", now.lure)
    self.nowIcon:SetTexture(icon)
    self.nowIcon:SetShown(icon ~= nil)
    self.nowTitle:SetText(now.title)
    self.nowSub:SetText(now.sub)
    self.nowDetail:SetText(now.detail)
end

local function drawLogin(self)
    local status = ns.helperStatus or {}
    local rows = HelperModel.Login({
        presses = status.presses,
        casts = status.casts,
        doubled = ns.doubleCast and ns.doubleCast.armedCount,
        hides = ns.hideUI and ns.hideUI.hides,
    })
    for i, row in ipairs(rows) do
        self.loginRows[i].label:SetText(row.label)
        self.loginRows[i].value:SetText(Style.Number(row.value))
    end
end

-- Draws every part from the helpers' current state.
function HelpersPage:Draw()
    drawRows(self)
    self.keyButton:Refresh()
    drawNow(self)
    drawLogin(self)
    local conflict = ns.DoubleCast.Conflict(self.env)
    self.conflict:SetText(conflict and format(L.HELPER_CONFLICT, conflict) or "")
end

-- Redraws every REFRESH seconds while the page is visible (one timer at a time).
function HelpersPage:Refresh()
    if self.ticking or not self.panel:IsVisible() then
        return
    end
    self.ticking = true
    Context.Call(
        self.env,
        "C_Timer.After",
        HelpersPage.REFRESH,
        ns.Guard.Wrap("helpers:refresh", function()
            self.ticking = false
            if self.panel:IsVisible() then
                self:Draw()
                self:Refresh()
            end
        end)
    )
end

MainWindow.Register({
    key = HelpersPage.KEY,
    icon = HelpersPage.ICON,
    label = L.PAGE_HELPERS,
    order = 30,
    build = HelpersPage.Build,
    show = function()
        local page = ns.helpersPage
        page:Draw()
        page:Refresh()
    end,
})
