-- The Fishing Mastery window (Epic 9, Draft 1): one portrait frame for every module, with the
-- module tabs on its right edge like the Professions window. Modules register a page
-- (MainWindow.Register); only registered modules get a tab. Each page gets a panel over the whole
-- window and draws its controls and body there; the window draws the page name under the title.
-- Opens on the last page per character (FishingMasteryCharDB.ui.page), position saved per
-- character (ui.main), movable by the title, closes with Escape (UISpecialFrames, which needs
-- the frame's global name). Built on first open. Insecure frames; only the window is named.
local _, ns = ...

local setmetatable, ipairs, pairs, type, pcall, error, sort, remove =
    setmetatable, ipairs, pairs, type, pcall, error, table.sort, table.remove
local L, Frames, Style = ns.L, ns.Frames, ns.Style

local MainWindow = {}
MainWindow.__index = MainWindow
ns.MainWindow = MainWindow

MainWindow.NAME = "FishingMasteryFrame"
MainWindow.WIDTH, MainWindow.HEIGHT = 820, 500
-- Window templates in order (confirmed in game, Story 9.1); the last is the pre-Epic 9 frame.
MainWindow.TEMPLATES = { "ButtonFrameTemplate", "PortraitFrameTemplate", Frames.TEMPLATE }
MainWindow.INSET_TEMPLATE = "InsetFrameTemplate"
MainWindow.TAB_TEMPLATE = "LargeSideTabButtonTemplate"
-- Fallback side tab from Classic art (the spellbook tab).
MainWindow.TAB_TEXTURE = "Interface\\SpellBook\\SpellBook-SkillLineTab"
MainWindow.TAB_HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
MainWindow.TAB_CHECKED = "Interface\\Buttons\\CheckButtonHilight"
MainWindow.ICON = "Interface\\Icons\\Trade_Fishing"
MainWindow.POSITION_KEY = "main" -- FishingMasteryCharDB.ui keys
MainWindow.PAGE_KEY = "page"
MainWindow.OLD_KEYS = { "stats", "journal" } -- positions of the windows before Epic 9
-- Layout (pixels below the window top): page name, page controls, first body line, inset.
MainWindow.NAME_Y, MainWindow.CONTROLS_Y, MainWindow.BODY_Y = -34, -29, -62
MainWindow.INSET_TOP = -56
MainWindow.TAB_TOP, MainWindow.TAB_GAP = -36, -6

-- Registered pages in tab order: { key, icon, label, order, build(window, panel),
-- show(window, panel) }.
MainWindow.pages = {}

local function byOrder(a, b)
    if (a.order or 0) ~= (b.order or 0) then
        return (a.order or 0) < (b.order or 0)
    end
    return a.key < b.key
end

-- Adds a page (a page with the same key is replaced).
function MainWindow.Register(page)
    if type(page) ~= "table" or type(page.key) ~= "string" or type(page.build) ~= "function" then
        error("MainWindow.Register: a page needs a key and build", 2)
    end
    local pages = MainWindow.pages
    for i, existing in ipairs(pages) do
        if existing.key == page.key then
            remove(pages, i)
            break
        end
    end
    pages[#pages + 1] = page
    sort(pages, byOrder)
end

local function find(key)
    for _, page in ipairs(MainWindow.pages) do
        if page.key == key then
            return page
        end
    end
end

-- deps: { env, store (FishingMasteryCharDB.ui) }.
function MainWindow.Start(deps)
    local store = deps.store
    for _, key in ipairs(MainWindow.OLD_KEYS) do
        store[key] = nil
    end
    return setmetatable({ env = deps.env, store = store, panels = {}, tabs = {} }, MainWindow)
end

-- Title, portrait, close button, and inset of the template, or own replacements.
local function decorate(self, frame, template)
    local env = self.env
    if type(frame.SetTitle) == "function" then
        frame:SetTitle(L.MAIN_TITLE)
    else
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", frame, "TOP", 0, -6)
        title:SetText(L.MAIN_TITLE)
    end
    if type(frame.SetPortraitToAsset) == "function" then
        frame:SetPortraitToAsset(MainWindow.ICON)
    end
    -- Our own close script: the template's would hand the frame to the UI panel manager.
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function()
            frame:Hide()
        end)
    end
    local inset = frame.Inset
    if not inset and template == "PortraitFrameTemplate" then
        inset = Frames.Create(env, "Frame", frame, MainWindow.INSET_TEMPLATE)
    end
    if inset then
        ns.Look.Tint(inset, ns.Look.WARM_BODY)
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, MainWindow.INSET_TOP)
        inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4)
    end
