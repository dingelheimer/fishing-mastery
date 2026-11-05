-- Scrollable text window. Export mode shows read-only pages to select and copy; import mode is
-- an empty editable box with an Import button. Adapted from FishingMasteryProbe/TextWindow.lua.
local _, ns = ...

local setmetatable, format, max, min = setmetatable, string.format, math.max, math.min
local L = ns.L
local Frames = ns.Frames

local TextWindow = {}
TextWindow.__index = TextWindow
ns.TextWindow = TextWindow

TextWindow.WIDTH = 600
TextWindow.HEIGHT = 460
TextWindow.SCROLL_TEMPLATE = "UIPanelScrollFrameTemplate"
TextWindow.FONT = "ChatFontNormal"
TextWindow.POSITION_KEY = "textWindow"

local function buildEditBox(self, env, frame)
    local scroll = Frames.Create(env, "ScrollFrame", frame, TextWindow.SCROLL_TEMPLATE)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -54)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 46)
    local edit = env.CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(TextWindow.FONT)
    edit:SetWidth(TextWindow.WIDTH - 60)
    -- In export mode the box is read-only: typing restores the shown page.
    edit:SetScript(
        "OnTextChanged",
        ns.Guard.Wrap("text:changed", function(box, userInput)
            if userInput and not self.onSubmit then
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

-- store: FishingMasteryCharDB.ui (the window position is saved there).
function TextWindow.Create(env, store)
    local self = setmetatable({ env = env, pages = {}, page = 1 }, TextWindow)
    local frame = Frames.Create(env, "Frame", env.UIParent, Frames.TEMPLATE)
    self.frame = frame
    frame:SetSize(TextWindow.WIDTH, TextWindow.HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    Frames.RestorePosition(frame, env, store, TextWindow.POSITION_KEY)
    Frames.MakeMovable(frame, store, TextWindow.POSITION_KEY)

    self.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.title:SetPoint("TOP", frame, "TOP", 0, -6)
    self.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -32)
    self.hint:SetWidth(TextWindow.WIDTH - 32)
    self.hint:SetJustifyH("LEFT")
    buildEditBox(self, env, frame)

    self.selectButton = Frames.Button(env, frame, L.BUTTON_SELECT_ALL, 100, function()
        self:SelectAll()
    end)
    self.selectButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    self.prevButton = Frames.Button(env, frame, L.BUTTON_PREV, 70, function()
        self:SetPage(self.page - 1)
    end)
    self.prevButton:SetPoint("LEFT", self.selectButton, "RIGHT", 6, 0)
    self.nextButton = Frames.Button(env, frame, L.BUTTON_NEXT, 70, function()
        self:SetPage(self.page + 1)
    end)
    self.nextButton:SetPoint("LEFT", self.prevButton, "RIGHT", 6, 0)
    self.pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.pageText:SetPoint("LEFT", self.nextButton, "RIGHT", 10, 0)
    self.submitButton = Frames.Button(env, frame, L.BUTTON_IMPORT, 90, function()
        if self.onSubmit then
            self.onSubmit(self.edit:GetText())
        end
    end)
    self.submitButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    self.closeButton = Frames.Button(env, frame, L.BUTTON_CLOSE, 80, function()
        frame:Hide()
    end)
    self.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    frame:Hide()
    return self
end

-- Export mode: read-only pages under a title.
function TextWindow:Open(title, hint, pages)
    self.onSubmit = nil
    self.title:SetText(title)
    self.hint:SetText(hint or "")
    self.pages = pages
    self.selectButton:Show()
    self.submitButton:Hide()
    self.frame:Show()
    self:SetPage(1)
end

-- Import mode: an empty editable box; onSubmit(text) runs on the Import button.
function TextWindow:OpenInput(title, hint, onSubmit)
    self.onSubmit = onSubmit
    self.title:SetText(title)
    self.hint:SetText(hint or "")
    self.pages, self.page = {}, 1
    self.selectButton:Hide()
    self.prevButton:Hide()
    self.nextButton:Hide()
    self.pageText:SetText("")
    self.submitButton:Show()
    self.edit:SetText("")
    self.frame:Show()
    self.edit:SetFocus()
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

function TextWindow:Text()
    return self.edit:GetText()
end
