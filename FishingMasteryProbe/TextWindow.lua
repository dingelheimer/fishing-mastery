-- Scrollable text window for /fmp report and /fmp export. The text sits in a read-only
-- multi-line edit box, so it can be selected and copied; long texts are split into pages.
local _, ns = ...

local setmetatable, format, max, min = setmetatable, string.format, math.max, math.min
local L = ns.L

local TextWindow = {}
TextWindow.__index = TextWindow
ns.TextWindow = TextWindow

TextWindow.WIDTH = 600
TextWindow.HEIGHT = 460
TextWindow.SCROLL_TEMPLATE = "UIPanelScrollFrameTemplate"
TextWindow.FONT = "ChatFontNormal"
TextWindow.POSITION_KEY = "textWindow"

local function button(env, parent, label, width, onClick)
    local b = ns.Window.CreateFrame(env, "Button", parent, ns.Window.BUTTON_TEMPLATE)
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", ns.Guard.Wrap("text:click", onClick))
    return b
end

local function buildEditBox(self, env, frame)
    local scroll = ns.Window.CreateFrame(env, "ScrollFrame", frame, TextWindow.SCROLL_TEMPLATE)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -54)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 46)
    local edit = env.CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(TextWindow.FONT)
    edit:SetWidth(TextWindow.WIDTH - 60)
    -- Read-only: typing restores the shown text.
    edit:SetScript(
        "OnTextChanged",
        ns.Guard.Wrap("text:changed", function(box, userInput)
            if userInput then
                box:SetText(self.pages[self.page] or "")
            end
        end)
    )
    edit:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
        frame:Hide()
    end)
    scroll:SetScrollChild(edit)
    self.scroll, self.edit = scroll, edit
end

-- store: db.progress (the window position is saved there).
function TextWindow.Create(env, store)
    local self = setmetatable({ env = env, pages = {}, page = 1 }, TextWindow)
    local frame = ns.Window.CreateFrame(env, "Frame", env.UIParent, ns.Window.TEMPLATE)
    self.frame = frame
    frame:SetSize(TextWindow.WIDTH, TextWindow.HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    ns.Window.RestorePosition(frame, env, store, TextWindow.POSITION_KEY)
    ns.Window.MakeMovable(frame, store, TextWindow.POSITION_KEY)

    self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.title:SetPoint("TOP", frame, "TOP", 0, -6)
    self.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -32)
    self.hint:SetWidth(TextWindow.WIDTH - 32)
    self.hint:SetJustifyH("LEFT")
    buildEditBox(self, env, frame)

    self.selectButton = button(env, frame, L.BUTTON_SELECT_ALL, 100, function()
        self:SelectAll()
    end)
    self.selectButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    self.prevButton = button(env, frame, L.BUTTON_PREV, 70, function()
        self:SetPage(self.page - 1)
    end)
    self.prevButton:SetPoint("LEFT", self.selectButton, "RIGHT", 6, 0)
    self.nextButton = button(env, frame, L.BUTTON_NEXT, 70, function()
        self:SetPage(self.page + 1)
    end)
    self.nextButton:SetPoint("LEFT", self.prevButton, "RIGHT", 6, 0)
    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.pageText:SetPoint("LEFT", self.nextButton, "RIGHT", 10, 0)
    self.closeButton = button(env, frame, L.BUTTON_CLOSE, 80, function()
        frame:Hide()
    end)
    self.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    frame:Hide()
    return self
end

-- Shows a list of page texts under a title; hint: the line above the text.
function TextWindow:Open(title, hint, pages)
    self.title:SetText(title)
    self.hint:SetText(hint or "")
    self.pages = pages
    self.frame:Show()
    self:SetPage(1)
end

function TextWindow:SetPage(page)
    local count = #self.pages
    self.page = max(1, min(page, max(count, 1)))
    self.edit:SetText(self.pages[self.page] or "")
    self.edit:SetCursorPosition(0)
    local paged = count > 1
    self.prevButton:SetShown(paged)
    self.nextButton:SetShown(paged)
    self.prevButton:SetEnabled(self.page > 1)
    self.nextButton:SetEnabled(self.page < count)
    self.pageText:SetText(paged and format(L.PAGE, self.page, count) or "")
end

-- Selects the whole page text for Ctrl+C.
function TextWindow:SelectAll()
    self.edit:SetFocus()
    self.edit:HighlightText()
end

function TextWindow:IsShown()
    return self.frame:IsShown()
end

function TextWindow:Text()
    return self.edit:GetText()
end
