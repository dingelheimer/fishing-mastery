-- Tooltips of Draft 6 (Story 9.9): the Tip additions (label colors, a custom Shift prompt, writing
-- into a shown tooltip), the minimap tooltip, a sample of the other tooltips through every TOC
-- file, and the rule that only Tip.lua writes tooltip lines and only Tip.Details wraps them.
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")
local fmboot = require("spec.helpers.fmboot")
local statsui = require("spec.helpers.statsui")
local tiplines = require("spec.helpers.tiplines")

describe("FishingMastery tooltips", function()
    describe("Tip additions", function()
        local ns, env, owner

        before_each(function()
            ns = addon.load(
                { "Locale.lua", "LocaleUI.lua", "Guard.lua", "Style.lua", "Tip.lua" },
                nil,
                "FishingMastery"
            )
            env = fakeui.new()
            owner = env.CreateFrame("Frame")
        end)

        it("colors a pair's label and takes a custom Shift prompt", function()
            ns.Tip.Open(env, owner, function(tip)
                tip:Title("Casting key")
                tip:Pair("Fishing Mastery", "caught 3", nil, ns.Style.ADDON)
                tip:Details({ "A long explanation of the casting key." }, ns.L.TIP_SHIFT_MORE)
            end)
            local tip = env.GameTooltip
            assert.are.same(
                { "Casting key", "Fishing Mastery = caught 3", " ", "Hold Shift for more" },
                tip.lines
            )
            assert.are.same({ ns.Style.ADDON, ns.Style.WHITE }, tip.colors[2])
        end)

        it("writes below the lines a shown tooltip already has", function()
            local shown = { lines = { "Raw Slitherskin Mackerel" } }
            function shown:NumLines()
                return #self.lines
            end
            function shown:AddLine(text)
                self.lines[#self.lines + 1] = text
            end
            ns.Tip.Into(shown):Gap():Line("dev line")
            assert.are.same({ "Raw Slitherskin Mackerel", " ", "dev line" }, shown.lines)
        end)

        it("has no wrapped line outside Details", function()
            assert.is_nil(ns.Tip.Text)
            assert.is_nil(ns.Tip.Lines)
            env.shift = true
            ns.Tip.Open(env, owner, function(tip)
                tip:Title("A title that is long enough to wrap if it were allowed to")
                tip:Pair("Label", "value")
                tip:Header("Header")
                tip:Line("A line")
                tip:Gap()
                tip:Hint("Click: do it")
                tip:Details({ "First explanation.", "Second explanation." })
            end)
            local tip = env.GameTooltip
            for i = 1, #tip.lines - 2 do
                assert.is_falsy(tip.wraps[i])
            end
            assert.is_true(tip.wraps[#tip.lines - 1])
            assert.is_true(tip.wraps[#tip.lines])
        end)
    end)

    describe("minimap tooltip", function()
        local ns

        before_each(function()
            ns = addon.load({
                "Locale.lua",
                "LocaleUI.lua",
                "Style.lua",
                "HudModel.lua",
                "MinimapModel.lua",
            }, nil, "FishingMastery")
        end)

        local HINTS = {
            "Left-click: open",
            "Shift-click: journal",
            "Right-click: settings",
            "Drag: move this button",
        }

        local function expected(head)
            local lines = { "Fishing Mastery" }
            for _, line in ipairs(head) do
                lines[#lines + 1] = line
            end
            lines[#lines + 1] = " "
            for _, hint in ipairs(HINTS) do
                lines[#lines + 1] = hint
            end
            return lines
        end

        it("shows the session, the skill, and the click hints as in Draft 6", function()
            local draw = ns.MinimapModel.Tip({ catches = 8, active = 250, rank = 154, cap = 225 })
            assert.are.same(
                expected({ "Session = 8 catches, 4 min", "Fishing = 154 / 225" }),
                tiplines.lines(draw)
            )
        end)

        it("says when no session is open and shows a rank without a cap", function()
            assert.are.same(
                expected({ "Session = none open", "Fishing = 154" }),
                tiplines.lines(ns.MinimapModel.Tip({ rank = 154 }))
            )
            assert.are.same(
                expected({ "Session = 1,204 catches, 1 h 05 min" }),
                tiplines.lines(ns.MinimapModel.Tip({ catches = 1204, active = 3900 }))
            )
        end)
    end)

    describe("other tooltips (boot)", function()
        local w

        before_each(function()
            w = fmboot.new()
            w.boot(nil, nil)
            w.fire("PLAYER_ENTERING_WORLD", true, false)
            statsui.stub(w)
        end)

        after_each(function()
            w.cleanup()
            statsui.cleanup()
        end)

        it("puts a settings control's explanation behind Shift", function()
            _G.SlashCmdList.FM("settings")
            local control = w.ns.settingsPage.controls.hudLocked
            control:GetScript("OnEnter")(control)
            assert.are.same(
                { "Lock its position", " ", "Hold Shift for more" },
                _G.GameTooltip.lines
            )
            local shift = _G.IsShiftKeyDown
            _G.IsShiftKeyDown = function()
                return true
            end
            control:GetScript("OnEnter")(control)
            _G.IsShiftKeyDown = shift
            assert.are.equal("A locked HUD cannot be dragged.", _G.GameTooltip.lines[3])
            assert.are.equal(0, w.ns.Guard.errors)
        end)

        it("shows the day of a heatmap cell in pairs", function()
            local day = w.ns.Heatmap.Tip({ casts = 1204, catches = 1100 }, "2026-11-09")
            assert.are.same(
                { "2026-11-09", "Casts = 1,204", "Catches = 1,100" },
                tiplines.lines(day)
            )
            assert.are.same(
                { "2026-11-08", "No fishing" },
                tiplines.lines(w.ns.Heatmap.Tip({ casts = 0, catches = 0 }, "2026-11-08"))
            )
        end)
    end)

    describe("detail pane", function()
        it(
            "draws gold labels with right-aligned values, tables, and hides what does not fit",
            function()
                local ns = addon.load(
                    { "Locale.lua", "LocaleUI.lua", "Style.lua", "DetailPane.lua" },
                    nil,
                    "FishingMastery"
                )
                local env = fakeui.new()
                local pane = ns.DetailPane.Create(env, env.CreateFrame("Frame"), 0, 0, 246, 70)
                pane:Draw(function(b)
                    b:Title("Raw Brilliant Smallfish")
                    b:Pair("Caught", "28")
                    b:Header({ "Where it bites", "Classic", "Yours" })
                    b:Row({ "Sen'jin Village", "59 %", "1/2" }, { nil, nil, ns.Style.GREY })
                    b:Line("never shown: below the pane's 70 pixels")
                end)
                assert.are.same({
                    "Raw Brilliant Smallfish",
                    "Caught",
                    "28",
                    "Where it bites",
                    "Classic",
                    "Yours",
                    "Sen'jin Village",
                    "59 %",
                    "1/2",
                }, pane:Texts())
                local label, value, grey = pane.cells[2], pane.cells[3], pane.cells[9]
                assert.are.same(ns.Style.GOLD, label.color)
                assert.are.same({ "LEFT", "RIGHT" }, { label.justifyH, value.justifyH })
                assert.are.same(ns.Style.GREY, grey.color)
                assert.is_false(value.wordWrap)
                -- A redraw reuses the font strings and shows only the new rows.
                pane:Draw(function(b)
                    b:Line("Click a fish to see its details.", ns.Style.GREY)
                end)
                assert.are.same({ "Click a fish to see its details." }, pane:Texts())
            end
        )
    end)

    describe("source rule", function()
        -- Lua comments are removed first, so a comment may still name the calls.
        local function code(file)
            local handle = assert(io.open("FishingMastery/" .. file:gsub("\\", "/"), "r"))
            local text = handle:read("*a")
            handle:close()
            text = text:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
            return text
        end

        local CALLS = { ":AddLine%(", ":AddDoubleLine%(", "Tooltip:SetText%(" }

        it("writes tooltip lines only through Tip.lua", function()
            local found = {}
            for _, file in ipairs(addon.tocFiles("FishingMastery")) do
                if file ~= "Tip.lua" and file:find("%.lua$") then
                    local text = code(file)
                    for _, call in ipairs(CALLS) do
                        if text:find(call) then
                            found[#found + 1] = file .. " " .. call
                        end
                    end
                    if text:find("[tT]ip:Text%(") or text:find("Tip%.Lines%(") then
                        found[#found + 1] = file .. " Tip:Text or Tip.Lines"
                    end
                end
            end
            assert.are.same({}, found)
        end)

        it("wraps a tooltip line only in Tip:Details", function()
            local text = code("Tip.lua")
            local wrapped = {}
            for line in text:gmatch("[^\n]+") do
                if line:find("add%(self,.*true%)") then
                    wrapped[#wrapped + 1] = line
                end
            end
            assert.are.same({ "        add(self, line, Style.GREY, true)" }, wrapped)
        end)
    end)
end)
