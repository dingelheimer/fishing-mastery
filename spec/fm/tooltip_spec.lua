-- Item tooltip line: the pure line builder and, through every TOC file, the post-call on a fake
-- tooltip (caught items only, one lookup, the setting, secret IDs, guarded errors).
local addon = require("spec.helpers.addon")
local fmboot = require("spec.helpers.fmboot")

describe("FishingMastery item tooltip line", function()
    describe("TooltipModel", function()
        local ns

        before_each(function()
            ns = addon.load({ "Locale.lua", "TooltipModel.lua" }, nil, "FishingMastery")
        end)

        local function mapName(map)
            return map == 1411 and "Durotar" or nil
        end

        it("names the count and the best zone for caught items only", function()
            local line = ns.TooltipModel.Line({ n = 37, best = 1411 }, mapName)
            assert.are.equal("Fishing Mastery: caught 37x (best: Durotar)", line)
            line = ns.TooltipModel.Line({ n = 2, best = 1412 }, mapName)
            assert.are.equal("Fishing Mastery: caught 2x (best: zone 1412)", line)
            line = ns.TooltipModel.Line({ n = 1, best = 0 }, mapName)
            assert.are.equal("Fishing Mastery: caught 1x", line)
            assert.is_nil(ns.TooltipModel.Line(nil, mapName))
            assert.is_nil(ns.TooltipModel.Line({ n = 0 }, mapName))
            assert.is_nil(ns.TooltipModel.Line({ n = "3" }, mapName))
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

        -- A tooltip that records its added lines, with lines of another addon already on it.
        local function tooltip()
            local tip = { lines = { "Raw Slitherskin Mackerel", "Other addon: 5 in bank" } }
            function tip:AddLine(text, r, g, b)
                self.lines[#self.lines + 1] = text
                self.color = { r, g, b }
            end
            return tip
        end

        it("adds one line to caught items and nothing to others", function()
            w.catch(5000, 9)
            w.catch(5020, 12)
            local tip = tooltip()
            postCall(tip, { id = 6303 })
            assert.are.same({
                "Raw Slitherskin Mackerel",
                "Other addon: 5 in bank",
                "Fishing Mastery: caught 2x (best: Durotar)",
            }, tip.lines)
            postCall(tip, { id = 6303 }) -- the zone name is looked up once
            assert.are.equal(1, lookups)

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
