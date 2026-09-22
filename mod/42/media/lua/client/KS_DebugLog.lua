-- Central structured diagnostics for Knox Survivors.
--
-- Goals: exact failure causes in console.txt without spamming it.
-- Failures and state transitions log immediately (first time + every 10th
-- repeat). Steady-state polls never log. Verbose per-tick detail is gated
-- behind ShowDeveloperDiagnostics.
local DebugLog = rawget(_G, "KnoxDebugLog") or {}
_G.KnoxDebugLog = DebugLog

local counts = {}
local lastVerboseTick = {}

local function settings()
    return rawget(_G, "KnoxSettings")
end

function DebugLog.verboseEnabled()
    local s = settings()
    if s == nil or s.showDeveloperDiagnostics == nil then return false end
    local ok, value = pcall(function() return s.showDeveloperDiagnostics() end)
    return ok and value == true
end

-- Permanent master switch for all structured diagnostics. This is the
-- existing sandbox path (Developer page: EnableDeveloperTools +
-- ShowDeveloperDiagnostics), shared with the old verbose logging rather
-- than a parallel option. Missing settings (offline tests, early load)
-- default ON so diagnostics never silently vanish outside the game.
local function diagnosticsOn()
    local s = settings()
    if s == nil or s.showDeveloperDiagnostics == nil then return true end
    local ok, value = pcall(function() return s.showDeveloperDiagnostics() end)
    return ok and value == true
end

function DebugLog.diagnosticsEnabled()
    return diagnosticsOn()
end

local function formatDetails(details)
    if type(details) ~= "table" then
        return details ~= nil and (" " .. tostring(details)) or ""
    end
    local parts = {}
    local keys = {}
    for key in pairs(details) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local value = details[key]
        if type(value) == "number" then
            value = string.format("%.2f", value)
        end
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end
    if #parts == 0 then return "" end
    return " " .. table.concat(parts, " ")
end

-- Failures/transitions: 1st occurrence + every 10th, while the sandbox
-- diagnostics switch is on. Returns true when the line was emitted.
function DebugLog.log(category, id, event, details)
    if not diagnosticsOn() then return false end
    local key = tostring(category) .. ":" .. tostring(id) .. ":" .. tostring(event)
    counts[key] = (counts[key] or 0) + 1
    local count = counts[key]
    if count ~= 1 and count % 10 ~= 0 then return false end
    print("[KnoxSurvivors][Diag][" .. tostring(category) .. "] id=" .. tostring(id)
        .. " event=" .. tostring(event) .. formatDetails(details)
        .. " count=" .. tostring(count))
    return true
end

-- Verbose per-tick detail. Gated behind ShowDeveloperDiagnostics and a
-- per-key tick throttle so enabling diagnostics cannot flood console.txt.
function DebugLog.verbose(category, id, event, details, ticks, throttleTicks)
    if not DebugLog.verboseEnabled() then return false end
    local key = tostring(category) .. ":" .. tostring(id) .. ":" .. tostring(event)
    local now = tonumber(ticks) or 0
    local throttle = tonumber(throttleTicks) or 600
    if lastVerboseTick[key] ~= nil and now - lastVerboseTick[key] < throttle then
        return false
    end
    lastVerboseTick[key] = now
    print("[KnoxSurvivors][Diag][" .. tostring(category) .. "] id=" .. tostring(id)
        .. " event=" .. tostring(event) .. formatDetails(details))
    return true
end

-- One-shot state snapshot, bypassing the repeat throttle. Use sparingly:
-- queue results, completion verdicts, kit seeding, combat start/end.
-- Same sandbox switch as log(): removing QA later changes nothing here.
function DebugLog.once(category, id, event, details)
    if not diagnosticsOn() then return false end
    print("[KnoxSurvivors][Diag][" .. tostring(category) .. "] id=" .. tostring(id)
        .. " event=" .. tostring(event) .. formatDetails(details))
    return true
end

function DebugLog.reset()
    counts = {}
    lastVerboseTick = {}
end

