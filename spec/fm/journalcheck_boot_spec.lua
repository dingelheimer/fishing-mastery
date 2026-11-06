-- Boot tests for the journal API check (/fm dev journal) and the trade skill read on
-- TRADE_SKILL_SHOW: dev flag only, every API missing, every API present, header rows skipped,
-- recipe names printed but not saved, secret values, raising APIs, the run cap, and clear.
local fmboot = require("spec.helpers.fmboot")

-- Globals the stubs set beyond the harness; removed after each test.
local STUBS = {
    "IsSpellKnown",
    "IsPlayerSpell",
    "GetSpellInfo",
    "C_Spell",
    "C_TradeSkillUI",
    "C_TooltipInfo",
    "GetInventoryItemID",
    "GetNumTradeSkills",
    "GetTradeSkillLine",
    "GetTradeSkillInfo",
    "GetTradeSkillItemLink",
    "GetTradeSkillRecipeLink",
    "GetTradeSkillNumReagents",
    "GetTradeSkillReagentInfo",
    "GetTradeSkillReagentItemLink",
    "issecretvalue",
}

local KNOWN = { [7751] = true, [7752] = true }
local NAMES = { [7751] = "Brilliant Smallfish", [1229745] = "Fish Bowl", [43308] = "Find Fish" }
local TIPS = {
    [6365] = { "Strong Fishing Pole", "Fishing Pole", "Equip: Increased Fishing +5." },
    [6367] = { "Big Iron Fishing Pole", "Equip: Increased Fishing +42." },
}
local COUNTS = { [6365] = { 1, 1 }, [19971] = { 0, 2 } } -- bags, with bank
local CLASSES = { [6291] = { 0, 0 }, [6292] = { 15, 0 }, [16967] = { 12, 0 } }

local function itemLink(id, name)
    return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r"
end

local function stubChecks(w)
    _G.IsSpellKnown = function(id)
        return KNOWN[id] or false
    end
    _G.IsPlayerSpell = function(id)
        return KNOWN[id] or false
    end
    _G.GetSpellInfo = function(id)
        return NAMES[id]
    end
    _G.C_Spell = {
        GetSpellInfo = function(id)
            return NAMES[id] and { name = NAMES[id], spellID = id } or nil
        end,
    }
    _G.C_TooltipInfo = {
        GetItemByID = function(id)
            local lines = {}
            for i, left in ipairs(TIPS[id] or {}) do
                lines[i] = { leftText = left }
            end
            return TIPS[id] and { lines = lines } or nil
        end,
    }
    _G.C_Item.GetItemCount = function(id, bank)
        local c = COUNTS[id] or { 0, 0 }
        return bank and c[2] or c[1]
    end
    _G.C_Item.GetItemInfoInstant = function(id)
        local c = CLASSES[id]
        if c then
            return id, "Trade Goods", "", "", 1, c[1], c[2]
        end
    end
    _G.C_Item.RequestLoadItemDataByID = function() end
    _G.GetInventoryItemID = function(unit, slot)
        assert.are.equal("player", unit)
        return slot == 16 and 6367 or nil
    end
    w.game.modifier = 20
end

-- A cooking window with a header row and four recipes.
local RECIPES = {
    { "Fish", "header" },
    { "Brilliant Smallfish", "easy", 6290, 7751, { { 6291, 1 } } },
    { "Longjaw Mud Snapper", "medium", 4592, 7753, { { 6289, 1 } } },
    { "Rockscale Cod", "optimal", 5527, 7828, { { 6362, 1 }, { 2678, 1 } } },
    { "Spiced Wolf Meat", "trivial", 2680, 2539, { { 2672, 1 }, { 2678, 1 } } },
}

local function stubTrade()
    _G.GetTradeSkillLine = function()
        return "Cooking", 120, 150
    end
    _G.GetNumTradeSkills = function()
        return #RECIPES
    end
    _G.GetTradeSkillInfo = function(i)
        return RECIPES[i][1], RECIPES[i][2]
    end
    _G.GetTradeSkillItemLink = function(i)
        return itemLink(RECIPES[i][3], RECIPES[i][1])
    end
    _G.GetTradeSkillRecipeLink = function(i)
        return "|cffffd000|Henchant:" .. RECIPES[i][4] .. "|h[Cooking: " .. RECIPES[i][1] .. "]|h|r"
    end
    _G.GetTradeSkillNumReagents = function(i)
        return #RECIPES[i][5]
    end
    _G.GetTradeSkillReagentInfo = function(i, r)
        return "Reagent", 133890, RECIPES[i][5][r][2], 4
    end
    _G.GetTradeSkillReagentItemLink = function(i, r)
        return itemLink(RECIPES[i][5][r][1], "Reagent")
    end
end

local function journal()
    return _G.FishingMasteryDB.dev.journal
end

