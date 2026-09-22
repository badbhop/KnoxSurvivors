local root = arg[1] or "."
require = function() return true end
Events = { OnTick = { Add = function() end, Remove = function() end },
    OnGameStart = { Add = function() end }, OnMainMenuEnter = { Add = function() end },
    OnCreatePlayer = { Add = function() end }, OnPlayerDeath = { Add = function() end } }
getCell = function()
    return { getZombieList = function()
        return { size = function() return 0 end }
    end }
end
getSpecificPlayer = function() return nil end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local function characterWithNeed()
    return {
        getCurrentSquare = function() return { getX = function() return 0 end,
            getY = function() return 0 end, getZ = function() return 0 end,
            getBuilding = function() return nil end } end,
        getCharacterActions = function() return { isEmpty = function() return true end } end,
        getInventory = function() return { getItems = function()
            return { size = function() return 0 end } end } end,
    }
end

-- 1. rest/sleep must not override a direct follow order.
KnoxSurvivorNeeds = { decide = function() return { kind = "sleep", state = {} } end }
local c = setmetatable({ id = "order-test", character = characterWithNeed(),
    companionOrder = "follow", companionDirective = nil, baseId = nil,
    nextThink = 0, currentTicks = 100, nextThreatScan = 99999,
    reservations = { threats = {} }, failedThreats = {},
    selfCareRetryAt = {}, bridge = {}, groupMembers = {},
}, Controller)
-- Stub out everything after the needs gate so we observe the gate itself.
c.beginRecovery = function() error("rest_overrode_order") end
c.beginWorldSearch = function() return false end
c.beginRoam = function() return false end
c.beginGroupSupport = function() return false end
c.beginInventoryCleanup = function() return false end
c.beginEventTravel = function() return false end
local ok, err = pcall(function() c:think(100) end)
assert(not string.find(tostring(err or ""), "rest_overrode_order", 1, true),
    "direct follow order must defer sleep, got: " .. tostring(err))

-- Critical exhaustion is the bounded exception: it starts normal recovery but
-- retains the exact durable order for reconsideration afterward.
KnoxSurvivorNeeds.decide = function()
    return { kind = "rest", state = { endurance = 0.10, fatigue = 0.20 } }
end
local critical = setmetatable({ id = "critical-order-test", character = characterWithNeed(),
    companionOrder = "follow", companionDirective = nil, baseId = nil,
    nextThink = 0, currentTicks = 100, nextThreatScan = 99999,
    reservations = { threats = {} }, failedThreats = {},
    selfCareRetryAt = {}, bridge = {}, groupMembers = {},
}, Controller)
local recoveredKind = nil
critical.beginRecovery = function(_, kind) recoveredKind = kind; return true end
critical:think(100)
assert(recoveredKind == "rest" and critical.companionOrder == "follow",
    "critical recovery must start without clearing the follow order")
assert(Controller.isCriticalOrderedRecovery({ kind = "sleep", state = { fatigue = 0.95 } }),
    "critical fatigue must qualify for ordered recovery")
assert(Controller.isCriticalOrderedRecovery({ kind = "rest",
        state = { endurance = 0.20, fatigue = 0.95 } }),
    "critical fatigue must still qualify when low endurance made rest the selected need")
assert(not Controller.isCriticalOrderedRecovery({ kind = "rest", state = { endurance = 0.20 } }),
    "ordinary tiredness must remain deferred by a direct order")

-- 2. HOLD must survive rest/sleep ticks.
KnoxSurvivorNeeds.decide = function() return { kind = "rest" } end
local h = setmetatable({ id = "hold-test",
    character = { getCurrentSquare = function() return {} end,
        getCharacterActions = function() return { isEmpty = function() return true end } end },
    state = "COMPANION_HOLD", nextThink = 100, nextThreatScan = 99999,
    stateStartedAt = 0, currentTicks = 100,
}, Controller)
h:tick(100)
assert(h.state == "COMPANION_HOLD", "hold must not drop for rest")

KnoxSurvivorNeeds.decide = function()
    return { kind = "rest", state = { endurance = 0.08, fatigue = 0.20 } }
end
h.nextThink = 100
h:tick(100)
assert(h.state == "IDLE" and h.nextThink == 100,
    "critical exhaustion must release hold into recovery planning without clearing its order")

