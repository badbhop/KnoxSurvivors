local root = arg[1] or "."
local notebookFile = assert(io.open(root .. "/mod/42/media/lua/client/KS_SurvivorNotebook.lua", "r"))
local notebook = notebookFile:read("*a")
notebookFile:close()
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path
package.loaded["KS_Persistence"] = true
package.loaded["KS_BaseManager"] = true
require "KS_OrderCatalog"

local claimed
local persistedBase = { ownerKind = "player", ownerId = "player-1", tasks = {} }
KnoxBaseManager = {
    canPerformTask = function() return true end,
}
KnoxPersistence = {
    getBase = function() return persistedBase end,
    getSurvivorAffiliation = function(id)
        if id == "survivor-1" then
            return { kind = "player", ownerId = "player-1" }
        end
        return { kind = "faction", factionId = "faction-1" }
    end,
    claimBaseTask = function(_, id, survivorId)
        claimed = { id = id, survivorId = survivorId }
        return { id = id, state = "claimed", claimedBy = survivorId }, "claimed"
    end,
}
getGameTime = function()
    return { getWorldAgeHours = function() return 24 end }
end

local board = dofile(root .. "/mod/42/media/lua/client/KS_BaseTaskBoard.lua")
local queued = {
    { id = "farm", type = "farm_seed", state = "queued", priority = 20 },
    { id = "guard", type = "guard", state = "queued", priority = 10 },
}
board.queued = function() return queued end
local result = board.claimBest("base-1", "survivor-1", "guard")
assert(result ~= nil and claimed ~= nil and claimed.id == "guard",
    "preference should select the matching task")
claimed = nil
result = board.claimBest("base-1", "survivor-1", "repair")
assert(result ~= nil and claimed ~= nil and claimed.id == "farm",
    "preference should fall back when no matching task exists")
local persistenceFile = assert(io.open(root .. "/mod/42/media/lua/client/KS_Persistence.lua", "r"))
local persistenceText = persistenceFile:read("*a")
persistenceFile:close()
assert(string.find(persistenceText, "already_claimed_task", 1, true),
    "persistent task claims must enforce one active task per resident")
assert(string.find(persistenceText, "task.manual = nil", 1, true)
    and string.find(persistenceText, "task.auto = nil", 1, true),
    "released resident claims must not retain manual or automatic ownership markers")
assert(string.find(persistenceText, "task.lastClaimedBy = task.claimedBy", 1, true)
    and string.find(persistenceText, "task.claimedBy = nil", 1, true),
    "completed task claims must release ownership while preserving fairness history")
assert(string.find(persistenceText, "animal_care_requires_concrete_action", 1, true)
    and string.find(persistenceText, "task.target.action", 1, true)
    and string.find(persistenceText, 'task.state = "cancelled"', 1, true),
    "legacy generic animal-care tasks must be migrated to a concrete action or retired")
assert(string.find(persistenceText, "getBaseResidentWorkStatus", 1, true)
    and string.find(persistenceText, "offscreenHours", 1, true),
    "resident work status must expose persisted loaded and off-screen duty")
assert(string.find(persistenceText, "survivor.duty.lastJobType", 1, true)
    and string.find(persistenceText, "survivor.duty.lastJobAtHours", 1, true),
    "persistent task claims should record the resident's last job rotation hint")
assert(string.find(persistenceText, "task.offscreenWaitHours = 0", 1, true),
    "a newly claimed task must receive a fresh off-screen execution lease")
assert(string.find(persistenceText, "function KnoxPersistence.reconcileBaseTaskClaims", 1, true)
    and string.find(persistenceText, "claimant_not_available", 1, true)
    and string.find(persistenceText, "duplicate_resident_claim", 1, true),
    "task persistence must reconcile stale and duplicate resident claims")
assert(string.find(persistenceText, "function KnoxPersistence.reconcileAllBaseTaskClaims", 1, true),
    "task persistence must expose a whole-settlement reconciliation boundary")
