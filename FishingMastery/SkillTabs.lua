-- Skill and Compare tabs of the stats window (entries as in StatsTabs.lua). Skill: the logged-in
-- character's rank over time (line chart), pace and forecasts, and catches per skill point by
-- rank band; it reads the history in steps (SkillScan) with a progress line in the status.
-- Compare: two groups side by side from the aggregates, chosen with a kind button and, for zones
-- and characters, A and B buttons.
local _, ns = ...

local type, pairs, concat, format, floor, huge =
    type, pairs, table.concat, string.format, math.floor, math.huge
local L, StatsFrame, StatsTabs, StatsView, Stats =
    ns.L, ns.StatsFrame, ns.StatsTabs, ns.StatsView, ns.Stats
local SkillScan, SkillModel, SkillTable, CompareTable =
    ns.SkillScan, ns.SkillModel, ns.SkillTable, ns.CompareTable

local SkillTabs = {}
ns.SkillTabs = SkillTabs

SkillTabs.LINE_WIDTH, SkillTabs.LINE_HEIGHT = 420, 210
SkillTabs.TEXT_X = SkillTabs.LINE_WIDTH + 16

local function currentChar(self)
    local chars = type(self.db.chars) == "table" and self.db.chars or {}
    return chars[self.charKey]
end

local function shown(self, name)
    return self.frame:IsVisible() and ns.StatsWindow.TABS[self.tab] == name
end

local function progressText(self)
    local done, total = SkillScan.Progress(self.skillScan)
    return format(L.SKILL_READING, total > 0 and floor(done / total * 100) or 0)
end

-- Reads the next chunks once per frame while the Skill tab is shown; draws the tab when done.
local function continueScan(self)
    if self.scanPending then
        return
    end
    self.scanPending = true
    self.after(0, function()
        self.scanPending = false
        local char = currentChar(self)
        if not (char and shown(self, "skill")) then
            return
        end
        if SkillScan.Step(self.skillScan, char) then
            self:Render(true)
        else
            self.status:SetText(progressText(self))
            continueScan(self)
        end
    end)
end

local function drawEmpty(self, message)
    self.skillText:SetText("")
    self.rankChart:Draw(L.SKILL_CHART_RANK, nil, message)
    self.paceChart:Draw(L.SKILL_CHART_PACE, nil, message)
end

StatsTabs.skill = {
    build = function(self, panel)
        self.rankChart =
            ns.LineChart.Create(self.env, panel, SkillTabs.LINE_WIDTH, SkillTabs.LINE_HEIGHT)
        self.rankChart.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.skillText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.skillText:SetPoint("TOPLEFT", panel, "TOPLEFT", SkillTabs.TEXT_X, 0)
        self.skillText:SetWidth(StatsFrame.PANEL_WIDTH - SkillTabs.TEXT_X)
        self.skillText:SetJustifyH("LEFT")
        local top = SkillTabs.LINE_HEIGHT + 12
        self.paceChart = ns.BarChart.Create(
            self.env,
            panel,
            StatsFrame.PANEL_WIDTH,
            StatsFrame.PANEL_HEIGHT - top
        )
        self.paceChart.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -top)
    end,
    draw = function(self, input)
        local char = currentChar(self)
        self.skillReading = false
        if not char then
            drawEmpty(self, L.SKILL_NONE)
            return nil
        end
        local view = StatsView.Build({ char })
        self.skillScan = self.skillScan or SkillScan.New()
        local budget = self.after and SkillScan.CHUNKS or huge
        if not SkillScan.Step(self.skillScan, char, budget) then
            self.skillReading = true
            drawEmpty(self, L.SKILL_WAIT)
            continueScan(self)
            return view
        end
        local t = input.thresholds
        local model = SkillModel.Build({
            result = SkillScan.Result(self.skillScan, char),
            rank = char.fishingRank,
            max = char.fishingMax,
            perHour = Stats.CatchesPerHour(view.outcomes, view.active, t),
            thresholds = t,
        })
        if not model then
            drawEmpty(self, L.SKILL_NONE)
            return view
        end
        self.skillModel = model
        self.skillText:SetText(concat(SkillTable.Lines(model, input), "\n"))
        self.rankChart:Draw(L.SKILL_CHART_RANK, SkillTable.RankChart(model, input))
        self.paceChart:Draw(L.SKILL_CHART_PACE, SkillTable.BandChart(model), L.SKILL_CHART_NO_PACE)
        return view
    end,
    status = function(self)
        return self.skillReading and progressText(self) or nil
    end,
}