describe("FishingMastery journal check boot", function()
    local w

    before_each(function()
        w = fmboot.new()
        w.boot({ schemaVersion = 1, chars = {}, settings = { dev = true } }, nil)
    end)

    after_each(function()
        for _, name in ipairs(STUBS) do
            _G[name] = nil
        end
        w.cleanup()
    end)

    it("is a dev command only and does not read trade windows without the flag", function()
        _G.FishingMasteryDB.settings.dev = nil
        _G.SlashCmdList.FM("dev journal")
        assert.truthy(w.output():find("Unknown command: dev", 1, true))
        stubTrade()
        w.fire("TRADE_SKILL_SHOW")
        assert.is_nil(_G.FishingMasteryDB.dev)
    end)

    it("reports every missing API without Lua errors", function()
        _G.SlashCmdList.FM("dev journal")
        local run = journal().runs[1]
        assert.are.equal(w.serverTime, run.at)
        local paths = { "IsSpellKnown", "C_TooltipInfo.GetItemByID", "GetNumTradeSkills" }
        for _, path in ipairs(paths) do
            assert.truthy(table.concat(run.missing, ","):find(path, 1, true))
        end
        assert.are.equal(#w.ns.JournalCheck.RECIPES, #run.recipes)
        assert.is_nil(run.recipes[1].known)
        assert.is_nil(run.gear[1].tip)
        local out = w.output()
        assert.truthy(out:find("Journal check (run 1 of at most 10 kept, 0 trade reads", 1, true))
        assert.truthy(out:find("New spells named: 0 of 14", 1, true))
        assert.truthy(out:find("(no tooltip yet, run again)", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)

        stubTrade()
        _G.GetTradeSkillReagentItemLink = nil
        _G.GetTradeSkillRecipeLink = nil
        w.fire("TRADE_SKILL_SHOW")
        local trade = journal().trades[1]
        assert.is_nil(trade.recipes[1].spell)
        assert.are.same({ { count = 1 } }, trade.recipes[1].reagents)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("reads spells, tooltips, counts, item classes, and the fishing modifier", function()
        stubChecks(w)
        _G.SlashCmdList.FM("dev journal")
        local run = journal().runs[1]
        assert.are.same(
            { id = 7751, name = "Brilliant Smallfish", known = true, player = true },
            run.recipes[1]
        )
        assert.are.same({ id = 18246, known = false, player = false }, run.recipes[3])
        assert.are.same({ id = 43308, name = "Find Fish" }, run.newSpells[1])
        local byId = {}
        for _, g in ipairs(run.gear) do
            byId[g.id] = g
        end
        assert.are.same({ id = 6365, tip = TIPS[6365], bags = 1, bank = 1 }, byId[6365])
        assert.are.same({ id = 19971, bags = 0, bank = 2 }, byId[19971])
        assert.are.same({ id = 6292, class = 15, subclass = 0 }, run.groups[2])
        assert.are.same({ id = 6297 }, run.groups[7])
        assert.are.same({ rank = 11, modifier = 20, pole = 6367, tip = TIPS[6367] }, run.fishing)
        local out = w.output()
        assert.truthy(out:find("Recipe 7751 Brilliant Smallfish: IsSpellKnown true", 1, true))
        assert.truthy(out:find("New spells named: 2 of 14", 1, true))
        assert.truthy(
            out:find(
                "Item 6365 Strong Fishing Pole: bags 1, with bank 1; bonus lines: "
                    .. "Equip: Increased Fishing +5.",
                1,
                true
            )
        )
        assert.truthy(out:find("Item class/subclass: 6291=0/0, 6292=15/0", 1, true))
        assert.truthy(
            out:find(
                "Fishing skill 11, modifier 20; main hand 6367, bonus lines: "
                    .. "Equip: Increased Fishing +42.",
                1,
                true
            )
        )
        assert.truthy(out:find("Missing APIs: GetNumTradeSkills", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it(
        "reads the first recipes of a trade window, skipping headers, without saving names",
        function()
            stubTrade()
            w.fire("TRADE_SKILL_SHOW")
            local trade = journal().trades[1]
            assert.are.same({
                at = w.serverTime,
                fired = true,
                phase = "show",
                modern = { recipes = {} },
                line = "Cooking",
                num = 5,
                recipes = {
                    {
                        index = 2,
                        spell = 7751,
                        product = 6290,
                        reagents = { { id = 6291, count = 1 } },
                    },
                    {
                        index = 3,
                        spell = 7753,
                        product = 4592,
                        reagents = { { id = 6289, count = 1 } },
                    },
                    {
                        index = 4,
                        spell = 7828,
                        product = 5527,
                        reagents = { { id = 6362, count = 1 }, { id = 2678, count = 1 } },
                    },
                },
            }, trade)
            local out = w.output()
            assert.truthy(
                out:find("Trade skill window (show): Cooking, 5 recipes (read 1 saved)", 1, true)
            )
            assert.truthy(
                out:find(
                    "Rockscale Cod: spell 7828, product 5527, reagents 6362 x1, 2678 x1",
                    1,
                    true
                )
            )

            -- A spell link instead of an enchant link also gives the spell.
            _G.GetTradeSkillRecipeLink = function()
                return "|cff71d5ff|Hspell:7751:0|h[Brilliant Smallfish]|h|r"
            end
            w.fire("TRADE_SKILL_SHOW")
            assert.are.equal(7751, journal().trades[2].recipes[1].spell)
            assert.are.equal(0, w.ns.Guard.errors)
        end
    )

    it("reads C_TradeSkillUI recipes on show and once more a second later", function()
        local schematics = {
            [7751] = {
                outputItemID = 6290,
                reagentSlotSchematics = {
                    { reagents = { { itemID = 6291 } }, quantityRequired = 1 },
                },
            },
        }
        _G.C_TradeSkillUI = {
            GetBaseProfessionInfo = function()
                return {
                    professionID = 185,
                    professionName = "Cooking",
                    skillLevel = 120,
                    maxSkillLevel = 150,
                }
            end,
            GetAllRecipeIDs = function()
                return { 7751, 7753, 18246 }
            end,
            GetRecipeInfo = function(id)
                return { recipeID = id, name = "Recipe " .. id, learned = id ~= 18246 }
            end,
            GetRecipeSchematic = function(id)
                return schematics[id]
            end,
            GetRecipeNumReagents = function(id)
                return id == 7753 and 1 or nil
            end,
            GetRecipeItemLink = function()
                return itemLink(4592, "Longjaw Mud Snapper")
            end,
            GetRecipeReagentInfo = function()
                return "Raw Longjaw Mud Snapper", 133890, 1, 3
            end,
            GetRecipeReagentItemLink = function()
                return itemLink(6289, "Raw Longjaw Mud Snapper")
            end,
        }
        w.fire("TRADE_SKILL_SHOW")
        local m = journal().trades[1].modern
        assert.are.equal(8, #m.api)
        assert.are.equal("GetAllRecipeIDs", m.api[1])
        assert.are.same({ 185, "Cooking", 120, 150, 3, 2 }, {
            m.profession,
            m.professionName,
            m.skill,
            m.maxSkill,
            m.total,
            m.learned,
        })
        assert.are.same({
            {
                id = 7751,
                via = "schematic",
                product = 6290,
                reagents = { { id = 6291, count = 1 } },
            },
            {
                id = 7753,
                via = "reagentInfo",
                product = 4592,
                reagents = { { id = 6289, count = 1 } },
            },
        }, m.recipes)
        local out = w.output()
        assert.truthy(
            out:find(
                "C_TradeSkillUI: 8 functions; profession 185 Cooking, skill 120 of 150; "
                    .. "recipes 3, learned 2",
                1,
                true
            )
        )
        assert.truthy(out:find("Recipe 7751: spell 7751, product 6290, reagents 6291 x1", 1, true))
        assert.is_nil(out:find("Recipe 18246", 1, true))

        w.runTimers(w.clock + 1)
        local trades = journal().trades
        assert.are.equal(2, #trades)
        assert.are.equal("later", trades[2].phase)
        assert.are.equal(2, trades[2].modern.learned)
        w.runTimers(w.clock + 5) -- the later read schedules nothing more
        assert.are.equal(2, #journal().trades)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("skips secret values and raising APIs", function()
        local secret = {}
        _G.issecretvalue = function(value)
            return value == secret
        end
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
        stubChecks(w)
        stubTrade()
        _G.IsSpellKnown = function()
            return secret
        end
        _G.C_TooltipInfo.GetItemByID = function()
            error("tooltip failed")
        end
        _G.GetTradeSkillLine = function()
            return secret
        end
        _G.GetTradeSkillInfo = function(i)
            if i == 2 then
                error("info failed")
            end
            return RECIPES[i][1], RECIPES[i][2]
        end
        _G.SlashCmdList.FM("dev journal")
        w.fire("TRADE_SKILL_SHOW")
        local run, trade = journal().runs[1], journal().trades[1]
        assert.is_nil(run.recipes[1].known)
        assert.is_true(run.recipes[1].player)
        assert.is_nil(run.gear[1].tip)
        assert.is_nil(trade.line)
        assert.are.equal(3, trade.recipes[1].index)
        assert.are.equal(0, w.ns.Guard.errors)
    end)

    it("keeps at most CAP runs and trade reads and clears them", function()
        local cap = w.ns.JournalCheck.CAP
        stubTrade()
        for _ = 1, cap + 2 do
            _G.SlashCmdList.FM("dev journal")
            w.fire("TRADE_SKILL_SHOW")
        end
        assert.are.equal(cap, #journal().runs)
        assert.are.equal(cap, #journal().trades)
        _G.SlashCmdList.FM("dev journal clear")
        assert.are.same({ runs = {}, trades = {} }, journal())
        assert.truthy(w.output():find("Journal check runs and trade reads removed.", 1, true))

        -- A broken saved table is replaced instead of raising.
        _G.FishingMasteryDB.dev.journal = "broken"
        _G.SlashCmdList.FM("dev journal")
        assert.are.equal(1, #journal().runs)
        assert.are.equal(0, w.ns.Guard.errors)
    end)
end)
