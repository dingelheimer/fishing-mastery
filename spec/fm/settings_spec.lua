-- Settings defaults, controls, and proxy; minimap button angle math; the idle cap T in the totals.
local addon = require("spec.helpers.addon")

describe("FishingMastery settings and minimap math", function()
    local ns

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "Options.lua",
            "Codec.lua",
            "History.lua",
            "Totals.lua",
            "Stats.lua",
            "MinimapModel.lua",
        }, nil, "FishingMastery")
    end)

    local function near(expected, actual)
        assert.is_true(math.abs(expected - actual) < 1e-6, tostring(actual))
    end

    describe("Options", function()
        it("keeps every default in one table and reads them from empty settings", function()
            local settings = {}
            local expected = {
                hudEnabled = true,
                hudLocked = false,
                hudText = false,
                hudZone = true,
                hudScale = 1,
                summaryChat = false,
                minimapShown = true,
                tooltipLine = true,
                reloadReminder = true,
                countBelow = 10,
                greyBelow = 30,
                activeCap = 60,
            }
            for _, control in ipairs(ns.Options.CONTROLS) do
                assert.are.equal(expected[control.key], ns.Options.Get(settings, control.key))
                assert.are.equal(expected[control.key], ns.Options.Default(control.key))
            end
            assert.are.equal(12, #ns.Options.CONTROLS)
            -- Hud, Summary, Stats, and Totals take their defaults from the same table.
            assert.are.equal(10, ns.Stats.DEFAULTS.countBelow)
            assert.are.equal(60, ns.Totals.ACTIVE_CAP)
        end)

        it("sets values in the saved shapes, clamps sliders, and ignores wrong types", function()
            local settings = { hud = { style = "full" } }
            assert.is_true(ns.Options.Set(settings, "hudText", true))
            assert.are.equal("text", settings.hud.style)
            assert.is_true(ns.Options.Set(settings, "summaryChat", true))
            assert.are.same({ style = "chat" }, settings.summary)
            assert.is_true(ns.Options.Set(settings, "reloadReminder", false))
            assert.is_false(settings.reloadReminder)
            assert.is_true(ns.Options.Set(settings, "hudScale", 3))
            assert.are.equal(2, settings.hud.scale)
            assert.is_true(ns.Options.Set(settings, "hudScale", 0.83))
            near(0.85, settings.hud.scale)
            assert.is_true(ns.Options.Set(settings, "activeCap", 12))
            assert.are.equal(30, settings.thresholds.activeCap)
            assert.is_false(ns.Options.Set(settings, "activeCap", 30)) -- unchanged
            assert.is_false(ns.Options.Set(settings, "countBelow", "7"))
            assert.is_false(ns.Options.Set(settings, "hudLocked", 1))
            assert.is_false(ns.Options.Set(settings, "nothing", true))
        end)

        it("reports changes made through the proxy", function()
            local settings, changed = {}, {}
            local proxy = ns.Options.Proxy(settings, function(key)
                changed[#changed + 1] = key
            end)
            assert.is_true(proxy.minimapShown)
            assert.is_false(proxy.hudLocked) -- false stays false
            proxy.minimapShown = false
            proxy.minimapShown = false -- no change, no report
            proxy.greyBelow = 41
            assert.are.same({ "minimapShown", "greyBelow" }, changed)
            assert.are.equal(40, settings.thresholds.greyBelow)
            assert.is_nil(proxy.unknown)
            assert.is_nil(rawget(proxy, "greyBelow"))
        end)
    end)

    describe("MinimapModel", function()
        it("places the button on the edge of a round minimap", function()
            local x, y = ns.MinimapModel.Offset(0, 140, 140)
            near(75, x)
            near(0, y)
            x, y = ns.MinimapModel.Offset(90, 140, 140, "ROUND")
            near(0, x)
            near(75, y)
            x, y = ns.MinimapModel.Offset(225, 140, 140)
            near(-75 * math.sqrt(0.5), x)
            near(-75 * math.sqrt(0.5), y)
        end)

        it("follows square corners and keeps round ones round", function()
            local diagonal = math.sqrt(2 * 75 * 75) - 10 -- pulled 10 px into the corner
            local x, y = ns.MinimapModel.Offset(45, 140, 140, "SQUARE")
            near(diagonal * math.sqrt(0.5), x)
            near(diagonal * math.sqrt(0.5), y)
            x, y = ns.MinimapModel.Offset(30, 140, 140, "SQUARE")
            near(75, x)
            near(diagonal * 0.5, y)
            x = ns.MinimapModel.Offset(45, 140, 140, "CORNER-TOPRIGHT")
            near(75 * math.sqrt(0.5), x) -- the round corner
            x = ns.MinimapModel.Offset(135, 140, 140, "CORNER-TOPRIGHT")
            near(-diagonal * math.sqrt(0.5), x) -- top left is square there
            x = ns.MinimapModel.Offset(45, 140, 140, "UNKNOWN-SHAPE")
            near(75 * math.sqrt(0.5), x)
        end)

        it("finds the cursor angle and reads the saved angle", function()
            near(0, ns.MinimapModel.Angle(100, 100, 150, 100))
            near(90, ns.MinimapModel.Angle(100, 100, 100, 150))
            near(225, ns.MinimapModel.Angle(100, 100, 50, 50))
            assert.are.equal(220, ns.MinimapModel.Saved({}))
            assert.are.equal(10, ns.MinimapModel.Saved({ minimap = { angle = 370 } }))
            assert.are.equal(220, ns.MinimapModel.Saved({ minimap = { angle = "x" } }))
        end)
    end)

    describe("idle cap T", function()
        after_each(function()
            ns.Totals.SetCap(60)
        end)

        it("counts active time with this login's T and marks totals of another T stale", function()
            local old = ns.Totals.New()
            assert.is_nil(old.cap) -- the default T is not stored
            assert.are.equal(45, ns.Totals.SetCap(45))
            assert.is_false(ns.Totals.Current(old))
            local totals = ns.Totals.New()
            assert.are.equal(45, totals.cap)
            assert.is_true(ns.Totals.Current(totals))
            ns.Totals.Add(totals, { t = 1000, map = 1, out = "timeout" })
            ns.Totals.Add(totals, { t = 1050, map = 1, out = "timeout" })
            assert.are.equal(45 + 45, totals.active[1]) -- the 50 s gap counts 45 s
            assert.are.equal(45, ns.Stats.Thresholds({ activeCap = 90 }).activeCap)
            assert.are.equal(60, ns.Totals.SetCap(500)) -- out of range: the default
            assert.is_true(ns.Totals.Current(old))
        end)
    end)
end)
