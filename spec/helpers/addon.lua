-- Loads addon files the way the WoW client does: each chunk gets (addonName, ns).
local M = {}

M.ADDON_NAME = "FishingMasteryProbe"

-- Loads files from the probe folder, or from the folder named by addonName.
function M.load(files, ns, addonName)
    ns = ns or {}
    addonName = addonName or M.ADDON_NAME
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(addonName .. "/" .. file))
        chunk(addonName, ns)
    end
    return ns
end

-- Lists the Lua files of an addon's TOC in load order.
function M.tocFiles(addonName)
    local files = {}
    for line in io.lines(addonName .. "/" .. addonName .. ".toc") do
        if line:match("%.lua%s*$") then
            files[#files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    return files
end

return M
