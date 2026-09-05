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
local function optionBlock(name)
    local startAt = assert(string.find(sandboxDefinition,
        "option KnoxSurvivors." .. name, 1, true), name .. " sandbox option missing")
    return string.sub(sandboxDefinition, startAt, startAt + 260)
end

local function assertDefault(name, expected)
    assert(string.find(optionBlock(name), "default = " .. tostring(expected), 1, true),
        name .. " sandbox declaration default drifted")
end

local trustOptionAt = string.find(sandboxDefinition,
    "option KnoxSurvivors.RequireTrustForRecruitment", 1, true)
local trustOptionBlock = trustOptionAt ~= nil
    and string.sub(sandboxDefinition, trustOptionAt, trustOptionAt + 240) or ""
assert(trustOptionAt ~= nil
    and string.find(trustOptionBlock, "type = boolean, default = false", 1, true),
    "trust recruitment setting is declared off by default")
assert(string.find(sandboxEnglish, "Sandbox_KnoxSurvivors_RequireTrustForRecruitment", 1, true),
    "trust recruitment setting has player-facing English text")
assertDefault("WorldPopulation", 48)
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
assertDefault("AllowSurvivorFleeing", false)
assertDefault("ShowDeveloperDiagnostics", false)
assertDefault("FactionRaidMinimumDays", 14)
assert(string.find(sandboxEnglish, "Allow NPC Factions (Work in Progress)", 1, true)
    and string.find(sandboxEnglish, "Allow Faction Raids (Experimental)", 1, true),
    "unfinished normal-play settings are identified in player-facing text")

SandboxVars = nil
require "KS_Settings"

assert(KnoxSettings.enabled(), "mod enabled default")
assert(KnoxSettings.companionLimit() == 4, "companion limit default")
assert(not KnoxSettings.requireTrustForRecruitment(), "trust requirement defaults off")
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
assert(not KnoxSettings.allowSurvivorFleeing(), "experimental fleeing defaults off")
assert(not KnoxSettings.allowFactionRaids(), "experimental faction raids default off")
assert(not KnoxSettings.enableKnoxEvents(), "experimental events default off")
assert(KnoxSettings.factionRaidMinimumDays() == 14, "raid world-age balanced default")
assert(KnoxSettings.factionRaidIntervalDays() == 7, "raid interval default")
assert(KnoxSettings.showCompanionHUD(), "HUD default")
assert(KnoxSettings.showActivityFeed(), "feed default")
assert(not KnoxSettings.developerToolsEnabled(), "developer tools must default off")
assert(KnoxSettings.developerScenario() == "none", "developer scenario default")
assert(not KnoxSettings.allowDestructiveDeveloperTests(), "destructive tests default off")

SandboxVars = { KnoxSurvivors = {
    CompanionLimit = 99,
    RequireTrustForRecruitment = true,
    AllowNPCFactions = false,
    NPCFactionMinimumMembers = 99,
    NPCFactionMaxMembers = 99,
    AllowHostileEncounters = false,
    AllowSurvivorFleeing = true,
    AllowFactionRaids = true,
    EnableKnoxEvents = true,
    FactionRaidMinimumDays = 0,
    FactionRaidIntervalDays = 99,
    EnableDeveloperTools = true,
    DeveloperScenario = 6,
    DeveloperSpawnDistance = 2,
    AllowDestructiveDeveloperTests = true,
} }

assert(KnoxSettings.companionLimit() == 12, "companion limit upper clamp")
assert(KnoxSettings.requireTrustForRecruitment(), "trust requirement explicit opt-in")
assert(not KnoxSettings.allowNPCFactions(), "factions configured off")
assert(KnoxSettings.npcFactionMinimumMembers() == 8,
    "faction minimum has a bounded upper clamp")
assert(KnoxSettings.npcFactionMaxMembers() == 24,
    "faction maximum has a bounded upper clamp")
assert(not KnoxSettings.allowHostileEncounters(), "hostility configured off")
assert(KnoxSettings.allowSurvivorFleeing(), "fleeing remains an explicit sandbox opt-in")
assert(not KnoxSettings.allowFactionRaids(), "raids require factions and hostile encounters")
assert(KnoxSettings.enableKnoxEvents(), "events can be enabled explicitly")
assert(KnoxSettings.factionRaidMinimumDays() == 1, "raid age lower clamp")
assert(KnoxSettings.factionRaidIntervalDays() == 30, "raid interval upper clamp")
assert(KnoxSettings.developerToolsEnabled(), "developer tools configured on")
assert(KnoxSettings.developerScenario() == "faction_base", "enum mapping")
assert(KnoxSettings.developerSpawnDistance() == 6, "spawn distance lower clamp")
assert(KnoxSettings.allowDestructiveDeveloperTests(), "destructive opt-in")

SandboxVars.KnoxSurvivors.AllowNPCFactions = true
SandboxVars.KnoxSurvivors.AllowHostileEncounters = true
assert(KnoxSettings.allowFactionRaids(), "experimental raids remain available by explicit opt-in")

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