-- Plain-language brief for a machine reason code. Every test verdict (QA
-- steps, probes, combat scenarios, job matrix) funnels its feed/console line
-- through here so a FAIL/BLOCKED always says why in one short line.
-- Unknown codes fall back to the raw code; never nil.
local BRIEFS = {
    timeout = "Timed out waiting for the expected native action.",
    probe_timeout = "Probe saw no result before its deadline.",
    probe_start_rejected = "Probe refused to start (bad fixture or gate).",
    probe_unavailable = "Probe module missing.",
    probe_status_failed = "Probe status read failed.",
    probe_finished_without_result = "Probe ended with no verdict recorded.",
    active_probe_missing = "Coordinator lost its active probe handle.",
    suite_timeout = "Whole suite exceeded its global tick budget.",
    combat_timeout = "Combat ended with no decisive native damage in time.",
    combat_start_failed = "Combat fixture could not be spawned or engaged.",
    combat_failed = "Combat finished without the required damage proof.",
    no_two_way_combat = "Survivor dealt nothing and took nothing.",
    survivor_damage_only = "Survivor hit but never got hit back.",
    zombie_attack_animation_without_damage = "Zombie swung but no damage registered.",
    no_native_ranged_damage = "No native shots, or shots dealt no damage.",
    staging_timeout = "Duelists never got both pistols loaded and ready in time.",
    staging_controllers_missing = "A duelist body vanished while staging pistols.",
    no_standable_zombie_spawn_square = "No free tile near the survivor to spawn the zombie.",
    no_standable_needs_fixture = "No free tile near the player for the needs dummy.",
    all_test_survivors_eliminated = "Every test survivor died mid-scenario.",
    native_consumption_timeout = "Needs bars never moved after eat/drink actions.",
    needs_action_retry_limit = "Eat/drink actions kept failing to queue.",
    test_state_missing = "Test fixture body went missing mid-step.",
    health_gate_prepare_failed = "Java health gate refused to arm.",
    no_adjacent_zombie_square = "No free tile next to the survivor for the attacker.",
    test_zombie_spawn_failed = "Engine refused the zombie spawn.",
    test_zombie_killed_without_damage = "Survivor killed each attacker before it could land a hit.",
    zombie_target_failed = "Attacker would not lock onto the survivor.",
    zombie_retarget_failed = "Attacker lost its lock and would not re-acquire.",
    zombie_movement_failed = "Attacker could not path to the survivor.",
    minor_injury_normalization_failed = "Controlled scratch could not be applied.",
    controlled_injury_missing = "Normalized injury did not stick.",
    post_injury_save_failed = "Injured survivor record would not save.",
    survivor_restore_failed = "Saved survivor would not restore into the world.",
    saved_square_not_loaded = "Save square not loaded yet; still waiting.",
    npc_character_unavailable = "Test body missing after restore.",
    saved_injury_not_restored = "Reload lost the saved injury.",
    post_loot_inventory_not_restored = "Reload lost saved inventory.",
    native_task_completion_timeout = "Worker never finished the native action.",
    native_work_state_timeout = "Worker never entered the work state.",
    native_task_blocked_before_execution = "Task blocked before the worker moved.",
    native_task_blocked = "Task blocked mid-execution.",
    native_task_disappeared = "Task record vanished mid-execution.",
    no_native_target_fixture = "No real world target (crop/tree/window/corpse) found.",
    task_not_claimable = "Resident could not claim the queued task.",
    job_matrix_timeout = "Job matrix never finished all admissions.",
    job_matrix_start_failed = "Job matrix fixture failed to start.",
    job_matrix_state_missing = "Job matrix lost its run state.",
    job_matrix_unavailable = "Job matrix module missing.",
    guard_task_not_queued = "Guard post never produced a task.",
    guard_zone_create_failed = "Guard zone could not be created.",
    base_setup_failed = "Player base could not be established here.",
    base_modules_unavailable = "Base modules missing.",
    no_loaded_building_fixture = "No building near the player for the base.",
    no_assignable_storage_fixture = "No usable container in the base area.",
    storage_policy_not_resolved = "Storage policy points at nothing loaded.",
    assigned_storage_receipt_missing = "Seeded hammer never showed in storage.",
    resident_fixture_unavailable = "Disposable resident would not spawn.",
    resident_assignment_failed = "Resident could not join the base.",
    resident_body_unavailable = "Resident body missing after spawn.",
    developer_spawn_failed = "Developer survivor spawn failed.",
    developer_spawn_unavailable = "No player/bridge/square to spawn from.",
    developer_character_missing = "Spawned body missing.",
    encounter_spawn_failed = "Hostile-pair spawn failed.",
    encounter_spawn_short = "Fewer than 2 survivors spawned.",
    encounter_fixture_unavailable = "Encounter needs player/persistence/autonomy.",
    hostile_record_rejected = "Hostility record would not persist.",
    no_raid_fixture = "No source faction or target base exists.",
    no_valid_raid_proposal = "No source/target pair passes raid rules.",
    raid_modules_unavailable = "Raid planning modules missing.",
    faction_roster_unavailable = "Faction/base roster unreadable.",
    faction_spawn_failed = "Faction fixture would not spawn.",
    faction_fixture_unavailable = "Faction needs player/persistence/autonomy.",
    faction_membership_inconsistent = "Members disagree about their faction.",
    faction_disappeared = "Faction record vanished mid-wait.",
    faction_member_lost = "A faction member died or left.",
    faction_wait_state_missing = "Faction wait lost its context.",
    npc_factions_disabled = "NPC factions off in sandbox options.",
    no_vehicle_fixture = "No vehicle within 25 tiles.",
    no_free_passenger_seat = "Every seat taken, locked, or driver-reserved.",
    passenger_fixture_unavailable = "Passenger dummy would not spawn.",
    passenger_body_unavailable = "Passenger body missing after spawn.",
    vehicle_modules_unavailable = "Vehicle modules missing.",
    no_shelter_fixture = "No indoor square within 24 tiles.",
    shelter_modules_unavailable = "Shelter search module missing.",
    save_capture_failed = "Save pass reported failure.",
    save_capture_threw = "Save pass threw an exception.",
    living_ids_changed = "Roster changed size across the save pass.",
    persistence_modules_unavailable = "Persistence/bridge missing.",
    required_module_missing = "A required Lua module is missing.",
    java_bridge_missing = "Java bridge not loaded.",
    java_bridge_ping_failed = "Java bridge would not answer.",
    player_not_ready = "Player or square not ready yet.",
    unknown_step_kind = "Coordinator met an unknown step type.",
    traversal_timeout = "Traversal cases never finished.",
    traversal_status_missing = "Traversal probe gave no status.",
    one_or_more_cases_failed = "At least one traversal case failed.",
    no_obstacle_fixture_tested = "No obstacle fixture could be built.",
    spawn_failed = "Fixture spawn failed.",
    movement_request = "Movement request rejected.",
    controller_tick = "Controller tick threw.",
    combat_controller = "Combat controller fixture failed.",
    post_combat_save_failed = "Post-combat save failed.",
    loot_approach_failed = "No reachable container: locked doors/windows blocked every candidate.",
    transfer_action_ended_without_item = "Transfer action ended but the item never arrived.",
    transfer_without_timed_action = "Item moved without a timed action owning it.",
    no_world_container = "No lootable container within scan radius.",
    test_item_creation_failed = "Engine refused to create the test item.",
    health_reload_prerequisite_missing = "Needs the injury half first; reruns after a health PASS.",
    task_not_claimable = "Resident could not claim the queued task.",
    native_work_state_timeout = "Worker never entered the work state.",
    no_faction_home_fixture = "Faction never scouted a home base in time.",
    combat_controller = "Native combat driver failed the fixture.",
}

function DebugLog.brief(reason)
    local code = tostring(reason or "unknown")
    -- Suffixes like ":details" still match the base code.
    local base = string.match(code, "^([a-z_0-9]+)") or code
    return BRIEFS[code] or BRIEFS[base] or code
end

return DebugLog
