local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local function read(path)
    local file = assert(io.open(rootPath .. "/" .. path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local sandboxDefinition = read("mod/42/media/sandbox-options.txt")
local sandboxEnglish = read("mod/42/media/lua/shared/Translate/EN/Sandbox.json")
for _, page in ipairs({ "General", "Companions", "World", "Developer" }) do
    assert(sandboxDefinition:find("page = KnoxSurvivors_" .. page, 1, true),
        "sandbox page is unused: " .. page)
    assert(sandboxEnglish:find('"Sandbox_KnoxSurvivors_' .. page .. '"', 1, true),
        "sandbox page translation missing: " .. page)
end
assert(sandboxDefinition:find("option KnoxSurvivors.Enabled", 1, true)
    < sandboxDefinition:find("option KnoxSurvivors.WorldPopulation", 1, true),
    "master enable must precede detailed population settings")
local function optionBlock(name)
    local startAt = assert(string.find(sandboxDefinition,
        "option KnoxSurvivors." .. name, 1, true), name .. " sandbox option missing")
    return string.sub(sandboxDefinition, startAt, startAt + 260)
end

local function assertDefault(name, expected)
    assert(string.find(optionBlock(name), "default = " .. tostring(expected), 1, true),
        name .. " sandbox declaration default drifted")
end

assert(not string.find(sandboxDefinition, "RequireTrustForRecruitment", 1, true)
    and not string.find(sandboxEnglish, "RequireTrustForRecruitment", 1, true),
    "trust recruitment setting is retired")
assertDefault("WorldPopulation", 48)
assertDefault("FollowerFormation", 1)
assertDefault("FollowerSpacing", 1)
assertDefault("InitialGroupChance", 65)
assertDefault("InitialGroupMaxSize", 4)
assertDefault("InitialGroupCount", 3)
assertDefault("MaxActiveSurvivors", 16)
assertDefault("PopulationRefillDays", 5)
assertDefault("MinimumSpawnDistance", 40)
assertDefault("SurvivorEncounterDistance", 280)
assertDefault("ActivationsPerUpdate", 2)
assertDefault("NPCFactionMinimumMembers", 4)
assertDefault("NPCFactionMaxMembers", 8)
assertDefault("AllowFactionRaids", false)
assertDefault("EnableKnoxEvents", false)
assert(not string.find(sandboxDefinition, "AllowSurvivorFleeing", 1, true)
    and not string.find(sandboxEnglish, "AllowSurvivorFleeing", 1, true),
    "fleeing is an internal risk decision rather than a sandbox option")
assertDefault("ShowDeveloperDiagnostics", false)
assertDefault("SurvivorAimingAssist", 1)
assertDefault("FactionRaidMinimumDays", 14)
assert(string.find(sandboxEnglish, "Allow NPC Factions (Work in Progress)", 1, true)
    and string.find(sandboxEnglish, "Allow Faction Raids (Experimental)", 1, true),
    "unfinished normal-play settings are identified in player-facing text")

SandboxVars = nil
require "KS_Settings"

assert(KnoxSettings.enabled(), "mod enabled default")
assert(KnoxSettings.companionLimit() == 4, "companion limit default")
assert(KnoxSettings.followerFormation() == "paired" and KnoxSettings.followerSpacing() == 1,
    "old saves retain compact paired follow positions")
assert(KnoxSettings.requireTrustForRecruitment == nil,
    "trust recruitment setting is no longer part of the player-facing settings")
assert(not KnoxSettings.capsDisabled(), "caps remain enabled by default")
assert(KnoxSettings.worldPopulation() == 48, "balanced world population default")
assert(KnoxSettings.maxActiveSurvivors() == 16, "balanced active population default")
assert(KnoxSettings.populationRefillDays() == 5, "balanced replacement default")
assert(KnoxSettings.minimumSpawnDistance() == 40, "balanced encounter distance default")
assert(KnoxSettings.activationBudget(0) == 2, "activation has a bounded construction budget")
assert(KnoxSettings.activationBudget(15) == 1 and KnoxSettings.activationBudget(16) == 0,
    "construction budget respects configured active cap")
assert(KnoxSettings.allowNPCFactions(), "factions default")
assert(KnoxSettings.npcFactionMinimumMembers() == 4,
    "travelling groups need four members before normal faction promotion")
assert(KnoxSettings.npcFactionMaxMembers() == 8,
    "NPC factions default to a bounded readable size")
assert(KnoxSettings.allowHostileEncounters(), "hostility default")
assert(not KnoxSettings.allowFactionRaids(), "experimental faction raids default off")
assert(not KnoxSettings.enableKnoxEvents(), "experimental events default off")
assert(KnoxSettings.factionRaidMinimumDays() == 14, "raid world-age balanced default")
assert(KnoxSettings.factionRaidIntervalDays() == 7, "raid interval default")
assert(KnoxSettings.survivorAimingAssist() == 1, "native aiming assistance default")
assert(KnoxSettings.showCompanionHUD(), "HUD default")
assert(KnoxSettings.showActivityFeed(), "feed default")
assert(not KnoxSettings.developerToolsEnabled(), "developer tools must default off")
assert(KnoxSettings.developerScenario() == "none", "developer scenario default")
assert(not KnoxSettings.allowDestructiveDeveloperTests(), "destructive tests default off")

SandboxVars = { KnoxSurvivors = {
    CompanionLimit = 99,
    AllowNPCFactions = false,
    NPCFactionMinimumMembers = 99,
    NPCFactionMaxMembers = 99,
    AllowHostileEncounters = false,
    AllowFactionRaids = true,
    EnableKnoxEvents = true,
    FactionRaidMinimumDays = 0,
    FactionRaidIntervalDays = 99,
    EnableDeveloperTools = true,
    DeveloperScenario = 6,
    DeveloperSpawnDistance = 2,
    AllowDestructiveDeveloperTests = true,
    SurvivorAimingAssist = 99,
} }

assert(KnoxSettings.companionLimit() == 12, "companion limit upper clamp")
assert(not KnoxSettings.allowNPCFactions(), "factions configured off")
assert(KnoxSettings.npcFactionMinimumMembers() == 8,
    "faction minimum has a bounded upper clamp")
assert(KnoxSettings.npcFactionMaxMembers() == 24,
    "faction maximum has a bounded upper clamp")
assert(not KnoxSettings.allowHostileEncounters(), "hostility configured off")
assert(not KnoxSettings.allowFactionRaids(), "raids require factions and hostile encounters")
assert(KnoxSettings.enableKnoxEvents(), "events can be enabled explicitly")
assert(KnoxSettings.factionRaidMinimumDays() == 1, "raid age lower clamp")
assert(KnoxSettings.factionRaidIntervalDays() == 30, "raid interval upper clamp")
assert(KnoxSettings.developerToolsEnabled(), "developer tools configured on")
assert(KnoxSettings.developerScenario() == "faction_base", "enum mapping")
assert(KnoxSettings.developerSpawnDistance() == 6, "spawn distance lower clamp")
assert(KnoxSettings.allowDestructiveDeveloperTests(), "destructive opt-in")
assert(KnoxSettings.survivorAimingAssist() == 3, "aiming assistance upper clamp")

SandboxVars.KnoxSurvivors.AllowNPCFactions = true
SandboxVars.KnoxSurvivors.AllowHostileEncounters = true
assert(KnoxSettings.allowFactionRaids(), "experimental raids remain available by explicit opt-in")

SandboxVars.KnoxSurvivors.PopulationRefillDays = 0
SandboxVars.KnoxSurvivors.FollowerFormation = 2
SandboxVars.KnoxSurvivors.FollowerSpacing = 99
assert(KnoxSettings.followerFormation() == "single_file" and KnoxSettings.followerSpacing() == 3,
    "single-file preference and bounded separation are available")
assert(KnoxSettings.populationRefillDays() == 0, "zero disables routine arrivals")
SandboxVars.KnoxSurvivors.MinimumSpawnDistance = 150
SandboxVars.KnoxSurvivors.SurvivorEncounterDistance = 120
assert(KnoxSettings.survivorEncounterDistance() == 160,
    "conflicting distances retain a hidden first-appearance band")
SandboxVars.KnoxSurvivors.NPCFactionMinimumMembers = 8
SandboxVars.KnoxSurvivors.NPCFactionMaxMembers = 3
assert(KnoxSettings.npcFactionMaxMembers() == 8,
    "faction capacity cannot be below its formation requirement")
for _, malformed in ipairs({ 0 / 0, math.huge, -math.huge, "invalid", {} }) do
    SandboxVars.KnoxSurvivors.WorldPopulation = malformed
    SandboxVars.KnoxSurvivors.ActivationsPerUpdate = malformed
    assert(KnoxSettings.worldPopulation() == 48 and KnoxSettings.activationsPerUpdate() == 2,
        "malformed settings fall back to bounded balanced defaults")
end
SandboxVars.KnoxSurvivors.ActivationsPerUpdate = nil
SandboxVars.KnoxSurvivors.WorldPopulation = nil

SandboxVars.KnoxSurvivors.DisableSurvivorCaps = true
assert(KnoxSettings.capsDisabled(), "explicit sandbox opt-in disables caps")
assert(KnoxSettings.companionLimit() == math.huge, "recruitment count no longer blocks companions")
assert(KnoxSettings.maxActiveSurvivors() == math.huge, "configured physical count no longer blocks activation")
assert(KnoxSettings.activationBudget(500) == 2, "uncapped population still has bounded per-update construction")
SandboxVars.KnoxSurvivors.DisableSurvivorCaps = false
assert(KnoxSettings.companionLimit() == 12, "re-enabling caps retains the configured value")

SandboxVars.KnoxSurvivors.Enabled = false
assert(not KnoxSettings.enabled(), "master switch")
assert(not KnoxSettings.developerToolsEnabled(), "master switch disables developer tools")
assert(not KnoxSettings.showCompanionHUD(), "master switch disables HUD")

print("sandbox settings PASS")

SandboxVars.KnoxSurvivors.Enabled = true
SandboxVars.KnoxSurvivors.DeveloperJobSupplies = nil
assert(not KnoxSettings.developerJobSuppliesEnabled(), "test job stock defaults off")
SandboxVars.KnoxSurvivors.DeveloperJobSupplies = true
SandboxVars.KnoxSurvivors.EnableDeveloperTools = false
assert(not KnoxSettings.developerJobSuppliesEnabled(), "resource assistance requires developer mode")
SandboxVars.KnoxSurvivors.EnableDeveloperTools = true
assert(KnoxSettings.developerJobSuppliesEnabled(), "test resources explicitly enabled")

assert(KnoxSettings.orderGesturesEnabled(), "order gestures default enabled")
SandboxVars.KnoxSurvivors.OrderGestures=false
assert(not KnoxSettings.orderGesturesEnabled(), "order gestures can be disabled")

SandboxVars=nil
assert(KnoxSettings.cautiousTravel() and KnoxSettings.zombieEngagementDistance()==4)
SandboxVars={KnoxSurvivors={CautiousTravel=false,ZombieEngagementDistance=1000}}
assert(not KnoxSettings.cautiousTravel() and KnoxSettings.zombieEngagementDistance()==16)
SandboxVars.KnoxSurvivors.ZombieEngagementDistance=0
assert(KnoxSettings.zombieEngagementDistance()==2)
SandboxVars.KnoxSurvivors.SurvivorAimingAssist=0
assert(KnoxSettings.survivorAimingAssist()==1, "aiming assistance lower clamp")

SandboxVars=nil
assert(KnoxSettings.npcDrivingSpeed()==20 and KnoxSettings.baseReadingEnabled())
SandboxVars={KnoxSurvivors={NpcDrivingSpeed=1000,BaseReading=false}}
assert(KnoxSettings.npcDrivingSpeed()==30 and not KnoxSettings.baseReadingEnabled())
SandboxVars.KnoxSurvivors.NpcDrivingSpeed=0
assert(KnoxSettings.npcDrivingSpeed()==5)