end

local function setChecked(tab, checked)
    if type(tab.SetChecked) == "function" then
        tab:SetChecked(checked)
    end
    if tab.SelectedTexture then
        tab.SelectedTexture:SetShown(checked)
    end
end

-- A side tab from Classic art when the template is missing.
local function fallbackTab(env, frame)
    local tab = env.CreateFrame("CheckButton", nil, frame)
    tab:SetSize(32, 32)
    local back = tab:CreateTexture(nil, "BACKGROUND")
    back:SetTexture(MainWindow.TAB_TEXTURE)
    back:SetSize(64, 64)
    back:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 11)
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetAllPoints(tab)
    tab:SetHighlightTexture(MainWindow.TAB_HIGHLIGHT)
    tab.SelectedTexture = tab:CreateTexture(nil, "OVERLAY")
    tab.SelectedTexture:SetTexture(MainWindow.TAB_CHECKED)
    tab.SelectedTexture:SetAllPoints(tab)
    return tab
end

local function sideTab(self, page, previous)
    local env, frame = self.env, self.frame
    local ok, tab = pcall(env.CreateFrame, "CheckButton", nil, frame, MainWindow.TAB_TEMPLATE)
    if not ok or not tab then
        tab = fallbackTab(env, frame)
    end
    if tab.Icon then
        tab.Icon:SetTexture(page.icon)
    end
    if previous then
        tab:SetPoint("TOP", previous, "BOTTOM", 0, MainWindow.TAB_GAP)
    else
        tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, MainWindow.TAB_TOP)
    end
    tab.key = page.key
    tab:SetScript(
        "OnClick",
        ns.Guard.Wrap("main:tab", function()
            self:Select(page.key)
        end)
    )
    tab:SetScript("OnEnter", function(button)
        ns.Tip.Open(env, button, function(tip)
            tip:Title(page.label)
        end, "ANCHOR_RIGHT")
    end)
    tab:SetScript("OnLeave", function(button)
        ns.Tip.Close(env, button)
    end)
    setChecked(tab, false)
    return tab
end

local function build(self)
    local env = self.env
    local frame, template =
        Frames.CreateFirst(env, "Frame", env.UIParent, MainWindow.TEMPLATES, MainWindow.NAME)
    self.frame = frame
    frame:SetSize(MainWindow.WIDTH, MainWindow.HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    Frames.RestorePosition(frame, env, self.store, MainWindow.POSITION_KEY)
    decorate(self, frame, template)
    local handle = env.CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, 0)
    handle:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -28, -24)
    self.handle = handle
    Frames.MakeMovable(frame, self.store, MainWindow.POSITION_KEY, handle)
    self.pageName = frame:CreateFontString(nil, "OVERLAY", Style.FONTS.label)
    self.pageName:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, MainWindow.NAME_Y)
    local special = env.UISpecialFrames
    if type(special) == "table" then
        special[#special + 1] = MainWindow.NAME
    end
    for i, page in ipairs(MainWindow.pages) do
        self.tabs[i] = sideTab(self, page, self.tabs[i - 1])
    end
end

local function panel(self, page)
    local frame = self.env.CreateFrame("Frame", nil, self.frame)
    frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
    self.panels[page.key] = frame
    page.build(self, frame)
    return frame
end

-- Shows the page of key (unknown: the first page); builds its panel on first use.
function MainWindow:Select(key)
    local page = find(key) or MainWindow.pages[1]
    if not page then
        return
    end
    local shown = self.panels[page.key] or panel(self, page)
    self.page = page.key
    self.store[MainWindow.PAGE_KEY] = page.key
    for pageKey, frame in pairs(self.panels) do
        frame:SetShown(pageKey == page.key)
    end
    for _, tab in ipairs(self.tabs) do
        setChecked(tab, tab.key == page.key)
    end
    self.pageName:SetText(page.label)
    if page.show then
        page.show(self, shown)
    end
end

-- Opens the window on the page of key, else on the last page.
function MainWindow:Open(key)
    if not self.frame then
        build(self)
    end
    self.frame:Show()
    self:Select(key or self.store[MainWindow.PAGE_KEY])
end

-- Closes the window when it shows the page of key (any page without a key), else opens it there.
function MainWindow:Toggle(key)
    if self:IsShown(key) then
        self.frame:Hide()
    else
        self:Open(key)
    end
end

-- True while the window is shown (on the page of key, when given).
function MainWindow:IsShown(key)
    return self.frame ~= nil and self.frame:IsShown() and (key == nil or key == self.page)
end
