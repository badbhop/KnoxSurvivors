local root = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local settings = read(root .. "/mod/42/media/lua/client/KS_Settings.lua")
local sandbox = read(root .. "/mod/42/media/sandbox-options.txt")
local bootstrap = read(root .. "/mod/42/media/lua/client/KS_Bootstrap.lua")
local qa = read(root .. "/mod/42/media/lua/client/KS_AutomatedQA.lua")
local matrix = read(root .. "/mod/42/media/lua/client/KS_AutomatedJobMatrix.lua")
local autonomy = read(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua")
local controllerSource = read(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local parser = read(root .. "/tools/parse-live-qa.ps1")

assert(string.find(settings, "AutomatedQAMode = false", 1, true),
    "automated QA must default off")
assert(string.find(settings, "function Settings.automatedQAMode", 1, true),
    "settings must expose an explicit QA gate")
assert(string.find(sandbox, "option KnoxSurvivors.AutomatedQAMode", 1, true),
    "sandbox must expose automated QA mode")
assert(string.find(bootstrap, 'require "KS_AutomatedQA"', 1, true),
    "bootstrap must load the QA coordinator")
local firearmTests = read(root .. "/mod/42/media/lua/client/KS_CombatTestScenarios.lua")
assert(string.find(firearmTests, "definition.firearm == true and 8 or 1", 1, true)
    and string.find(firearmTests, 'population = "independent_pair"', 1, true)
    and string.find(firearmTests, "setRelationshipDisposition", 1, true)
    and string.find(firearmTests, "native_ranged_human_damage_observed", 1, true)
    and string.find(firearmTests, "cleanupDeveloperScenario", 1, true),
    "firearm QA must isolate a hostile survivor duel, prove native ranged damage and clean fixtures")
assert(string.find(qa, "MAX_STEP_ATTEMPTS = 3", 1, true)
    and string.find(qa, "RETRY scenario=", 1, true),
    "legacy QA retry support must remain available during manifest migration")
assert(string.find(qa, "MAX_PASSES = 3", 1, true)
    and string.find(qa, "PASS_START pass=", 1, true)
    and string.find(qa, "QA pass ", 1, true)
    and string.find(qa, "QA FINISHED: ", 1, true)
    and string.find(qa, "stepDoneThisSuite", 1, true),
    "automated QA must rerun open scenarios up to 3 passes and announce FINISHED")
local vehicleTravel = read(root .. "/mod/42/media/lua/client/KS_NpcVehicleTravel.lua")
assert(string.find(vehicleTravel, "playerOwnsOrIsNear", 1, true)
    and string.find(vehicleTravel, "group.leaderId ~= controller.id", 1, true)
    and string.find(vehicleTravel, "KnoxCompanionVehicles.driveTo", 1, true),
    "autonomous vehicle travel must preserve player vehicles, leader ownership, and native driving")
local factionProperty = read(root .. "/mod/42/media/lua/client/KS_FactionProperty.lua")
assert(string.find(factionProperty, "recordPlayerFactionTheft", 1, true)
    and string.find(factionProperty, "not self.srcContainer:contains(item)", 1, true)
    and string.find(factionProperty, "isInCharacterInventory", 1, true),
    "faction property hostility must require a completed local-player inventory transfer")
local persistenceForProperty = read(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
assert(string.find(persistenceForProperty, "function KnoxPersistence.getBaseAtSquare", 1, true)
    and string.find(persistenceForProperty, "function KnoxPersistence.recordPlayerFactionTheft", 1, true),
    "faction property ownership and hostility must share persistence authority")
assert(string.find(controllerSource, "function Controller:tryBoardFollowVehicle", 1, true)
    and string.find(controllerSource, "self:tryBoardFollowVehicle(ticks)", 1, true),
    "following companions must board a nearby parked player vehicle through native actions")
assert(not string.find(qa, "ensurePlayerProtection", 1, true)
    and not string.find(qa, "setGodMod(", 1, true)
    and not string.find(qa, "setGhostMode(", 1, true)
    and not string.find(qa, "setInvisible(", 1, true)
    and not string.find(qa, "setZombiesDontAttack", 1, true)
    and not string.find(qa, "releasePlayerProtection", 1, true)
    and string.find(qa, "GLOBAL_TIMEOUT_TICKS", 1, true)
    and string.find(qa, "suite_timeout", 1, true),
    "automated QA must never write player protection flags and must bound the full run")
for _, token in ipairs({
    "preflight", "equipment_persistence", "needs_consumption", "health_injury",
    "medical_treatment", "loot_transfer", "npc_combat", "population_autonomy",
    "faction_admission", "traversal", "base_storage_jobs", "base_job_matrix", "firearm_combat", "PROBE_WAIT",
    "hostile_encounter", "raid_eligibility", "vehicle_boarding", "night_shelter",
    "persistence_roundtrip",
    "BLOCKED", "probe_timeout", "native_consumption_verified", "combat_timeout",
    "manual_review=visual_feel_only", "config.enabled = true",
    "table.concat(scenarioNames, \",\")",
    "FACTION_WAIT", "faction_settlement_arrival", "distinct_indoor_arrivals",
    "cleanupDeveloperScenario", "JOB_MATRIX_TIMEOUT",
    "hostile_relationship_recorded", "raid_proposal_valid",
    "passenger_seat_available", "indoor_shelter_found",
    "save_capture_verified",
    "automated_q_a_requires_enable_developer_tools",
}) do
    assert(string.find(qa, token, 1, true),
        "QA coordinator must include " .. token)
end
local traversal = read(root .. "/mod/42/media/lua/client/KS_NpcSpawnProbe.lua")
assert(string.find(traversal, 'if tostring(tickResult) == "Succeeded" then', 1, true),
    "traversal coordinator must latch the one-tick native success result")
local failBlock = string.match(qa, "local function failCurrent.-\nend") or ""
assert(string.find(failBlock, "advanceStep()", 1, true)
    and not string.find(failBlock, "finish()", 1, true),
    "one scenario failure must be recorded and continue through the full suite")
for _, token in ipairs({
    "job_guard_admission", "job_patrol_admission", "job_farming_admission",
    "job_woodcutting_admission", "job_saw_logs_admission",
    "job_barricade_admission", "job_repair_admission", "job_cooking_admission",
    "job_corpse_haul_admission", "native_task_admitted", "native_work_state_entered",
    "native_task_completed", "native_task_completion_timeout",
}) do
    assert(string.find(matrix, token, 1, true),
        "automated job matrix must include " .. token)
end
assert(string.find(matrix, "EXECUTION_STATES[controllerState] and taskStillOwned", 1, true),
    "job execution must belong to the exact claimed task")
assert(not string.find(matrix,
    'EXECUTION_STATES[controllerState] or taskStillOwned', 1, true),
    "unrelated survivor activity must not pass job execution")
assert(string.find(matrix, "releaseResidentClaims(step.types)", 1, true),
    "the matrix must preserve the exact preclaimed job it is about to execute")
assert(string.find(qa,
    'local invoked, spawned, encoded = pcall(function()', 1, true),
    "base-job QA must keep pcall success separate from the spawned survivor ID")
for _, kind in ipairs({
    'kind = "encounter"', 'kind = "raid"', 'kind = "vehicle"',
    'kind = "shelter"', 'kind = "persistence"',
}) do
    assert(string.find(qa, kind, 1, true),
        "QA coordinator must dispatch " .. kind)
end
assert(string.find(qa, "proposeRaid", 1, true)
    and string.find(qa, "findFreePassengerSeat", 1, true)
    and string.find(qa, "findShelter", 1, true)
    and string.find(qa, "captureAllActiveSurvivors", 1, true)
    and string.find(qa, "setRelationshipDisposition", 1, true),
    "boundary checks must use the real planning/seat/shelter/save APIs")
assert(string.find(autonomy, "function Autonomy.cleanupDeveloperScenario", 1, true)
    and string.find(autonomy, 'string.find(id, "ks-dev-", 1, true) ~= 1', 1, true)
    and string.find(autonomy, "KnoxPersistence.markSurvivorDead", 1, true),
    "automated QA cleanup must be restricted to disposable developer survivors")
local persistence = read(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
assert(string.find(persistence, "function KnoxPersistence.purgeDeveloperQaBases", 1, true)
    and string.find(persistence, "removeSafeHouse", 1, true),
    "automated QA must clean only developer faction bases and safehouses")
for _, probe in ipairs({
    "KS_EquipmentProbe", "KS_NeedsProbe", "KS_HealthProbe", "KS_MedicalProbe",
    "KS_LootProbe", "KS_CombatProbe", "KS_PopulationProbe",
}) do
    local probePath = root .. "/mod/42/media/lua/client/" .. probe .. ".lua"
    local source = read(probePath)
    assert(string.find(source, "function Probe.start", 1, true)
        and string.find(source, "function Probe.status", 1, true),
        probe .. " must expose coordinator start/status adapters")
end
assert(string.find(parser, "AutomatedQA", 1, true)
    and string.find(parser, "ConvertTo-Json", 1, true)
    and string.find(parser, "START (?:runId=(\\S+) )?save_is_disposable=true", 1, true)
    and string.find(parser, "$entries = @()", 1, true)
    and string.find(parser, "$checkpoints = @()", 1, true)
    and string.find(parser, "HARNESS_ERROR", 1, true)
    and string.find(parser, "evidenceType", 1, true),
    "live QA parser must preserve run metadata, checkpoints and harness verdicts")

for _, token in ipairs({
    'id = "QA-START-001"', 'id = "QA-ENCOUNTER-001"',
    'id = "QA-RECRUIT-001"', 'id = "QA-CHECKPOINT-001"',
    'id = "QA-CLEANUP-001"', 'PASS = true', 'FAIL = true',
    'BLOCKED = true', 'SKIPPED = true', 'HARNESS_ERROR = true',
    'CHECKPOINT runId=', 'scope=controlled_fixture_not_natural_encounter',
    'fixture_ownership_invalid', 'native_fixture_not_materialized',
    'mutation=none', 'owned_fixture_cleanup_failed', 'scenario_exception',
    'scenario_timeout', 'cleanupVerticalFixtures', 'state.mode == "vertical_slice"',
}) do
    assert(string.find(qa, token, 1, true),
        "vertical QA slice must include " .. token)
end
assert(not string.find(qa:sub(qa:find("local function runVerticalScenario", 1, true),
    qa:find("local function finishVertical", 1, true)), "clearQaArea(", 1, true),
    "vertical QA slice must never clear ordinary zombies or world entities")

print("Automated QA PASS opt_in=true unattended_coordinator=true report_parser=true")
