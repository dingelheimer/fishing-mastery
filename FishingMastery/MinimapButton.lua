-- The own minimap button (no libraries, owner decision 2026-11-05): a round button on the minimap
-- edge, dragged around it (angle saved per character in FishingMasteryCharDB.ui.minimap), left
-- click toggles the main window (Shift: its Journal page), right click opens the settings,
-- tooltip with the session, the skill, and the click hints (MinimapModel.Tip). Hidden with the
-- minimap setting. OnUpdate runs only while dragging. Unnamed, insecure frame.
local _, ns = ...

local setmetatable, type = setmetatable, type
local Context, MinimapModel = ns.Context, ns.MinimapModel

local MinimapButton = {}
MinimapButton.__index = MinimapButton
ns.MinimapButton = MinimapButton

MinimapButton.SIZE = 31
MinimapButton.ICON = "Interface\\Icons\\Trade_Fishing"
MinimapButton.BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
MinimapButton.BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"
MinimapButton.HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

-- deps: { env, settings (db.settings), store (FishingMasteryCharDB.ui), hud, toggleWindow(),
-- toggleJournal() (Shift + left click), openSettings() }.
function MinimapButton.Start(deps)
    local self = setmetatable({
        env = deps.env,
        settings = deps.settings,
        store = deps.store,
        hud = deps.hud,
        toggleWindow = deps.toggleWindow,
        toggleJournal = deps.toggleJournal,
        openSettings = deps.openSettings,
    }, MinimapButton)
    self:Update()
    return self
end

local function texture(button, path, size, layer, point)
    local tex = button:CreateTexture(nil, layer)
    tex:SetTexture(path)
    tex:SetSize(size, size)
    tex:SetPoint(point, button, point, 0, 0)
    return tex
end

-- Places the button at its saved angle.
function MinimapButton:Place()
    local minimap = self.env.Minimap
    local shape = Context.Call(self.env, "GetMinimapShape")
    local x, y = MinimapModel.Offset(
        MinimapModel.Saved(self.store),
        minimap:GetWidth(),
        minimap:GetHeight(),
        shape
    )
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

local function dragUpdate(self)
    local env, minimap = self.env, self.env.Minimap
    local px, py = env.GetCursorPosition()
    local scale = minimap:GetEffectiveScale()
    local cx, cy = minimap:GetCenter()
    local store = self.store
    store.minimap = type(store.minimap) == "table" and store.minimap or {}
    store.minimap.angle = MinimapModel.Angle(cx, cy, px / scale, py / scale)
    self:Place()
end

-- The MinimapModel.Tip input: the open session's catches and active time, the Fishing skill.
function MinimapButton:TipInput()
    local rank, _, cap = Context.Fishing(self.env)
    local input = { rank = rank, cap = cap }
    local castLog = self.hud and self.hud.castLog
    local session = castLog and castLog:Session()
    if session then
        local model = self.hud:Model(session)
        input.catches, input.active = model.catches, model.active
    end
    return input
end

function MinimapButton:ShowTooltip(owner)
    ns.Tip.Open(self.env, owner, MinimapModel.Tip(self:TipInput()), "ANCHOR_LEFT")
end

local function build(self)
    local env = self.env
    local button = env.CreateFrame("Button", nil, env.Minimap)
    self.button = button
    button:SetSize(MinimapButton.SIZE, MinimapButton.SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    texture(button, MinimapButton.BACKGROUND, 20, "BACKGROUND", "CENTER")
    self.icon = texture(button, MinimapButton.ICON, 18, "ARTWORK", "CENTER")
    texture(button, MinimapButton.BORDER, 53, "OVERLAY", "TOPLEFT")
    button:SetHighlightTexture(MinimapButton.HIGHLIGHT)
    button:SetScript(
        "OnClick",
        ns.Guard.Wrap("minimap:click", function(_, mouseButton)
            if mouseButton == "RightButton" then
                self.openSettings()
            elseif ns.Context.Call(env, "IsShiftKeyDown") and self.toggleJournal then
                self.toggleJournal()
            else
                self.toggleWindow()
            end
        end)
    )
    button:SetScript(
        "OnDragStart",
        ns.Guard.Wrap("minimap:drag", function(b)
            b:SetScript(
                "OnUpdate",
                ns.Guard.Wrap("minimap:move", function()
                    dragUpdate(self)
                end)
            )
        end)
    )
    button:SetScript("OnDragStop", function(b)
        b:SetScript("OnUpdate", nil)
    end)
    button:SetScript(
        "OnEnter",
        ns.Guard.Wrap("minimap:tooltip", function(b)
            self:ShowTooltip(b)
        end)
    )
    button:SetScript("OnLeave", function(b)
        ns.Tip.Close(env, b)
    end)
end

-- Shows the button at its angle, or hides it when the setting is off (or there is no minimap).
function MinimapButton:Update()
    local shown = ns.Options.Get(self.settings, "minimapShown") and self.env.Minimap ~= nil
    if not shown then
        if self.button then
            self.button:Hide()
        end
        return
    end
    if not self.button then
        build(self)
    end
    self:Place()
    self.button:Show()
end
