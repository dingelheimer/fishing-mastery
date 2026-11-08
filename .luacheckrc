-- LuaJIT 2.1 (scoop build) segfaults in JIT-compiled luacheck code on full-tree runs; the
-- interpreter is stable. Turn the JIT off for this process when luacheck runs on LuaJIT.
if type(jit) == "table" and type(jit.off) == "function" then
    jit.off()
    jit.flush()
end

std = "lua51"
max_line_length = 100
exclude_files = { ".luarocks/", "probe-results/" }

-- Read-only WoW API shared by both addons.
read_globals = {
    "C_AddOns",
    "C_Timer",
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "GetServerTime",
    "GetTimePreciseSec",
    "debugstack",
    "issecretvalue",
}

-- The probe may write only its SavedVariables and the /fmp slash command.
files["FishingMasteryProbe/"] = {
    globals = { "FishingMasteryProbeDB", "SLASH_FMP1" },
    read_globals = { SlashCmdList = { fields = { FMP = { read_only = false } } } },
}

-- The addon may write only its two SavedVariables, the /fm slash command, and the addon
-- compartment handler named in its TOC (AddonCompartmentFunc).
files["FishingMastery/"] = {
    globals = {
        "FishingMasteryDB",
        "FishingMasteryCharDB",
        "SLASH_FM1",
        "SLASH_FM2",
        "FishingMastery_OnAddonCompartmentClick",
        -- Key Bindings window texts of Bindings.xml (CastKey.lua).
        "BINDING_HEADER_FISHINGMASTERY",
    },
    read_globals = { SlashCmdList = { fields = { FM = { read_only = false } } } },
}

files["spec/"] = { std = "+busted" }
