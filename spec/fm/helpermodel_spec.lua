-- The Helpers page model of Draft 3 (Story 9.6): the helper rows with their live states, the
-- "Right now" texts of the smart lure's choice, and the "This login" counts.
local addon = require("spec.helpers.addon")

describe("FishingMastery helper model", function()
    local ns, HelperModel

    before_each(function()
        ns = addon.load(
            { "Locale.lua", "LocaleHelpers.lua", "LocaleUI.lua", "Options.lua", "HelperModel.lua" },
            nil,
            "FishingMastery"
        )
        HelperModel = ns.HelperModel
    end)

    local function states(input)
        local list = {}
        for _, row in ipairs(HelperModel.Rows(input)) do
            list[row.key] = { row.on, row.state.text, row.state.kind }
        end
        return list
    end

    it("shows every helper off by default, in page order and groups", function()
        local rows = HelperModel.Rows({ settings = {} })
        local order = {}
        for i, row in ipairs(rows) do
            order[i] = row.group .. ":" .. row.key
            assert.is_false(row.on)
            assert.are.same({ text = "off", kind = "off" }, row.state)
        end
        assert.are.same({
            "casting:doubleClick",
            "casting:autoLure",
            "fishing:loudSplash",
            "fishing:hideUI",
        }, order)
        assert.are.equal("Double right-click casting", rows[1].label)
        assert.truthy(rows[1].text:find("pole is equipped", 1, true))
    end)

    it("shows ready, on, active, and blocked states with the reason", function()
        local settings = {
            helpers = { doubleClick = true, autoLure = true, loudSplash = true, hideUI = true },
        }
        local list = states({ settings = settings, blocked = "no-pole" })
        assert.are.same({ true, "no pole equipped", "blocked" }, list.doubleClick)
        assert.are.same({ true, "needs the casting key", "blocked" }, list.autoLure)
        assert.are.same({ true, "on", "on" }, list.loudSplash)
        assert.are.same({ true, "on", "on" }, list.hideUI)

        list = states({ settings = settings, bound = true, splashActive = true, hidden = true })
        assert.are.same({ true, "ready", "ready" }, list.doubleClick)
        assert.are.same({ true, "on", "on" }, list.autoLure)
        assert.are.same({ true, "active", "active" }, list.loudSplash)
        assert.are.same({ true, "active", "active" }, list.hideUI)
        assert.are.equal(
            "in combat",
            states({ settings = settings, blocked = "combat" }).doubleClick[2]
        )
    end)

    local function name(id)
        return ({ [6532] = "Shiny Bauble", [6533] = "Aquadynamic Fish Attractor" })[id]
    end

    it("writes what the smart lure would do right now", function()
        local bauble = { id = 6532, bonus = 25, count = 4 }
        local now = HelperModel.Now({
            choice = { action = "lure", reason = "reaches", lure = bauble, goal = 200 },
            active = { bonus = 25, seconds = 420 },
            name = name,
            zone = "Stranglethorn Vale",
        })
        assert.are.same({
            title = "Shiny Bauble (+25)",
            sub = "would stop getaways in Stranglethorn Vale",
            detail = "4 in your bags; 7 min left on the pole",
            lure = 6532,
        }, now)
        now = HelperModel.Now({
            choice = { reason = "strongest", lure = bauble, goal = 280 },
            name = name,
        })
        assert.are.equal("is your best lure; getaways stop at 280", now.sub)
        assert.are.equal("4 in your bags; no lure on the pole", now.detail)

        local function title(choice, zone)
            local result = HelperModel.Now({ choice = choice, name = name, zone = zone })
            return result.title .. " | " .. result.sub
        end
        assert.are.equal(
            "No lure needed | Your skill already stops getaways here.",
            title({ reason = "enough", goal = 100 })
        )
        assert.are.equal(
            "No usable lure in your bags | Getaways stop at skill 125.",
            title({ reason = "no-lures", goal = 125 })
        )
        assert.are.equal("Fishing skill not known yet | ", title({ reason = "unknown-skill" }))
        assert.are.equal(
            "No water data here | The smart lure uses your strongest lure.",
            title({ reason = "unknown-base" })
        )
        assert.are.equal("Your bags cannot be read yet", HelperModel.Now({ name = name }).title)
    end)

    it("lists the counts of this login", function()
        local rows = HelperModel.Login({
            presses = { spell = 10, lure = 1, wait = 2 },
            casts = 9,
            doubled = 4,
            hides = 1,
        })
        local values = {}
        for i, row in ipairs(rows) do
            values[i] = row.label .. "=" .. row.value
        end
        assert.are.same({
            "Casts through the key=10",
            "Lures put on=1",
            "Presses that waited for a lure=2",
            "Casts by double right-click=4",
            "Casts the tracker saved=9",
            "Times the interface was hidden=1",
        }, values)
        assert.are.equal(0, HelperModel.Login({})[1].value)
    end)
end)