local boardFile = assert(io.open(root .. "/mod/42/media/lua/client/KS_BaseTaskBoard.lua", "r"))
local boardText = boardFile:read("*a")
boardFile:close()
local serviceFile = assert(io.open(root .. "/mod/42/media/lua/client/KS_CompanionService.lua", "r"))
local serviceText = serviceFile:read("*a")
serviceFile:close()
local controllerFile = assert(io.open(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r"))
local controllerText = controllerFile:read("*a")
controllerFile:close()
assert(string.find(boardText, "KnoxBaseJobs", 1, true)
    and string.find(boardText, "selectEligibleTask", 1, true),
    "task board should defer to the canonical settlement selector when loaded")
assert(string.find(boardText, "normalizeTaskType", 1, true),
    "queued settlement work should normalize legacy task names")
assert(string.find(persistenceText, "taskType = canonicalTaskType(taskType)", 1, true),
    "persistence must normalize task names for direct callers too")
assert(string.find(boardText, "function TaskBoard.claimSpecific", 1, true)
    and string.find(boardText, "not_your_base", 1, true)
    and string.find(boardText, "not_eligible", 1, true),
    "player-directed task assignment must use the guarded task-board boundary")
assert(string.find(boardText, "assigned.manual = true", 1, true),
    "explicit task assignment must remain distinguishable from automatic work")
local claimCallAt = string.find(boardText, "local assigned, result = KnoxPersistence.claimBaseTask", 1, true)
local manualMarkAt = string.find(boardText, "assigned.manual = true", 1, true)
assert(claimCallAt ~= nil and manualMarkAt ~= nil and manualMarkAt > claimCallAt,
    "manual marker must be written only after the atomic claim succeeds")
assert(string.find(boardText, "KnoxPersistence.claimBaseTask", 1, true),
    "directed assignment must finish through atomic persistence claiming")
persistedBase.tasks.directed = { id = "directed", type = "guard", state = "queued" }
local directed, directedResult = board.claimSpecific(
    "base-1", "directed", "survivor-1", "player-1"
)
assert(directed ~= nil and directedResult == "claimed"
    and claimed ~= nil and claimed.id == "directed",
    "player-directed assignment should claim an eligible queued task atomically")
local denied, deniedResult = board.claimSpecific(
    "base-1", "directed", "survivor-1", "different-player"
)
assert(denied == nil and deniedResult == "not_your_base",
    "directed assignment must reject another player's base")
local foreign, foreignResult = board.claimSpecific(
    "base-1", "directed", "survivor-2", "player-1"
)
assert(foreign == nil and foreignResult == "not_player_resident",
    "directed assignment must reject a non-player resident")
assert(string.find(notebook, '"Assign"', 1, true)
    and string.find(notebook, "residentPicker", 1, true)
    and string.find(notebook, "KnoxCompanionService.assignBaseTask", 1, true),
    "Work tab must expose guarded assignment to a selected base resident")
assert(string.find(notebook, "workStatusFor", 1, true)
    and string.find(notebook, "off-screen", 1, true),
    "Residents tab must distinguish active off-screen duty from idle residents")
assert(string.find(serviceText, "function CompanionService.assignBaseTask", 1, true)
    and string.find(serviceText, "taskBoard.claimSpecific", 1, true),
    "player-facing assignment must enter through the companion service boundary")
local restoredAt = string.find(controllerText, "local restored =", 1, true)
local autoGateAt = string.find(controllerText, "if self.base.settings.automaticJobs == false", 1, true)
assert(restoredAt ~= nil and autoGateAt ~= nil and autoGateAt > restoredAt,
    "automatic-jobs off must still allow an existing assigned task to restore")
assert(string.find(controllerText, "self.baseTask.manual == true", 1, true)
    and string.find(controllerText, "preference == \"rest\" and not", 1, true),
    "Rest must release automatic work without cancelling explicit assignments")
assert(string.find(controllerText, "function canonicalBaseTask", 1, true)
    and string.find(controllerText, "self.baseTask = canonicalBaseTask(restored)", 1, true)
    and string.find(controllerText, "self.baseTask = canonicalBaseTask(task)", 1, true),
    "loaded and newly claimed tasks must cross one canonical controller boundary")
assert(string.find(persistenceText, "canonicalTaskType", 1, true)
    and string.find(persistenceText, "LEGACY_TASK_TYPES", 1, true),
    "persisted settlement tasks should migrate to current executor names")
assert(string.find(persistenceText, "task.offscreenLastHours = task.claimedAtHours", 1, true),
    "claiming a task must reset its off-screen lease timestamp")
print("base task board tests passed")