-- 3. Grouped finishDecision must wait a full think interval, not +5.
local f = setmetatable({ id = "think-test", companionOrder = "follow",
    groupMembers = {}, nextThink = 0,
    releaseBaseCooking = function() end, releaseBaseRecreation = function() end,
    releaseGroupSupport = function() end, releaseAmbientMovement = function() end,
}, Controller)
KnoxPersistence = { captureActiveSurvivor = function() end }
ZombRand = function(n) return 0 end
f:finishDecision(1000)
assert(f.nextThink >= 1000 + 30, "grouped rethink must be >= +30, got " .. tostring(f.nextThink))
assert(f.movementFailureCount == nil or f.movementFailureCount == 0,
    "finish must reset movement backoff")

-- 4. Controller-error cleanup is idempotent and continues after one cleanup
-- step itself throws. It removes only this controller's reservation ownership.
local threatKey, itemKey, otherKey = {}, {}, {}
local cancelCalls, resetCalls, taskCleanupCalls = 0, 0, 0
local claimedTask = { id = "task-1", baseId = "base-1", type = "repair",
    state = "claimed", claimedBy = "error-test" }
KnoxBaseTaskBoard = { finish = function() error("task board fixture") end }
local e = setmetatable({ id = "error-test", character = characterWithNeed(),
    companionOrder = "follow", companionDirective = { kind = "guard" },
    state = "COMBAT", activeDecision = "fight", nextThreatScan = 0,
    counts = { failures = 0 }, selfCareRetryAt = {},
    baseTask = claimedTask,
    reservations = {
        threats = { [threatKey] = { ["error-test"] = true, other = true } },
        items = { [itemKey] = "error-test" },
        containers = { [otherKey] = "other" },
    },
    bridge = {
        cancelNpcMove = function() cancelCalls = cancelCalls + 1 end,
        resetNpcCombat = function() resetCalls = resetCalls + 1 end,
    },
}, Controller)
e.cancelTrade = function() end
e.abandonBaseTask = function() taskCleanupCalls = taskCleanupCalls + 1 end
e.leaveRecoveryPosture = function() end
e.releaseRestSpot = function() end
e.releaseCombat = function() end
e.releaseSupply = function() end
e.releaseGroupSupport = function() end
e.releaseAid = function() end
e.releaseAmbientMovement = function() end
e.releaseCampPosition = function() end
e.releaseBaseCooking = function() error("cleanup fixture") end
e.releaseBaseRecreation = function() end
e.releaseBaseHygiene = function() end
e.closeOpenedDoors = function() end
e.resetMovementRecovery = function() end
local recovered, cleanupEvidence = e:recoverFromControllerError(200, "fixture")
assert(not recovered and string.find(cleanupEvidence, "base_cooking=", 1, true),
    "cleanup failures must be reported without aborting later cleanup")
assert(e.state == "IDLE" and e.activeDecision == nil
        and e.companionOrder == "follow" and e.companionDirective.kind == "guard",
    "error recovery must reset transient control and retain durable orders")
assert(e.baseTask == nil and claimedTask.state == "blocked" and claimedTask.claimedBy == nil,
    "fallback cleanup must release a claim even when normal task teardown throws")
assert(e.reservations.items[itemKey] == nil
        and e.reservations.threats[threatKey]["error-test"] == nil
        and e.reservations.threats[threatKey].other == true
        and e.reservations.containers[otherKey] == "other",
    "error recovery must sweep only this controller's leases")
local recoveredAgain = e:recoverFromControllerError(201, "fixture-repeat")
assert(not recoveredAgain and cancelCalls == 2 and resetCalls == 2 and taskCleanupCalls == 2,
    "repeated recovery must remain safe and complete")

-- 5. Migration backup exists.
local fh = assert(io.open(root .. "/mod/42/media/lua/client/KS_Persistence.lua", "r"))
local src = fh:read("*a"); fh:close()
assert(string.find(src, "preMigrationBackup", 1, true), "migration backup missing")
assert(string.find(src, "restorePreMigrationBackup", 1, true), "restore boundary missing")
assert(string.find(src, "typeBeforeMigration", 1, true), "task type backup missing")

-- 6. Any-player helper present in autonomy + probes.
local af = assert(io.open(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua", "r"))
local asrc = af:read("*a"); af:close()
assert(string.find(asrc, "getAnyLoadedPlayer", 1, true), "any-player helper missing")
assert(not string.find(asrc, "local player = getSpecificPlayer(0)", 1, true),
    "player-0 hard requirement remains in autonomy update")

print("AI priority + anti-flap + migration + any-player PASS orders=true criticalRecovery=true hold=true think30=true backup=true anyplayer=true")