-- Characters with casts: { { key, name, view } }.
local function charViews(self)
    local list = {}
    for key, entry in pairs(type(self.db.chars) == "table" and self.db.chars or {}) do
        if type(entry) == "table" and type(entry.totals) == "table" then
            list[#list + 1] = { key = key, name = entry.name, view = StatsView.Build({ entry }) }
        end
    end
    return list
end

-- Groups of the chosen kind; pick says whether A and B are chosen from a list.
local function groups(self, kind, input)
    if kind == "char" then
        return CompareTable.Chars(charViews(self)), true, nil
    end
    local view = StatsView.Build(self:Chars())
    if kind == "lure" then
        return CompareTable.Lure(view), false, view
    end
    if kind == "daynight" then
        return CompareTable.DayNight(view, input.hourOffset), false, view
    end
    return CompareTable.Zones(view), true, view
end

-- The next index after i in 1..n that is not other.
local function step(i, n, other)
    local nextIndex = i % n + 1
    if nextIndex == other and n > 1 then
        nextIndex = nextIndex % n + 1
    end
    return nextIndex
end

local function pickButton(self, panel, x, side)
    local button = StatsFrame.Button(self, panel, 200, function()
        local c = self.compare
        if side == "a" then
            c.a = step(c.a, self.compareCount, c.b)
        else
            c.b = step(c.b, self.compareCount, c.a)
        end
    end)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
    return button
end

StatsTabs.compare = {
    scoped = function(self)
        return CompareTable.KINDS[self.compare.kind] ~= "char"
    end,
    build = function(self, panel)
        self.kindButton = StatsFrame.Button(self, panel, 220, function()
            local c = self.compare
            c.kind, c.a, c.b = c.kind % #CompareTable.KINDS + 1, 1, 2
        end)
        self.kindButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.pickA = pickButton(self, panel, 232, "a")
        self.pickB = pickButton(self, panel, 444, "b")
        local height = StatsFrame.PANEL_HEIGHT - 30 - 22
        local area = StatsFrame.Area(self, panel, 0, 30, height)
        self.compareList = ns.StatsList.Create(self.env, area, CompareTable.COLUMNS)
        self.compareHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.compareHint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2)
        self.compareHint:SetWidth(StatsFrame.PANEL_WIDTH - 4)
        self.compareHint:SetJustifyH("LEFT")
    end,
    draw = function(self, input, keepScroll)
        local c = self.compare
        local kind = CompareTable.KINDS[c.kind]
        local list, pick, view = groups(self, kind, input)
        self.compareCount = #list
        self.kindButton:SetText(format(L.CMP_KIND, L["CMP_KIND_" .. kind]))
        local a, b = list[pick and c.a or 1], list[pick and c.b or 2]
        self.pickA:SetShown(pick and a ~= nil)
        self.pickB:SetShown(pick and b ~= nil)
        if not (a and b) then
            self.compareList:SetRows({}, keepScroll)
            self.compareHint:SetText(L.CMP_NEED_TWO)
            return view
        end
        local nameA, nameB = CompareTable.Name(kind, a, input), CompareTable.Name(kind, b, input)
        self.pickA:SetText(format(L.CMP_PICK_A, nameA))
        self.pickB:SetText(format(L.CMP_PICK_B, nameB))
        self.compareList.headers[2]:SetText(nameA)
        self.compareList.headers[3]:SetText(nameB)
        self.compareList:SetRows(CompareTable.Rows(a, b, input.thresholds), keepScroll)
        self.compareHint:SetText(L.CMP_HINT)
        return view
    end,
}
