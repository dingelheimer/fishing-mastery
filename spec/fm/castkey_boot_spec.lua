-- Casting key (CastKey.lua, Bindings.xml) through every TOC file: the spell choice, the secure
-- button with its attributes after login, the Key Bindings texts, the wait after a /reload in
-- combat, no Fishing (one chat note per login), casts through the key tracked like any other, and
-- the Helpers heading in the settings panel.
local fmboot = require("spec.helpers.fmboot")

local STUBS = {
    "InCombatLockdown",
    "IsPlayerSpell",
    "C_Spell",
    "Settings",
    "CreateSettingsListSectionHeaderInitializer",
    "BINDING_HEADER_FISHINGMASTERY",
    "BINDING_NAME_CLICK FishingMasteryCastButton:LeftButton",
}

describe("FishingMastery casting key", function()
    local w

    before_each(function()
        w = fmboot.new()
    end)

    after_each(function()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
        w.cleanup()
    end)

    local function key()
        return w.ns.castKey
    end

    it("picks the spell name, else the highest known rank, else nothing", function()
        w.boot(nil, nil)
        local Spell = w.ns.CastKey.Spell
        local function knows(ids)
            return function(id)
                return ids[id] == true
            end
        end
        assert.are.equal("Fishing", Spell(true, "Fishing", knows({})))
        assert.are.equal(7732, Spell(true, nil, knows({ [7620] = true, [7732] = true })))
        assert.are.equal(18248, Spell(true, "", knows({ [18248] = true, [7620] = true })))
        assert.are.equal(7620, Spell(true, nil, knows({}))) -- the client picks the rank
        assert.is_nil(Spell(false, "Fishing", knows({ [7620] = true })))
    end)

    it("sets up the secure button and the Key Bindings texts at login", function()
        w.boot(nil, nil)
        local button = key().button
        assert.are.equal("FishingMasteryCastButton", button.name)
        assert.are.equal("SecureActionButtonTemplate", button.template)
        assert.are.same({ "AnyDown", "AnyUp" }, button.clicks)
        assert.is_false(button:GetAttribute("useOnKeyDown"))
        assert.are.equal("spell", button:GetAttribute("type"))
        assert.are.equal("Fishing", button:GetAttribute("spell")) -- GetProfessionInfo name
        assert.are.equal("Fishing Mastery", _G.BINDING_HEADER_FISHINGMASTERY)
        assert.are.equal(
            "Cast Fishing",
            _G["BINDING_NAME_CLICK FishingMasteryCastButton:LeftButton"]
        )

        -- The spell name from C_Spell wins; attributes change only when the value changes.
        _G.C_Spell = {
            GetSpellInfo = function(id)
                return id == 7620 and { name = "Angeln" } or nil
            end,
        }
        local writes = 0
        local original = button.SetAttribute
        button.SetAttribute = function(b, k, v)
            writes = writes + 1
            original(b, k, v)
        end
        w.fire("SPELLS_CHANGED")
        assert.are.equal("Angeln", button:GetAttribute("spell"))
        assert.are.equal(1, writes)
        w.fire("SKILL_LINES_CHANGED")
        assert.are.equal(1, writes)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("waits for the end of combat after a /reload in combat", function()
        local combat = true
        _G.InCombatLockdown = function()
            return combat
        end
        w.boot(nil, nil)
        assert.is_nil(key().button)
        assert.is_true(key().pending)
        combat = false
        w.fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("spell", key().button:GetAttribute("type"))

        -- A skill change during combat is applied after it.
        combat = true
        _G.C_Spell = {
            GetSpellInfo = function()
                return { name = "Pêche" }
            end,
        }
        w.fire("SPELLS_CHANGED")
        assert.are.equal("Fishing", key().button:GetAttribute("spell"))
        combat = false
        w.fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("Pêche", key().button:GetAttribute("spell"))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("does nothing without Fishing and says so once", function()
        w.boot(nil, nil)
        _G.GetProfessions = function()
            return 5, nil, nil, nil, 6
        end
        w.fire("SKILL_LINES_CHANGED")
        local button = key().button
        assert.is_nil(button:GetAttribute("type"))
        assert.is_nil(button:GetAttribute("spell"))
        button:PressKey(true) -- key down: nothing
        assert.is_nil(w.output():find("has not learned Fishing", 1, true))
        button:PressKey(false)
        button:PressKey(false)
        local _, notes = w.output():gsub("has not learned Fishing", "")
        assert.are.equal(1, notes)
    end)

    it("tracks a cast through the key like any other cast", function()
        w.boot(nil, nil)
        key().button:PressKey(true)
        key().button:PressKey(false)
        w.catch(5000, 9)
        w.runTimers(5012)
        local totals = _G.FishingMasteryDB.chars[next(_G.FishingMasteryDB.chars)].totals
        assert.are.equal(1, totals.outcomes.catch)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("adds the Helpers heading to the settings panel, or lists it as missing", function()
        local headers, layout = {}, {}
        function layout.AddInitializer(_, initializer)
            headers[#headers + 1] = initializer
        end
        _G.Settings = {
            RegisterVerticalLayoutCategory = function()
                return {
                    GetID = function()
                        return 1
                    end,
                },
                    layout
            end,
            RegisterAddOnSetting = function(_, _, settingKey)
                return { key = settingKey }
            end,
            CreateCheckbox = function() end,
            RegisterAddOnCategory = function() end,
        }
        _G.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
            return { name = name, tooltip = tooltip }
        end
        w.boot(nil, nil)
        assert.are.equal(1, #headers)
        assert.are.equal("Helpers", headers[1].name)
        assert.truthy(headers[1].tooltip:find("Key Bindings, under AddOns", 1, true))
        assert.are.equal("ok", w.ns.settingsPanel.results.helpers)

        _G.CreateSettingsListSectionHeaderInitializer = nil
        w.boot(nil, nil)
        assert.are.equal("missing", w.ns.settingsPanel.results.helpers)
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
