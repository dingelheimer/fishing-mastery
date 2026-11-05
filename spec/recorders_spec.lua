local addon = require("spec.helpers.addon")

local FILES = {
    "Serializer.lua",
    "Logger.lua",
    "Guard.lua",
    "Scan.lua",
    "Calls.lua",
    "Redact.lua",
    "Attempt.lua",
    "Context.lua",
    "Loot.lua",
    "Events.lua",
    "Tracer.lua",
    "Recorders.lua",
}

local NAME, GUID = "Synthia Brook", "Player-4321-0ABCDEF9"
local OTHER_NAME, OTHER_GUID = "Otto Other", "Player-4321-0FFFFFF1"
local SCHOOL_GUID = "GameObject-0-4321-0-12-180682-0000ABCDEF"
local CAST_GUID = "Cast-3-4321-0-12-7620-000CE1E4AF"
local FISH_LINK = "|cffffffff|Hitem:6291::::::::10:::::|h[Raw Brilliant Smallfish]|h|r"

-- A fake client: loot window state, item cache, auras, map, and a tooltip.
local function fakeClient()
    local client = { loot = {}, cache = {}, requests = {}, now = 100 }
    local tooltipLines = {
        GameTooltipTextLeft1 = { text = "Fishing Bobber" },
        GameTooltipTextLeft2 = { text = NAME .. "'s bobber" },
    }
    for _, line in pairs(tooltipLines) do
        function line:GetText()
            return self.text
        end
    end
    local tooltip = { owner = "UIParent" }
    function tooltip:GetUnit()
        return self.unitName, self.unit
    end
    function tooltip:GetOwner()
        return self.owner
    end
    function tooltip.GetName()
        return "GameTooltip"
    end
    client.tooltip = tooltip
    client.env = {
        UIParent = "UIParent",
        GameTooltip = tooltip,
        GameTooltipTextLeft1 = tooltipLines.GameTooltipTextLeft1,
        GameTooltipTextLeft2 = tooltipLines.GameTooltipTextLeft2,
        ERR_FISH_ESCAPED = "Your fish got away!",
        UnitName = function()
            return NAME
        end,
        UnitGUID = function()
            return GUID
        end,
        UnitChannelInfo = function()
            return "Fishing", "", 136245, 100000, 130000, false, false, 7620
        end,
        C_Spell = {
            GetSpellInfo = function(id)
                return { name = "Fishing", spellID = id }
            end,
        },
        GetProfessions = function()
            return nil, nil, nil, 4, nil
        end,
        GetProfessionInfo = function()
            return "Fishing", 136245, 75, 150, 1, 0, 356, 25
        end,
        GetInventoryItemID = function(_, slot)
            return slot == 16 and 6256 or nil
        end,
        C_UnitAuras = {
            GetAuraDataByIndex = function(_, index, filter)
                if filter == "HELPFUL" and index == 1 then
                    return {
                        spellId = 1234,
                        duration = 600,
                        expirationTime = 700,
                        name = "Well Fed",
                    }
                end
                return nil
            end,
        },
        C_Map = {
            GetBestMapForUnit = function()
                return 1429
            end,
            GetMapInfo = function(id)
                if id == 1429 then
                    return { mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415 }
                end
                return nil
            end,
            GetPlayerMapPosition = function()
                return { x = 0.123456, y = 0.987654 }
            end,
        },
        GetZoneText = function()
            return "Elwynn Forest"
        end,
        GetSubZoneText = function()
            return "Crystal Lake"
        end,
        IsFishingLoot = function()
            return client.loot.fishing == true
        end,
        GetNumLootItems = function()
            return #client.loot
        end,
        GetLootSlotInfo = function(slot)
            local entry = client.loot[slot]
            return 133888, "Raw Brilliant Smallfish", entry.quantity, nil, 1
        end,
        GetLootSlotType = function()
            return 1
        end,
        GetLootSlotLink = function(slot)
            return client.loot[slot].link
        end,
        GetLootSourceInfo = function(slot)
            return client.loot[slot].source, client.loot[slot].quantity
        end,
        C_Item = {
            GetItemInfo = function(id)
                if client.cache[id] then
                    return "Raw Brilliant Smallfish",
                        FISH_LINK,
                        1,
                        5,
                        0,
                        "Trade Goods",
                        "Meat",
                        20,
                        "",
                        133888,
                        1
                end
                return nil
            end,
            RequestLoadItemDataByID = function(id)
                client.requests[#client.requests + 1] = id
            end,
        },
    }
    return client
end

describe("Recorders", function()
    local ns, store, client, frame, bus, state, timers

    local function fire(event, ...)
        bus:Dispatch(event, ...)
    end

    local function runTimers()
        local pending = timers
        timers = {}
        for _, fn in ipairs(pending) do
            fn()
        end
    end

    local function entries(kind)
        local found = {}
        for _, entry in ipairs(store.entries) do
            if entry.kind == kind then
                found[#found + 1] = entry
            end
        end
        return found
    end

    local function dump(value, out)
        out = out or {}
        if type(value) == "table" then
            for key, child in pairs(value) do
                dump(key, out)
                dump(child, out)
            end
        else
            out[#out + 1] = tostring(value)
        end
        return table.concat(out, "|")
    end

    before_each(function()
        ns = addon.load(FILES)
        client = fakeClient()
        store = {}
        local logger = ns.Logger.New(store, {
            now = function()
                return client.now
            end,
            sanitize = ns.Serializer.Sanitize,
        })
        ns.Guard.SetSink(function(record)
            logger:Log("lua_error", record)
        end)
        frame = { registered = {} }
        function frame:RegisterEvent(event)
            self.registered[event] = true
        end
        function frame:RegisterUnitEvent(event, unit)
            self.registered[event] = unit
        end
        bus = ns.Events.New(frame, { UNIT_SPELLCAST_FAILED_QUIET = false })
        timers = {}
        state = ns.Recorders.Start({
            env = client.env,
            bus = bus,
            log = function(kind, data, q)
                return logger:Log(kind, data, q)
            end,
            now = function()
                return client.now
            end,
            after = function(_, fn)
                timers[#timers + 1] = fn
            end,
        })
    end)

    local function castAndCatch(autoLoot)
        client.now = 100
        fire("UNIT_SPELLCAST_CHANNEL_START", "player", CAST_GUID, 7620)
        client.now = 104
        fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", CAST_GUID, 7620)
        client.loot = {
            fishing = true,
            { quantity = 1, link = FISH_LINK, source = SCHOOL_GUID },
        }
        client.now = 104.1
        fire("LOOT_READY", autoLoot)
        client.now = 105
        fire("LOOT_CLOSED")
    end

    it("subscribes player unit events and skips unsupported ones", function()
        assert.are.equal("player", frame.registered.UNIT_SPELLCAST_CHANNEL_START)
        assert.is_true(frame.registered.LOOT_READY)
        assert.is_nil(frame.registered.UNIT_SPELLCAST_FAILED_QUIET)
        local started = entries("recorders_started")[1].data
        assert.are.same({ "UNIT_SPELLCAST_FAILED_QUIET" }, started.skipped)
    end)

    it("records a cast, its context, the loot, and a catch attempt", function()
        castAndCatch(false)
        local cast = entries("cast")[1]
        assert.are.equal("Q06", cast.q)
        assert.are.equal(30, cast.data.duration)
        assert.are.same(
            { present = true, type = "Cast", segments = 7, spellID = 7620, castID = "000CE1E4AF" },
            cast.data.castGUID
        )
        local context = entries("context")[1].data
        assert.are.equal(25, context.professions.info[4].values[8])
        assert.are.equal(4, context.professions.info[4].index)
        assert.are.equal(6256, context.mainHand.values[1])
        assert.are.same({ spellId = 1234, duration = 600, expirationTime = 700 }, context.buffs[1])
        assert.are.equal(0.123, context.location.x)
        assert.are.equal(0.988, context.location.y)
        assert.are.equal(1415, context.location.chain[1].parentMapID)
        local loot = entries("loot")[1]
        assert.are.equal("Q09", loot.q)
        assert.is_true(loot.data.isFishingLoot.values[1])
        assert.is_false(loot.data.autoLoot)
        assert.are.equal(6291, loot.data.slots[1].itemID)
        assert.are.same(
            { present = true, type = "GameObject", segments = 7, id = 180682 },
            loot.data.slots[1].sources[1].source
        )
        local attempt = entries("attempt")[1]
        assert.are.equal("catch", attempt.data.outcome)
        assert.are.equal("Q08", attempt.q)
        assert.are.same({ total = 1, last = "catch", byOutcome = { catch = 1 } }, state.stats)
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("logs item info at once when cached and after the load event otherwise", function()
        castAndCatch(true)
        local first = entries("item_info")[1].data
        assert.is_false(first.cached)
        assert.are.same({ 6291 }, client.requests)
        client.cache[6291] = true
        client.now = 106.5
        fire("ITEM_DATA_LOAD_RESULT", 6291, true)
        local second = entries("item_info")[2].data
        assert.is_true(second.cached)
        assert.are.equal(1, second.sellPrice)
        assert.is_true(math.abs(second.wait - 2.4) < 1e-9)
        fire("ITEM_DATA_LOAD_RESULT", 6291, true)
        castAndCatch(true)
        assert.are.equal(2, #entries("item_info"))
    end)

    it("classifies a getaway through the message text when no message API exists", function()
        client.now = 100
        fire("UNIT_SPELLCAST_CHANNEL_START", "player", CAST_GUID, 7620)
        client.now = 110
        fire("UI_ERROR_MESSAGE", 1, "Your fish got away!")
        fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", CAST_GUID, 7620)
        client.now = 112
        runTimers()
        local attempt = entries("attempt")[1]
        assert.are.equal("getaway", attempt.data.outcome)
        local traced = entries("event")
        local message
        for _, entry in ipairs(traced) do
            if entry.data.name == "UI_ERROR_MESSAGE" then
                message = entry.data
            end
        end
        assert.are.equal("ERR_FISH_ESCAPED", message.msgName)
    end)

    it("prefers GetGameMessageInfo for message names", function()
        client.env.GetGameMessageInfo = function()
            return "ERR_FISH_NOT_HOOKED"
        end
        fire("UNIT_SPELLCAST_CHANNEL_START", "player", CAST_GUID, 7620)
        fire("UI_ERROR_MESSAGE", 2, "anything")
        fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", CAST_GUID, 7620)
        client.now = client.now + 2
        runTimers()
        assert.are.equal("early_click", entries("attempt")[1].data.outcome)
    end)

    it("ignores unit events of other units", function()
        fire("UNIT_SPELLCAST_CHANNEL_START", "party1", CAST_GUID, 7620)
        assert.are.equal(0, #entries("cast"))
        assert.is_false(state.classifier:Active())
    end)

    it("keeps own loot messages and drops other players' chat", function()
        fire(
            "CHAT_MSG_LOOT",
            "You receive loot: [Fish]. " .. NAME,
            NAME,
            "",
            "",
            NAME,
            "",
            0,
            0,
            "",
            0,
            1,
            GUID
        )
        fire(
            "CHAT_MSG_LOOT",
            OTHER_NAME .. " receives loot: [Fish].",
            OTHER_NAME,
            "",
            "",
            OTHER_NAME,
            "",
            0,
            0,
            "",
            0,
            2,
            OTHER_GUID
        )
        local chat = entries("event")
        assert.are.same(
            { name = "CHAT_MSG_LOOT", own = true, text = "You receive loot: [Fish]. <player>" },
            chat[1].data
        )
        assert.are.same({ name = "CHAT_MSG_LOOT", own = false }, chat[2].data)
    end)

    it("throttles UNIT_AURA and reports suppressed events", function()
        for i = 0, 4 do
            client.now = 200 + i * 0.2
            fire("UNIT_AURA", "player", { isFullUpdate = true })
        end
        client.now = 201.5
        fire("UNIT_AURA", "player", { isFullUpdate = false })
        local auras = {}
        for _, entry in ipairs(entries("event")) do
            if entry.data.name == "UNIT_AURA" then
                auras[#auras + 1] = entry
            end
        end
        assert.are.equal(2, #auras)
        assert.are.equal("Q18", auras[1].q)
        assert.are.equal(4, auras[2].data.suppressed)
    end)

    it("logs the bobber tooltip during a cast without other names", function()
        state.onTooltip(client.tooltip)
        assert.are.equal(0, #entries("tooltip"))
        fire("UNIT_SPELLCAST_CHANNEL_START", "player", CAST_GUID, 7620)
        state.onTooltip(client.tooltip)
        state.onTooltip(client.tooltip)
        local tooltips = entries("tooltip")
        assert.are.equal(1, #tooltips)
        assert.are.equal("Fishing Bobber", tooltips[1].data.line1)
        assert.is_true(tooltips[1].data.line2.hasOwnName)
        assert.is_nil(tooltips[1].data.line2.text)
        client.tooltip.unit = "player"
        client.env.GameTooltipTextLeft1.text = "Other text"
        state.onTooltip(client.tooltip)
        assert.are.equal(1, #entries("tooltip"))
    end)

    it("hooks the tooltip through TooltipDataProcessor or OnShow", function()
        local calls = {}
        client.env.TooltipDataProcessor = {
            AllTypes = "ALL",
            AddTooltipPostCall = function(kind, fn)
                calls[#calls + 1] = { kind = kind, fn = fn }
            end,
        }
        assert.are.equal("post_call", ns.Recorders.HookTooltip(client.env, state))
        assert.are.equal("ALL", calls[1].kind)
        client.env.TooltipDataProcessor = nil
        function client.tooltip:HookScript(script, fn)
            self.hooked = { script = script, fn = fn }
        end
        assert.are.equal("on_show", ns.Recorders.HookTooltip(client.env, state))
        assert.are.equal("OnShow", client.tooltip.hooked.script)
    end)

    it("never writes names or player GUIDs into the log", function()
        castAndCatch(false)
        fire(
            "CHAT_MSG_LOOT",
            "You receive loot. " .. NAME,
            NAME,
            "",
            "",
            NAME,
            "",
            0,
            0,
            "",
            0,
            1,
            GUID
        )
        fire(
            "CHAT_MSG_LOOT",
            OTHER_NAME .. " loots.",
            OTHER_NAME,
            "",
            "",
            OTHER_NAME,
            "",
            0,
            0,
            "",
            0,
            2,
            OTHER_GUID
        )
        fire("UNIT_SPELLCAST_CHANNEL_START", "player", CAST_GUID, 7620)
        state.onTooltip(client.tooltip)
        fire("UNIT_SPELLCAST_SENT", "player", OTHER_NAME, CAST_GUID, 7620)
        local text = dump(store)
        for _, secret in ipairs({ "Synthia", "Otto", "0ABCDEF9", "0FFFFFF1" }) do
            assert.is_nil(text:find(secret, 1, true), secret)
        end
        assert.is_nil(text:find("<depth>", 1, true), "a record exceeds the serializer depth cap")
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("survives a client where every recorder API is missing", function()
        local emptyBus = ns.Events.New(frame, nil)
        local emptyState = ns.Recorders.Start({
            env = {},
            bus = emptyBus,
            log = function() end,
            now = function()
                return 1
            end,
            after = function() end,
        })
        emptyBus:Dispatch("UNIT_SPELLCAST_CHANNEL_START", "player", "x", 1)
        emptyBus:Dispatch("LOOT_READY", true)
        emptyBus:Dispatch("UI_ERROR_MESSAGE", 1, "text")
        emptyBus:Dispatch("UNIT_SPELLCAST_CHANNEL_STOP", "player", "x", 1)
        emptyState.tick()
        assert.are.equal(0, ns.Guard.errors)
    end)
end)
