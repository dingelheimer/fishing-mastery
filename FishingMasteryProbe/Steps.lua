-- Data: the guided test run steps S0-S15 from the probe plan.
-- Texts are English and shown through ns.L (the English text is the locale key).
-- target = { kind, count }: kinds are counted by Progress.Observe (catch, attempt, timeout,
-- cancel, getaway, hover, check). Steps without a target are finished with Done.
-- snapshot = "start" / "done": a cast-context snapshot is logged when the step starts / is done.
-- showSnapshot / showLogPath: the window adds the login snapshot result / the log file path.
-- helpers: the window shows the S14 helper test buttons and their states (Helpers.lua).
local _, ns = ...

local ipairs = ipairs

local Steps = {}
ns.Steps = Steps

Steps.list = {
    {
        id = "S0",
        title = "Login snapshot",
        instruction = "Nothing to do. The probe recorded the game environment when you logged in. "
            .. "Read the result below, then press Done.",
        why = "Build, API, event, and global string facts answer the first questions without any "
            .. "fishing.",
        prereq = "None.",
        showSnapshot = true,
        showLogPath = true,
        questions = { "Q01", "Q02", "Q03", "Q04", "Q05", "Q20", "Q21", "Q29" },
    },
    {
        id = "S1",
        title = "Without fishing pole",
        instruction = "Unequip your fishing pole (put it in your bags), then press Done.",
        why = "Shows your fishing skill without the pole bonus.",
        prereq = "Fishing learned, a fishing pole equipped.",
        snapshot = "done",
        questions = { "Q07" },
    },
    {
        id = "S2",
        title = "With fishing pole",
        instruction = "Equip your fishing pole without a lure, then press Done.",
        why = "Shows the pole item and whether its bonus is part of your skill value.",
        prereq = "A fishing pole in your bags, no lure applied.",
        snapshot = "done",
        questions = { "Q07", "Q17" },
    },
    {
        id = "S3",
        title = "Catch fish, auto loot off",
        instruction = "Turn auto loot off. Press Start, then catch 5 fish normally: cast, wait "
            .. "for the splash, click the bobber, and loot by hand.",
        why = "Records the normal event order, loot data, item info, auras, and zone per cast.",
        prereq = "Auto loot off (Options > Controls > Auto Loot), fishable water nearby.",
        target = { kind = "catch", count = 5 },
        questions = { "Q06", "Q08", "Q09", "Q18", "Q19", "Q23", "Q24", "Q32" },
    },
    {
        id = "S4",
        title = "Catch fish, auto loot on",
        instruction = "Turn auto loot on. Press Start, then catch 3 fish normally.",
        why = "Shows how loot events change when the loot window does not open.",
        prereq = "Auto loot on (Options > Controls > Auto Loot).",
        target = { kind = "catch", count = 3 },
        questions = { "Q08", "Q09", "Q32" },
    },
    {
        id = "S5",
        title = "Click too early",
        instruction = "Press Start. Cast, then click the bobber before it splashes. Do this twice.",
        why = "Finds the event and message for an early click.",
        prereq = "Fishable water nearby.",
        target = { kind = "attempt", count = 2 },
        questions = { "Q11" },
    },
    {
        id = "S6",
        title = "Let the bobber time out",
        instruction = "Press Start. Cast and do not click; wait until the bobber disappears. "
            .. "Do this twice.",
        why = "Measures the channel duration and the events of a timeout.",
        prereq = "Fishable water nearby.",
        target = { kind = "timeout", count = 2 },
        questions = { "Q12" },
    },
    {
        id = "S7",
        title = "Cancel by moving",
        instruction = "Press Start. Cast, then jump or move right away. Do this twice.",
        why = "Finds the events when a cast is cancelled.",
        prereq = "Fishable water nearby.",
        target = { kind = "cancel", count = 2 },
        questions = { "Q13" },
    },
    {
        id = "S8",
        title = "Cast at land",
        instruction = "Press Start. Cast once at land or at very shallow water.",
        why = "Finds the error event and message for an invalid target.",
        prereq = "Land or shallow water in front of you.",
        target = { kind = "attempt", count = 1 },
        questions = { "Q15" },
    },
    {
        id = "S9",
        title = "Fish with a lure",
        instruction = "Apply a lure to your fishing pole, then press Start and catch 2 fish.",
        why = "Shows how an applied lure is visible to addons and how it changes your skill.",
        prereq = "A fishing lure. Skip this step if you have none.",
        target = { kind = "catch", count = 2 },
        snapshot = "start",
        questions = { "Q07", "Q16" },
    },
    {
        id = "S10",
        title = "Hover the bobber",
        instruction = "Press Start. Cast, then hold the mouse over the bobber for 2 seconds.",
        why = "Shows what the bobber tooltip contains.",
        prereq = "Fishable water nearby.",
        target = { kind = "hover", count = 1 },
        questions = { "Q26" },
    },
    {
        id = "S11",
        title = "Fish a school or wreckage",
        instruction = "Press Start, then catch 2 fish from a fish school or wreckage.",
        why = "Shows how pool loot is identified.",
        prereq = "A fish school or wreckage nearby.",
        target = { kind = "catch", count = 2 },
        optional = true,
        questions = { "Q10" },
    },
    {
        id = "S12",
        title = "Let a fish get away",
        instruction = "Press Start. Fish in a zone above your skill until a fish gets away.",
        why = "Finds the event and message when a fish escapes.",
        prereq = "A zone whose fishing skill is above yours.",
        target = { kind = "getaway", count = 1 },
        optional = true,
        questions = { "Q14" },
    },
    {
        id = "S13",
        title = "Fish with buff food",
        instruction = "Eat fishing buff food or use a camp buff, then press Start and catch "
            .. "1 fish.",
        why = "Records the buff aura and its effect on your skill.",
        prereq = "Fishing buff food or a camp buff.",
        target = { kind = "catch", count = 1 },
        optional = true,
        questions = { "Q31" },
    },
    {
        id = "S14",
        title = "Test key and self-whisper",
        instruction = "Out of combat at fishable water: press Start. Test key: press Enable "
            .. "test key, face the water, and press the key shown below once. Self-whisper: "
            .. "press Send self-whisper. Each test logs one result.",
        why = "Shows whether helper key bindings and addon messages work on Forever.",
        prereq = "Out of combat, fishing pole equipped, fishable water in front of you.",
        target = { kind = "check", count = 2 },
        helpers = true,
        questions = { "Q27", "Q28" },
    },
    {
        id = "S15",
        title = "Reload, log out, hand over",
        instruction = "1. Press Done.  2. Type /reload.  3. Log out completely.  4. Copy the log "
            .. "file below into the folder probe-results of the fishing-mastery repository and "
            .. "tell the agent.",
        why = "The game writes the log file only on /reload or logout; the reload also tests "
            .. "that saved data survives.",
        prereq = "All other steps done or skipped.",
        showLogPath = true,
        questions = { "Q22" },
    },
}

Steps.byId = {}
for index, step in ipairs(Steps.list) do
    step.index = index
    Steps.byId[step.id] = step
end
