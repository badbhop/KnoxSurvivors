-- The scenario harness must stop rather than emit misleading missing-controller
-- diagnostics after every test survivor has completed native death handling.
local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_CombatTestScenarios.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(string.find(source, 'status=eliminated', 1, true),
    "dead test survivors must be reported as eliminated")
assert(string.find(source, 'all_test_survivors_eliminated', 1, true),
    "scenario must finish after every test survivor is eliminated")
assert(string.find(source, 'KnoxPersistence.setSurvivorWeaponPreference(id, "ranged")', 1, true),
    "firearm scenario explicitly exercises guns despite ordinary melee preference")

print("Combat scenario reporting PASS eliminated_terminal=true")
