local addon = require("spec.helpers.addon")

describe("Commands", function()
    local ns, printed

    before_each(function()
        printed = {}
        ns = {
            Print = function(text)
                printed[#printed + 1] = text
            end,
        }
        addon.load({
            "Locale.lua",
            "Serializer.lua",
            "Logger.lua",
            "Guard.lua",
            "ApiList.lua",
            "Steps.lua",
            "Progress.lua",
            "View.lua",
            "Commands.lua",
        }, ns)
    end)

    local function output()
        return table.concat(printed, "\n")
    end

    it("shows help for an empty command", function()
        ns.Commands.Dispatch("")
        assert.truthy(output():find("/fmp help", 1, true))
        assert.truthy(output():find("/fmp status", 1, true))
        assert.truthy(output():find("Current step: -", 1, true))
        assert.truthy(output():find("SavedVariables\\FishingMasteryProbe.lua", 1, true))
    end)

    it("names an unknown command and then shows help", function()
        ns.Commands.Dispatch("  Nope ")
        assert.are.equal("Unknown command: nope", printed[1])
        assert.truthy(output():find("Commands:", 1, true))
    end)

    it("shows the current step and status once the logger exists", function()
        local store = {}
        ns.logger = ns.Logger.New(store, {
            now = function()
                return 0
            end,
            sanitize = ns.Serializer.Sanitize,
        })
        ns.logger:SetStep("S2")
        ns.logger:StartSession("abc", "0.1.0")
        ns.Commands.Dispatch("HELP")
        assert.truthy(output():find("Current step: S2", 1, true))
        printed = {}
        ns.Commands.Dispatch("status")
        assert.are.equal(
            "Session abc, version 0.1.0: 1 entries (cap 20000), 0 dropped, 0 Lua errors",
            printed[1]
        )
        assert.are.equal("Login snapshot (S0): not run yet", printed[2])
        printed = {}
        ns.snapshot = { count = 24, supported = 35 }
        ns.Commands.Dispatch("status")
        assert.are.equal(
            "Login snapshot (S0): 24 entries, 35 of " .. #ns.ApiList.EVENTS .. " events registered",
            printed[2]
        )
    end)

    it("calls onEmpty for a bare /fmp only, then shows help", function()
        local opened = 0
        ns.Commands.onEmpty = function()
            opened = opened + 1
        end
        ns.Commands.Dispatch("   ")
        assert.are.equal(1, opened)
        assert.truthy(output():find("Type /fmp to show or hide", 1, true))
        ns.Commands.Dispatch("help")
        ns.Commands.Dispatch("nope")
        assert.are.equal(1, opened)
    end)

    it("shows the guided run step and counter in status", function()
        ns.logger = ns.Logger.New({}, {
            now = function()
                return 0
            end,
            sanitize = ns.Serializer.Sanitize,
        })
        ns.progress = ns.Progress.New({ step = "S3" }, ns.Steps, { log = function() end })
        ns.Commands.Dispatch("status")
        assert.are.equal("Guided run: step S3 (not started), Catches: 0 / 5", printed[#printed])
        ns.progress:Start()
        ns.progress:Observe("attempt", { outcome = "catch" })
        ns.Commands.Dispatch("status")
        assert.are.equal("Guided run: step S3 (started), Catches: 1 / 5", printed[#printed])
        ns.progress = ns.Progress.New({ step = "S1" }, ns.Steps, { log = function() end })
        ns.Commands.Dispatch("status")
        assert.are.equal("Guided run: step S1 (not started)", printed[#printed])
    end)

    it("reports that the probe is loading before the logger exists", function()
        ns.Commands.Dispatch("status")
        assert.are.equal("The probe is still loading.", printed[1])
    end)
end)
