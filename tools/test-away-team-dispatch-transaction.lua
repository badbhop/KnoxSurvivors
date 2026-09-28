local root = arg[1] or "."
local originalRequire = require
require = function() return true end
Events = setmetatable({}, { __index = function()
    return { Add = function() end, Remove = function() end }
end })

local now = 42
getGameTime = function() return { getWorldAgeHours = function() return now end } end

local survivors, teams, live, runtimes = {}, {}, {}, {}
local nextTeam, prepareFails, storeFails, removalPlan, finalizeFails = 1, nil, nil, {}, false

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

KnoxSettings = { enabled = function() return true end, developerToolsEnabled = function() return true end }
KnoxSurvivorRuntime = {
    setLifecycleState = function(id, state) runtimes[id] = state return true end,
    unregister = function(id) runtimes[id] = nil return true end,
}
KnoxUnloadedSurvival = {
    prepareBaseResidentForStorage = function() return false, "not_base_resident" end,
    markStored = function(id)
        if storeFails == id then return false, "storage_persistence_failed" end
        survivors[id].ledger.status = "hibernated"
        return true, "stored"
    end,
    rollbackStored = function(id)
        survivors[id].ledger.status = "loaded"
        survivors[id].ledger.activity = "loaded"
        return true, "stored_rollback_loaded"
    end,
}
KnoxPersistence = {
    getPopulationState = function() return {} end,
    getSurvivorAffiliation = function(id) return survivors[id] and survivors[id].affiliation or nil end,
    validateAwayTeam = function(ownerKind, ownerId, ids)
        local seen = {}
        for _, id in ipairs(ids or {}) do
            local survivor = survivors[id]
            if seen[id] or survivor == nil or survivor.dead
                or survivor.affiliation.kind ~= ownerKind
                or survivor.affiliation.factionId ~= ownerId then
                return false, "invalid_member=" .. tostring(id)
            end
            seen[id] = true
        end
        return next(seen) ~= nil, next(seen) ~= nil and "valid" or "no_members"
    end,
    prepareAwayTeam = function(ownerKind, ownerId, ids)
        if prepareFails then return nil, "prepare_failed" end
        local id = "away-" .. tostring(nextTeam)
        nextTeam = nextTeam + 1
        teams[id] = { id = id, state = "dispatching", memberIds = copy(ids), removed = {} }
        for _, member in ipairs(ids) do
            local survivor = survivors[member]
            survivor.previousDuty = copy(survivor.duty)
            survivor.duty = { mode = "away", awayTeamId = id }
        end
        return copy(teams[id]), "created"
    end,
    recordAwayTeamDispatchRemoval = function(teamId, member)
        local team = teams[teamId]
        team.removed[#team.removed + 1] = member
        return true, "recorded"
    end,
    finalizeAwayTeamDispatch = function(teamId)
        local team = teams[teamId]
        if #team.removed ~= #team.memberIds then return nil, "removal_unconfirmed" end
        if finalizeFails then return nil, "finalize_failed" end
        team.state = "outbound"
        return copy(team), "dispatched"
    end,
    abortAwayTeamDispatch = function(teamId)
        local team = teams[teamId]
        team.state = "blocked"
        for _, member in ipairs(team.memberIds) do
            local removed = false
            for _, removedId in ipairs(team.removed) do removed = removed or removedId == member end
            if not removed then
                survivors[member].duty = copy(survivors[member].previousDuty)
            end
        end
        return copy(team), "aborted"
    end,
    recoverBlockedAwayTeamMember = function(teamId, member)
        local team, survivor = teams[teamId], survivors[member]
        if team == nil or team.state ~= "blocked" or survivor == nil
            or survivor.duty.mode ~= "away" or survivor.duty.awayTeamId ~= teamId then
            return false, "blocked_recovery_unavailable"
        end
        survivor.duty = copy(survivor.previousDuty)
        return true, "recovered"
    end,
}
KnoxJavaBridge = {
    getNpcCharacter = function(_, id) return live[id] end,
    removeNpc = function(_, id)
        local result = removalPlan[id] or "REMOVED"
        if result == "REMOVED" then live[id] = nil end
        return result
    end,
}

assert(loadfile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua"))()
require = originalRequire
local autonomy = KnoxSurvivorAutonomy

local function clearRuntime()
    local status = autonomy.status()
    for id in pairs(status.controllers) do status.controllers[id] = nil end
    for index = #status.ids, 1, -1 do table.remove(status.ids, index) end
    survivors, teams, live, runtimes = {}, {}, {}, {}
    nextTeam, prepareFails, storeFails, removalPlan, finalizeFails = 1, nil, nil, {}, false
end

local function add(id, dead)
    survivors[id] = {
        dead = dead == true,
        affiliation = { kind = "faction", factionId = "faction-1" },
        duty = { mode = "autonomous", order = "survive" },
        ledger = { status = "loaded", identity = id, inventory = "real", equipment = "real",
            needs = "real", affiliation = "faction-1" },
    }
    if not dead then
        live[id] = { id = id }
        autonomy.status().controllers[id] = { shutdown = function() return true, "captured" end }
        table.insert(autonomy.status().ids, id)
        runtimes[id] = "active"
    end
end

local player = {}
local destination = { getX = function() return 100 end, getY = function() return 200 end,
    getZ = function() return 0 end }
local function dispatch()
    return autonomy.dispatchDeveloperScout(player, destination)
end
local function active(id)
    return live[id] ~= nil and autonomy.status().controllers[id] ~= nil
        and runtimes[id] == "active" and survivors[id].ledger.status == "loaded"
end
local function removed(id)
    return live[id] == nil and autonomy.status().controllers[id] == nil
        and survivors[id].ledger.status == "hibernated"
end

clearRuntime()
add("a")
add("b")
local ok, teamId = dispatch()
assert(ok and teams[teamId].state == "outbound" and removed("a") and removed("b")
    and survivors.a.duty.mode == "away" and survivors.b.duty.mode == "away",
    "valid multi-survivor dispatch commits one complete ledger before teardown")

clearRuntime()
add("a")
add("b")
storeFails = "b"
ok = dispatch()
assert(not ok and active("a") and active("b") and next(teams) == nil,
    "stored-ledger failure leaves every body and duty active with no team")

clearRuntime()
add("a")
add("b")
prepareFails = true
ok = dispatch()
assert(not ok and active("a") and active("b") and next(teams) == nil,
    "team creation failure rolls every pre-removed ledger back to loaded")

clearRuntime()
add("a")
add("b")
add("b")
ok = dispatch()
assert(not ok and active("a") and active("b") and next(teams) == nil,
    "duplicate active roster input is rejected before mutation")

clearRuntime()
add("a")
add("dead", true)
table.insert(autonomy.status().ids, "dead")
ok = dispatch()
assert(not ok and active("a") and survivors.dead.ledger.status == "loaded" and next(teams) == nil,
    "dead or missing roster members reject dispatch before mutation")

local function partialFailure(label, failedId, expectedRemoved)
    clearRuntime()
    add("a")
    add("b")
    add("c")
    removalPlan[failedId] = "REMOVE_FAILED"
    local dispatched = dispatch()
    assert(not dispatched and teams["away-1"].state == "blocked",
        label .. " removal failure blocks the durable dispatch")
    for _, id in ipairs(expectedRemoved) do
        assert(removed(id) and survivors[id].duty.mode == "away",
            label .. " already-removed member remains hibernated under blocked ownership")
    end
    for _, id in ipairs({ "a", "b", "c" }) do
        local wasRemoved = false
        for _, removedId in ipairs(expectedRemoved) do wasRemoved = wasRemoved or removedId == id end
        if not wasRemoved then
            assert(active(id) and survivors[id].duty.mode == "autonomous",
                label .. " still-live member returns to loaded active ownership")
        end
    end
end
partialFailure("first", "a", {})
partialFailure("middle", "b", { "a" })
partialFailure("final", "c", { "a", "b" })

clearRuntime()
add("a")
add("b")
finalizeFails = true
ok = dispatch()
assert(not ok and teams["away-1"].state == "blocked" and removed("a") and removed("b")
    and survivors.a.duty.mode == "away" and survivors.b.duty.mode == "away",
    "finalization failure keeps every confirmed removal hibernated under one blocked ledger")

clearRuntime()
add("a")
add("b")
removalPlan.b = "REMOVE_FAILED"
ok = dispatch()
assert(not ok and removed("a") and active("b"), "partial dispatch preserves distinct recovery ownership")
-- Simulate the canonical later activation of the one stored identity; no new
-- identity, inventory/equipment/need ledger, order or faction data is created.
live.a = { id = "a" }
autonomy.status().controllers.a = { shutdown = function() return true, "captured" end }
table.insert(autonomy.status().ids, "a")
runtimes.a = "active"
survivors.a.ledger.status = "loaded"
assert(KnoxPersistence.recoverBlockedAwayTeamMember("away-1", "a"),
    "canonical restoration releases only the recovered blocked member's prior duty")
assert(survivors.a.duty.mode == "autonomous" and survivors.b.duty.mode == "autonomous",
    "recovery preserves the live member's earlier rollback without duplicating ownership")
removalPlan = {}
ok, teamId = dispatch()
assert(ok and teams[teamId].state == "outbound" and removed("a") and removed("b")
    and survivors.a.ledger.identity == "a" and survivors.a.ledger.inventory == "real"
    and survivors.a.ledger.equipment == "real" and survivors.a.ledger.needs == "real"
    and survivors.a.ledger.affiliation == "faction-1",
    "retry after recovery creates one new outbound team without duplicate survivor state")

print("Away dispatch transaction PASS validation=true rollback=true partial_recovery=true retry=true identity=true")
