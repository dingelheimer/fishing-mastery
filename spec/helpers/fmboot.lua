-- Boot harness for FishingMastery: loads every TOC file against the fake UI with stubbed game
-- APIs, a fake clock, and fake C_Timer timers, and drives client events. Used by the boot specs.
local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")

local M = {}

M.ADDON = "FishingMastery"
M.GUID = "Player-5827-0ABCDEF0"

-- Globals the harness sets; cleanup() removes them.
M.STUBS = {
    "CreateFrame",
    "UIParent",
    "UISpecialFrames",
    "GetServerTime",
    "DEFAULT_CHAT_FRAME",
    "SlashCmdList",
    "SLASH_FM1",
    "SLASH_FM2",
    "FishingMasteryDB",
    "FishingMasteryCharDB",
    "UnitGUID",
    "UnitFullName",
    "GetRealmName",
    "C_AddOns",
    "GetTimePreciseSec",
    "C_Timer",
    "GetGameMessageInfo",
    "UnitChannelInfo",
    "IsFishingLoot",
    "ERR_FISH_ESCAPED",
    "GetProfessions",
    "GetProfessionInfo",
    "GetWeaponEnchantInfo",
    "C_Map",
    "GetSubZoneText",
    "GetNumLootItems",
    "GetLootSlotLink",
    "GetLootSlotInfo",
    "GetLootSourceInfo",
    "C_Item",
    "C_UnitAuras",
    "FishingMastery_OnAddonCompartmentClick",
    "GameTooltip",
}

local function stubGame(w)
    local game = w.game
    _G.GetProfessions = function()
        return 5, nil, nil, 7, 6
    end
    _G.GetProfessionInfo = function(index)
        if index == 7 then
            return "Fishing", 136245, game.rank, 75, 2, 19, 356, game.modifier, -1, 0
        end
        return "Other", 1, 1, 75, 1, 1, 1, 0, -1, 0
    end
    _G.GetWeaponEnchantInfo = function()
        if game.lure then
            return true, 584149, 0, game.lure, false
        end
        return false
    end
    _G.C_Map = {
        GetBestMapForUnit = function()
            return game.map
        end,
    }
    _G.GetSubZoneText = function()
        return game.subzone
    end
    _G.GetNumLootItems = function()
        return 1
    end
    _G.GetLootSlotLink = function()
        return "|cnIQ1:|Hitem:6303::::::::5:1482:::::::::|h[Raw Slitherskin Mackerel]|h|r"
    end
    _G.GetLootSlotInfo = function()
        return 133910, "Raw Slitherskin Mackerel", 1, nil, 1, false, false
    end
    _G.GetLootSourceInfo = function()
        return "GameObject-0-1-2-3-35591-0000ABCD", 1
    end
    _G.C_Item = {
        GetItemInfo = function()
            return "Raw Slitherskin Mackerel", "link", 1
        end,
        -- w.game.itemInfoInstant(id): item class data from the first login on (nil: no API).
        GetItemInfoInstant = game.itemInfoInstant,
    }
    _G.C_UnitAuras = {
        GetAuraDataByIndex = function(_, index)
            local id = game.auras and game.auras[index]
            return id and { spellId = id, name = "Buff", sourceUnit = "party1" } or nil
        end,
    }
end

-- Returns a world: w.boot(saved, charSaved, guid) simulates a login or /reload (saved variables
-- come back as stored; guid false makes UnitGUID return nil). w.game holds the cast context and
-- survives boots; w.printed collects chat output. w.bootClock, when set, is the fake
-- GetTimePreciseSec value at the next boot (default 5000).
function M.new()
    local w = {
        game = { rank = 11, modifier = 0, map = 1411, subzone = "Darkspear Strand" },
        serverTime = 1793836800,
    }

    function w.fire(event, ...)
        for _, frame in ipairs(w.env.frames) do
            frame:Fire(event, ...)
        end
    end

    function w.output()
        return table.concat(w.printed, "\n")
    end

    function w.boot(saved, charSaved, guid)
        w.env = fakeui.new()
        w.printed = {}
        w.clock, w.timers = w.bootClock or 5000, {}
        w.bootClock = nil
        w.serverTime = w.serverTime + 60
        _G.CreateFrame = w.env.CreateFrame
        _G.UIParent = w.env.UIParent
        _G.UISpecialFrames = {}
        _G.GameTooltip = w.env.GameTooltip
        _G.GetServerTime = function()
            return w.serverTime
        end
        _G.DEFAULT_CHAT_FRAME = {
            AddMessage = function(_, text)
                w.printed[#w.printed + 1] = text
            end,
        }
        _G.SlashCmdList = {}
        _G.C_AddOns = {
            GetAddOnMetadata = function(name, field)
                if name ~= M.ADDON or field ~= "Version" then
                    error(
                        "unexpected metadata request " .. tostring(name) .. " " .. tostring(field)
                    )
                end
                return "0.1.0"
            end,
        }
        _G.UnitGUID = function()
            if guid == false then
                return nil
            end
            return guid or M.GUID
        end
        _G.UnitFullName = function()
            return "Dingel", "Brightwater"
        end
        _G.GetRealmName = function()
            error("GetRealmName must not be used")
        end
        _G.GetTimePreciseSec = function()
            return w.clock
        end
        _G.C_Timer = {
            After = function(seconds, fn)
                w.timers[#w.timers + 1] = { at = w.clock + seconds, fn = fn }
            end,
        }
        _G.UnitChannelInfo = function()
            return "Fishing", "Fishing", 0, w.clock * 1000, w.clock * 1000 + 30000
        end
        _G.IsFishingLoot = function()
            return true
        end
        _G.GetGameMessageInfo = function(messageType)
            return messageType == 418 and "ERR_FISH_ESCAPED" or nil
        end
        _G.ERR_FISH_ESCAPED = "Your fish got away!"
        stubGame(w)
        _G.FishingMasteryDB = saved
        _G.FishingMasteryCharDB = charSaved
        w.ns = {}
        for _, file in ipairs(addon.tocFiles(M.ADDON)) do
            -- TOC paths use the client's backslash; loadfile needs a slash on every OS.
            assert(loadfile(M.ADDON .. "/" .. file:gsub("\\", "/")))(M.ADDON, w.ns)
        end
        w.fire("ADDON_LOADED", "SomeOtherAddon")
        w.fire("ADDON_LOADED", M.ADDON)
        w.fire("PLAYER_LOGIN")
    end

    -- Fires an event at a fake clock time (GetTimePreciseSec); server time moves with it.
    function w.at(t, event, ...)
        w.serverTime = w.serverTime + (t - w.clock)
        w.clock = t
        w.fire(event, ...)
    end

    -- Runs the guarded C_Timer callbacks that are due at time t.
    function w.runTimers(t)
        w.serverTime = w.serverTime + (t - w.clock)
        w.clock = t
        local due = w.timers
        w.timers = {}
        for _, timer in ipairs(due) do
            if timer.at <= t then
                timer.fn()
            else
                w.timers[#w.timers + 1] = timer
            end
        end
    end

    -- A full catch: channel start, stop, loot, loot closed.
    function w.catch(t, bite)
        w.at(t, "UNIT_SPELLCAST_CHANNEL_START", "player", nil, 7620)
        w.at(t + bite - 0.1, "UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 7620)
        w.at(t + bite, "LOOT_READY", false)
        w.at(t + bite + 0.5, "LOOT_CLOSED")
    end

    function w.cleanup()
        for _, name in ipairs(M.STUBS) do
            _G[name] = nil
        end
    end

    return w
end

return M
