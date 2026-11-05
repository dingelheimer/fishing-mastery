-- Protected calls of named client APIs. Missing functions and errors are results, not failures.
local _, ns = ...

local type, pcall = type, pcall
local isSecret = issecretvalue or function()
    return false
end

local Calls = {}
ns.Calls = Calls

-- Raw protected call of the function at a dotted path: exists, ok, results... (unsanitized).
-- Use it only when the results are reduced before logging (e.g. through Redact).
function Calls.Invoke(env, path, ...)
    local fn = ns.Scan.Resolve(env, path)
    if isSecret(fn) or type(fn) ~= "function" then
        return false
    end
    return true, pcall(fn, ...)
end

-- Sanitized call result: { exists, ok, n, values }; values[1] is the error when not ok.
function Calls.Call(env, path, ...)
    local packed = ns.Serializer.Pack(Calls.Invoke(env, path, ...))
    if not packed[1] then
        return { exists = false }
    end
    local values = { n = packed.n - 2 }
    for i = 3, packed.n do
        values[i - 2] = packed[i]
    end
    return { exists = true, ok = packed[2], n = values.n, values = values }
end
