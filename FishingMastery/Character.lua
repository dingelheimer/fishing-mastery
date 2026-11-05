-- Character key and entry. The key is UnitGUID("player"); the two name parts are stored for
-- display only. GetRealmName() is not part of a Forever character's identity and is never used.
local _, ns = ...

local type, pairs = type, pairs
local isSecret = issecretvalue or function()
    return false
end

local Character = {}
ns.Character = Character

local GUID_PATTERN = "^Player%-%d+%-%x+$"

local function plainString(value)
    if isSecret(value) or type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

-- Returns the player's GUID, or nil when it is missing, secret, or not a player GUID.
function Character.Key(env)
    local getGuid = env.UnitGUID
    if type(getGuid) ~= "function" then
        return nil
    end
    local guid = plainString(getGuid("player"))
    if guid and guid:match(GUID_PATTERN) then
        return guid
    end
    return nil
end

-- Returns the two name parts: UnitFullName gives the name and a second part in the realm slot.
local function nameParts(env)
    local getName = env.UnitFullName or env.UnitName
    if type(getName) ~= "function" then
        return nil, nil
    end
    local name, part = getName("player")
    return plainString(name), plainString(part)
end

-- Creates or updates the entry of the logged-in character in db.chars.
-- Returns key, entry; nil when the GUID is not available.
function Character.Ensure(db, env, now)
    local key = Character.Key(env)
    if not key then
        return nil
    end
    local entry = db.chars[key]
    if not entry then
        entry = { firstSeen = now }
        db.chars[key] = entry
    end
    local name, part = nameParts(env)
    entry.name = name or entry.name
    entry.part = part or entry.part
    entry.lastSeen = now
    return key, entry
end

function Character.Count(db)
    local count = 0
    for _ in pairs(db and db.chars or {}) do
        count = count + 1
    end
    return count
end
