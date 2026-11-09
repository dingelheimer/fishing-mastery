-- The smart lure (SmartLure.lua, LureChoice.lua, CastKey.lua) through every TOC file: off by
-- default; with it on, the casting key puts the chosen lure on the pole (type=item, target-slot
-- 16) right before the press, waits after the click until the enchant shows up, and casts again
-- after it; no lure without a pole, without a usable lure, or with enough skill; nothing changes
-- in combat; the HUD tooltip line with the setting on or off.
local fmboot = require("spec.helpers.fmboot")

local STUBS = {
    "InCombatLockdown",
    "GetInventoryItemID",
    "UnitRace",
    "BINDING_HEADER_FISHINGMASTERY",
    "BINDING_NAME_CLICK FishingMasteryCastButton:LeftButton",
}

local POLE, BAUBLE, CRAWLERS = 6256, 6529, 6530
local NAMES = { [BAUBLE] = "Shiny Bauble", [CRAWLERS] = "Nightcrawlers" }

describe("FishingMastery smart lure", function()
    local w, game, goal

    before_each(function()
        w = fmboot.new()
        game = { pole = POLE, bags = { [BAUBLE] = 3, [CRAWLERS] = 2 }, area = 14 }
        _G.InCombatLockdown = function()
            return game.combat == true
        end
        _G.GetInventoryItemID = function(_, slot)
            return slot == 16 and game.pole or nil
        end
        _G.UnitRace = function()
            return "Troll", "Troll", 8
        end
        w.boot(nil, nil)
        _G.C_Item.GetItemInfoInstant = function(id)
            return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, id == POLE and 20 or 7
        end
        _G.C_Item.GetItemCount = function(id, bank)
            assert.is_false(bank)
            return game.bags[id] or 0
        end
        _G.C_Item.GetItemInfo = function(id)
            return NAMES[id]
        end
        -- The lure enchant on the pole: GetWeaponEnchantInfo with game.enchant and game.ms.
        _G.GetWeaponEnchantInfo = function()
            if game.enchant then
                return true, game.ms, 0, game.enchant, false
            end
            return false
        end
        -- 14 Durotar (base -70), 405 base 130; the area lookup is covered by the area check specs.
        w.ns.Context.CurrentArea = function()
            return game.area
        end
        goal = w.ns.area:Base(14) + 95
        w.ns.Options.Set(w.ns.db.settings, "autoLure", true)
    end)

    after_each(function()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
        w.cleanup()
    end)

    local function button()
        return w.ns.castKey.button
    end

    local function attributes()
        local b = button()
        return {
            type = b:GetAttribute("type"),
            spell = b:GetAttribute("spell"),
            item = b:GetAttribute("item"),
            slot = b:GetAttribute("target-slot"),
        }
    end

    local CAST = { type = "spell", spell = "Fishing" }
    local function lure(id)
        return { type = "item", item = "item:" .. id, slot = 16 }
    end

    it("is off by default and casts then", function()
        assert.is_false(w.ns.Options.Default("autoLure"))
        w.ns.Options.Set(w.ns.db.settings, "autoLure", false)
        button():PressKey(true)
        assert.are.same(CAST, attributes())
    end)

    it("puts the cheapest lure that stops getaways on the pole, then casts", function()
        -- Skill 11 in Durotar: +25 reaches the goal (Nightcrawlers need skill 50 anyway).
        assert.is_true(11 + 25 >= goal)
        button():PressKey(true)
        assert.are.same(lure(BAUBLE), attributes())
        button():PressKey(false)

        -- While the lure is applied the key does nothing (no second lure, no cast).
        w.at(5001, "UNIT_SPELLCAST_START", "player")
        button():PressKey(true)
        assert.are.same({}, attributes())
        assert.are.equal("applying", w.ns.smartLure.choice.reason)

        -- The enchant shows up: the next press casts.
        game.enchant, game.ms = 263, 600000
        button():PressKey(true)
        assert.are.same(CAST, attributes())
        assert.are.equal("active", w.ns.smartLure.choice.reason)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("stops waiting when the lure cast fails or after 10 s", function()
        button():PressKey(true)
        button():PressKey(false)
        w.fire("UNIT_SPELLCAST_INTERRUPTED", "player")
        button():PressKey(true)
        assert.are.same(lure(BAUBLE), attributes())

        button():PressKey(false)
        w.at(5009, "UNIT_SPELLCAST_START", "player")
        button():PressKey(true)
        assert.are.same({}, attributes())
        w.at(5010.1, "UNIT_SPELLCAST_START", "player")
        button():PressKey(true)
        assert.are.same(lure(BAUBLE), attributes())
    end)

    it("renews only a running lure of the same kind, at 30 s or less", function()
        game.enchant, game.ms = 263, 31000
        button():PressKey(true)
        assert.are.same(CAST, attributes())
        game.ms = 30000
        button():PressKey(true)
        assert.are.same(lure(BAUBLE), attributes())
        game.enchant = 264 -- Nightcrawlers running: not replaced early
        button():PressKey(true)
        assert.are.same(CAST, attributes())
        assert.are.equal("other-running", w.ns.smartLure.choice.reason)
    end)

    it("casts without a pole, a usable lure, or a need for one", function()
        game.pole = 2488
        button():PressKey(true)
        assert.are.same(CAST, attributes())
        game.pole = POLE
        game.bags = { [CRAWLERS] = 2 } -- needs skill 50
        button():PressKey(true)
        assert.are.same(CAST, attributes())
        assert.are.equal("no-lures", w.ns.smartLure.choice.reason)
        game.bags = { [BAUBLE] = 1 }
        w.game.rank = goal
        button():PressKey(true)
        assert.are.same(CAST, attributes())
        assert.are.equal("enough", w.ns.smartLure.choice.reason)
    end)

    it("changes nothing in combat", function()
        game.combat = true
        button():PressKey(true)
        assert.are.same(CAST, attributes())
        game.combat = false
        w.fire("PLAYER_REGEN_ENABLED")
        assert.are.same(lure(BAUBLE), attributes())
    end)

    it("makes the double-click wait while a lure is applied", function()
        w.ns.Options.Set(w.ns.db.settings, "doubleClick", true)
        button():PressKey(true)
        button():PressKey(false)
        w.at(5001, "GLOBAL_MOUSE_DOWN", "RightButton")
        w.at(5001.1, "GLOBAL_MOUSE_UP", "RightButton")
        w.at(5001.3, "GLOBAL_MOUSE_DOWN", "RightButton")
        assert.are.equal("lure-wait", w.ns.doubleCast.last)
    end)

    it("tells the HUD which lure would help, with the setting on or off", function()
        -- What the HUD card and tooltip show: the choice, its lure, and the goal.
        local function now()
            local result = w.ns.SmartLure.Now(_G, w.ns.area, w.ns.Journal)
            local choice = result.choice
            if not choice then
                return nil
            end
            local name = choice.lure and result.name(choice.lure.id)
            return choice.reason, name, choice.lure and choice.lure.bonus, choice.goal
        end
        assert.are.equal(25, goal)
        assert.are.same({ "reaches", "Shiny Bauble", 25, 25 }, { now() })
        w.ns.Options.Set(w.ns.db.settings, "autoLure", false)
        assert.are.same({ "reaches", "Shiny Bauble", 25, 25 }, { now() })

        -- A running +25 lure: skill 36 with it, 11 without; the suggestion leaves it out.
        game.enchant, game.ms, w.game.modifier = 263, 600000, 25
        assert.are.same({ "reaches", "Shiny Bauble", 25, 25 }, { now() })
        game.enchant, w.game.modifier = nil, 0

        game.bags = {}
        assert.are.same({ "no-lures", nil, nil, 25 }, { now() })
        game.area, w.game.rank = 405, 110
        game.bags = { [CRAWLERS] = 1, [BAUBLE] = 1 }
        assert.are.same({ "strongest", "Nightcrawlers", 50, 225 }, { now() })
        w.game.rank = 225
        assert.are.equal("enough", (now()))

        _G.C_Item.GetItemInfo = function() end
        game.area, w.game.rank = 14, 11
        assert.are.same({ "reaches", "item 6529", 25, 25 }, { now() })
        _G.C_Item.GetItemCount = nil -- bags unknown: no choice
        assert.is_nil(now())
    end)
end)
