-- Pure logic: privacy reductions for everything the probe logs. Names and player GUIDs become
-- shape facts, other GUIDs keep only their type and IDs, positions are rounded.
local _, ns = ...

local type, tonumber, floor = type, tonumber, math.floor
local find, gmatch, match, gsub = string.find, string.gmatch, string.match, string.gsub
local isSecret = issecretvalue or function()
    return false
end

local Redact = {}
ns.Redact = Redact

-- A name or realm text: presence, byte length, and separator flags; never the text itself.
function Redact.Text(value)
    if isSecret(value) then
        return { secret = true }
    end
    if type(value) ~= "string" then
        return { present = false, type = type(value) }
    end
    return {
        present = value ~= "",
        length = #value,
        hasSpace = find(value, " ", 1, true) ~= nil,
        hasHyphen = find(value, "-", 1, true) ~= nil,
    }
end

-- A GUID such as "Player-1234-0ABCDEF0": its type word and segment count only. A first
-- segment that is not a plain word is replaced by "<other>".
function Redact.Guid(guid)
    if isSecret(guid) then
        return { secret = true }
    end
    if type(guid) ~= "string" then
        return { present = false, type = type(guid) }
    end
    local segments, first = 0, nil
    for part in gmatch(guid .. "-", "([^-]*)-") do
        segments = segments + 1
        first = first or part
    end
    return {
        present = true,
        type = match(first, "^%a+$") and first or "<other>",
        segments = segments,
    }
end

-- GUID types whose sixth segment is a game ID (NPC, object, vehicle) that may be kept.
Redact.ID_GUID_TYPES = { Creature = true, GameObject = true, Pet = true, Vehicle = true }
Redact.KNOWN_GUID_TYPES = {
    AreaTrigger = true,
    BattlePet = true,
    Cast = true,
    ClientActor = true,
    Corpse = true,
    Creature = true,
    GameObject = true,
    Item = true,
    Pet = true,
    Player = true,
    Vehicle = true,
    Vignette = true,
}

local function split(guid)
    local parts = {}
    for part in gmatch(guid .. "-", "([^-]*)-") do
        parts[#parts + 1] = part
    end
    return parts
end

-- True for strings shaped like a known GUID type ("Type-a-b...", at least three segments).
function Redact.IsGuid(value)
    if isSecret(value) or type(value) ~= "string" then
        return false
    end
    local guidType = match(value, "^(%a+)%-")
    return guidType ~= nil and Redact.KNOWN_GUID_TYPES[guidType] == true and #split(value) >= 3
end

-- A GUID reduced per the probe privacy rules: game objects, creatures, pets, and vehicles keep
-- type and object ID; casts keep type, spell ID, and cast ID; all others (players) keep type and
-- segment count only.
function Redact.SourceGuid(guid)
    local base = Redact.Guid(guid)
    if not base.present or base.secret then
        return base
    end
    local parts = split(guid)
    if Redact.ID_GUID_TYPES[base.type] then
        base.id = tonumber(parts[6])
    elseif base.type == "Cast" then
        base.spellID = tonumber(parts[6])
        base.castID = parts[7]
    end
    return base
end

-- Replaces the player's own name in a text with "<player>". Secret text stays untouched for
-- the serializer to mark.
function Redact.OwnName(text, ownName)
    if isSecret(text) or type(text) ~= "string" then
        return text
    end
    if isSecret(ownName) or type(ownName) ~= "string" or ownName == "" then
        return text
    end
    return (gsub(text, gsub(ownName, "%p", "%%%0"), "<player>"))
end

-- A string from an event payload: GUIDs are reduced, the own name is replaced.
function Redact.Value(value, ownName)
    if Redact.IsGuid(value) then
        return Redact.SourceGuid(value)
    end
    return Redact.OwnName(value, ownName)
end

-- A map coordinate (0..1) rounded to 0.1 % of the map.
function Redact.Position(value)
    if isSecret(value) or type(value) ~= "number" then
        return nil
    end
    return floor(value * 1000 + 0.5) / 1000
end
