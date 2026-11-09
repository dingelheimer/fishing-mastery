-- Item tooltip lines (Draft 6): the pure draw and, through every TOC file, the post-call on a fake
-- tooltip (caught items only, one lookup, the setting, secret IDs, guarded errors).
local addon = require("spec.helpers.addon")
local fmboot = require("spec.helpers.fmboot")
local tiplines = require("spec.helpers.tiplines")

describe("FishingMastery item tooltip", function()
    describe("TooltipModel", function()
        local ns

        before_each(function()
            ns = addon.load(
                { "Locale.lua", "LocaleUI.lua", "Style.lua", "TooltipModel.lua" },
                nil,
                "FishingMastery"
            )
        end)

        local function mapName(map)
            return map == 1411 and "Durotar" or nil
        end

        local function lines(entry)
            return tiplines.lines(ns.TooltipModel.Draw(entry, mapName))
        end

        it("names the count and the best water for caught items only", function()
            assert.are.same(
                { " ", "Fishing Mastery = caught 1,412", "Best water = Durotar" },
                lines({ n = 1412, best = 1411 })
            )
            assert.are.same(
                { " ", "Fishing Mastery = caught 2", "Best water = zone 1412" },
                lines({ n = 2, best = 1412 })
            )
            assert.are.same({ " ", "Fishing Mastery = caught 1" }, lines({ n = 1, best = 0 }))
            assert.is_nil(ns.TooltipModel.Draw(nil, mapName))
            assert.is_nil(ns.TooltipModel.Draw({ n = 0 }, mapName))
            assert.is_nil(ns.TooltipModel.Draw({ n = "3" }, mapName))
        end)
    end)

    describe("boot", function()
        local w, postCall, lookups

        before_each(function()
            w = fmboot.new()
            _G.Enum = { TooltipDataType = { Item = 0 } }
            _G.TooltipDataProcessor = {
                AddTooltipPostCall = function(dataType, fn)
                    assert.are.equal(0, dataType)
                    postCall = fn
                end,
            }
            w.boot(nil, nil)
            w.fire("PLAYER_ENTERING_WORLD", true, false)
            _G.C_Map.GetMapInfo = function(map)
                lookups = lookups + 1
                return map == 1411 and { name = "Durotar" } or nil
            end
            lookups = 0
        end)

        after_each(function()
            w.cleanup()
            _G.Enum, _G.TooltipDataProcessor, _G.issecretvalue = nil, nil, nil
        end)

        -- A tooltip that records its added lines (pairs as "left = right" with the left color),
        -- with lines of another addon already on it.
        local function tooltip()
            local tip = { lines = { "Raw Slitherskin Mackerel", "Other addon: 5 in bank" } }
            function tip:NumLines()
                return #self.lines
            end
            function tip:AddLine(text, _, _, _, wrap)
                self.lines[#self.lines + 1] = text
                self.wrapped = self.wrapped or wrap
            end
            function tip:AddDoubleLine(left, right, r, g, b)
                self.lines[#self.lines + 1] = left .. " = " .. right
                self.colors = self.colors or {}
                self.colors[#self.lines] = { r, g, b }
            end
            return tip
        end

        it("adds the lines of Draft 6 to caught items and nothing to others", function()
            w.catch(5000, 9)
            w.catch(5020, 12)
            local tip = tooltip()
            postCall(tip, { id = 6303 })
            assert.are.same({
                "Raw Slitherskin Mackerel",
                "Other addon: 5 in bank",
                " ",
                "Fishing Mastery = caught 2",
                "Best water = Durotar",
            }, tip.lines)
            assert.are.same(w.ns.Style.ADDON, tip.colors[4]) -- the addon color
            assert.are.same(w.ns.Style.GOLD, tip.colors[5])
            assert.is_falsy(tip.wrapped)
            -- The zone name is looked up once by the tooltip and once by the HUD zone line.
            postCall(tip, { id = 6303 })
            assert.are.equal(2, lookups)

            local other = tooltip()
            postCall(other, { id = 2589 })
            postCall(other, { id = "6303" })
            postCall(other, nil)
            assert.are.equal(2, #other.lines)
            assert.are.equal(0, w.ns.Guard.errors)
        end)

        it("follows the setting, skips secret IDs, and keeps errors in the guard", function()
            w.catch(5000, 9)
            local settings = _G.FishingMasteryDB.settings
            w.ns.Options.Set(settings, "tooltipLine", false)
            local tip = tooltip()
            postCall(tip, { id = 6303 })
            assert.are.equal(2, #tip.lines)
            w.ns.Options.Set(settings, "tooltipLine", true)

            _G.issecretvalue = function(value)
                return value == 6303 -- only the item ID is secret
            end
            postCall = nil
            w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB) -- reads issecretvalue at load
            assert.is_function(postCall)
            postCall(tip, { id = 6303 })
            assert.are.equal(2, #tip.lines)
            _G.issecretvalue = nil
            w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)

            postCall({
                AddLine = function()
                    error("tooltip broken")
                end,
            }, { id = 6303 })
            assert.are.equal(1, w.ns.Guard.errors)
            assert.are.equal("tooltip:item", w.ns.recentErrors[1].where)
        end)
    end)
end)
