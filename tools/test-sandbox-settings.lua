local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

SandboxVars = nil
require "KS_Settings"

assert(KnoxSettings.enabled(), "mod enabled default")
assert(KnoxSettings.companionLimit() == 4, "companion limit default")
assert(KnoxSettings.allowNPCFactions(), "factions default")
assert(KnoxSettings.allowHostileEncounters(), "hostility default")
assert(KnoxSettings.showCompanionHUD(), "HUD default")
assert(KnoxSettings.showActivityFeed(), "feed default")
assert(not KnoxSettings.developerToolsEnabled(), "developer tools must default off")
assert(KnoxSettings.developerScenario() == "none", "developer scenario default")
assert(not KnoxSettings.allowDestructiveDeveloperTests(), "destructive tests default off")

SandboxVars = { KnoxSurvivors = {
    CompanionLimit = 99,
    AllowNPCFactions = false,
    AllowHostileEncounters = false,
    EnableDeveloperTools = true,
    DeveloperScenario = 6,
    DeveloperSpawnDistance = 2,
    AllowDestructiveDeveloperTests = true,
} }

assert(KnoxSettings.companionLimit() == 12, "companion limit upper clamp")
assert(not KnoxSettings.allowNPCFactions(), "factions configured off")
assert(not KnoxSettings.allowHostileEncounters(), "hostility configured off")
assert(KnoxSettings.developerToolsEnabled(), "developer tools configured on")
assert(KnoxSettings.developerScenario() == "faction_base", "enum mapping")
assert(KnoxSettings.developerSpawnDistance() == 6, "spawn distance lower clamp")
assert(KnoxSettings.allowDestructiveDeveloperTests(), "destructive opt-in")

SandboxVars.KnoxSurvivors.Enabled = false
assert(not KnoxSettings.enabled(), "master switch")
assert(not KnoxSettings.developerToolsEnabled(), "master switch disables developer tools")
assert(not KnoxSettings.showCompanionHUD(), "master switch disables HUD")

print("sandbox settings PASS")
