local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local key = "KnoxSurvivors_IsoPlayer"
local modData = {
    [key] = {
        -- Reproduce a save that was already stamped by an earlier schema-7
        -- development build before its membership migration had run.
        schemaVersion = 7,
        survivors = {
            a = { id = "a", record = "record-a" },
            b = { id = "b", record = "record-b" },
            c = { id = "c", record = "record-c" },
        },
        relationships = {},
        travelGroups = {
            legacy = {
                id = "legacy",
                leaderId = "a",
                memberIds = { "a", "b", "c" },
                factionId = "legacy-faction",
            },
        },
        nextTravelGroupId = 2,
        factions = {
            ["legacy-faction"] = {
                id = "legacy-faction",
                leaderId = "a",
                memberIds = { "a", "b" },
            },
        },
        nextFactionId = 2,
    },
}

ModData = {
    getOrCreate = function(name)
        modData[name] = modData[name] or {}
        return modData[name]
    end,
}
Events = {
    OnSave = { Add = function() end },
    OnPostSave = { Add = function() end },
    OnGameStart = { Add = function() end },
}
getGameTime = function()
    return { getWorldAgeHours = function() return 24 end }
end

require "KS_Persistence"

local migrated = KnoxPersistence.getFaction("legacy-faction")
assert(migrated.kind == "npc", "legacy faction kind migration")
assert(#migrated.memberIds == 3, "travel-group member merged into faction")
assert(KnoxPersistence.getSurvivorAffiliation("c").factionId == migrated.id,
    "legacy survivor affiliation migration")
assert(not KnoxPersistence.isIndependentSurvivor("c"), "faction member is not independent")

local playerModData = {}
local player = {
    getModData = function() return playerModData end,
    getDescriptor = function()
        return {
            getForename = function() return "Test" end,
            getSurname = function() return "Player" end,
        }
    end,
}
local playerId = assert(KnoxPersistence.ensurePlayerId(player))

local ghostRecruit, ghostRecruitResult = KnoxPersistence.setPlayerCompanion(
    "ghost",
    playerId,
    "follow",
    24
)
assert(not ghostRecruit and ghostRecruitResult == "survivor_not_persisted")

assert(KnoxPersistence.setRecord("independent", "record-independent"))
KnoxPersistence.ensureSurvivorIdentity("independent", "June", "Reed", 24)
assert(KnoxPersistence.setSurvivorLifeIntent("independent", {
    kind = "find_food", phase = "traveling", targetKey = "building:12",
    targetX = 100, targetY = 120, targetZ = 0,
}, 24), "autonomous life intent persists")
local lifeIntent = assert(KnoxPersistence.getSurvivorLifeIntent("independent"))
assert(lifeIntent.kind == "find_food" and lifeIntent.phase == "traveling"
        and lifeIntent.targetX == 100,
    "life intent round trips without runtime action ownership")
assert(not KnoxPersistence.setSurvivorLifeIntent("independent", {
    kind = "invented_plan", phase = "traveling",
}, 24), "unknown life intent is rejected")
local relation = KnoxPersistence.getPlayerRelationship(playerId, "independent")
relation.trust = 60
local refusal = assert(KnoxPersistence.recordPlayerRecruitRefusal(
    playerId, "independent", 24, 0.5
))
assert(refusal.nextRecruitHours == 24.5, "recruitment refusal keeps a bounded cooldown")
assert(KnoxPersistence.getPlayerRelationship(playerId, "independent").nextRecruitHours == 24.5,
    "recruitment refusal persists in the existing player relationship")
refusal.nextRecruitHours = 0
local recruited, recruitResult = KnoxPersistence.setPlayerCompanion(
    "independent",
    playerId,
    "follow",
    24
)
assert(recruited and recruitResult == "companion", tostring(recruitResult))
assert(KnoxPersistence.setCompanionFormation("independent", playerId, "single_file", 3, 24))
assert(KnoxPersistence.getSurvivorDuty("independent").followerFormation == "single_file"
    and KnoxPersistence.getSurvivorDuty("independent").followerSpacing == 3)
assert(not KnoxPersistence.setCompanionFormation("independent", "other-owner", "paired", 1, 24))
assert(not KnoxPersistence.setCompanionFormation("independent", playerId, "unknown", 1, 24))
assert(not KnoxPersistence.setCompanionFormation("independent", playerId, "paired", 99, 24))
assert(KnoxPersistence.getSurvivorLifeIntent("independent") == nil,
    "companion duty clears incompatible autonomous intent")
assert(KnoxPersistence.getSurvivorDuty("independent").mode == "companion")
assert(KnoxPersistence.getSurvivorDuty("independent").combatStance == "defensive",
    "new companions receive a defensive stance")
assert(KnoxPersistence.setCompanionCombatStance(
    "independent", playerId, "passive", 24
), "companion combat stance persists")
assert(KnoxPersistence.getSurvivorDuty("independent").combatStance == "passive")
assert(not KnoxPersistence.setCompanionCombatStance(
    "independent", playerId, "reckless", 24
), "unknown combat stance rejected")
assert(KnoxPersistence.setCompanionCombatStance(
    "independent", playerId, "defensive", 24
), "companion stance can return to defensive")
assert(#KnoxPersistence.getCompanionIds(playerId) == 1)
modData[key].travelGroups.stalePlayerGroup = {
    id = "stalePlayerGroup",
    leaderId = "independent",
    memberIds = { "independent", "ghost-member" },
}
assert(KnoxPersistence.setPlayerCompanion("independent", playerId, "follow", 24),
    "reapplying player ownership repairs stale NPC-group membership")
assert(KnoxPersistence.getTravelGroupFor("independent") == nil)
assert(KnoxPersistence.setCompanionClimbing("independent", playerId, false, 24))
assert(KnoxPersistence.getSurvivorPolicies("independent").allowClimbing == false)
assert(KnoxPersistence.setCompanionDirective("independent", playerId, {
    kind = "loot_area", minX = 1, minY = 2, maxX = 8, maxY = 9, z = 0,
}, 24))
assert(KnoxPersistence.getSurvivorDuty("independent").directive.kind == "loot_area")
assert(KnoxPersistence.clearCompanionDirective("independent", playerId, 24))
assert(KnoxPersistence.getSurvivorDuty("independent").directive == nil)
assert(KnoxPersistence.setCompanionDirective("independent", playerId, {
    kind = "go_to", minX = 12, minY = 34, z = 0,
}, 24), "go-to directive persists")
local goTo = KnoxPersistence.getSurvivorDuty("independent").directive
assert(goTo.kind == "go_to" and goTo.minX == 12 and goTo.maxX == 12
    and goTo.minY == 34 and goTo.maxY == 34, "go-to target is normalized")
assert(KnoxPersistence.setCompanionDirective("independent", playerId, {
    kind = "guard", minX = 18, minY = 27, maxX = 18, maxY = 27, z = 0,
}, 24), "guard directive persists")
assert(KnoxPersistence.getSurvivorDuty("independent").directive.kind == "guard")
assert(not KnoxPersistence.setCompanionDirective("independent", playerId, {
    kind = "unsupported", minX = 1, minY = 1, z = 0,
}, 24), "unknown directives are rejected")
assert(KnoxPersistence.clearCompanionDirective("independent", playerId, 24))

local base, baseResult = KnoxPersistence.createBase("player", playerId, {
    buildingId = "player-home",
    x = 10,
    y = 20,
    z = 0,
    minX = 8,
    minY = 18,
    width = 8,
    height = 9,
}, 24)
assert(base ~= nil and baseResult == "created", tostring(baseResult))
local territory, territoryResult = KnoxPersistence.updateBaseTerritory(base.id, {
    minX = 4, minY = 14, maxX = 20, maxY = 30,
}, 24)
assert(territory ~= nil and territoryResult == "updated")
assert(territory.allFloors and territory.minX == 4 and territory.maxY == 30)
local resident, residentResult = KnoxPersistence.setPlayerBaseResident(
    "independent",
    playerId,
    base.id,
    24
)
assert(resident and residentResult == "base_resident", tostring(residentResult))
assert(KnoxPersistence.setPlayerCompanion("independent", playerId, "follow", 24))
assert(KnoxPersistence.setCompanionFormation("independent", playerId, "single_file", 3, 24))
assert(KnoxPersistence.setPlayerBaseResident("independent", playerId, base.id, 24))
assert(KnoxPersistence.getSurvivorDuty("independent").followerSpacing == 3,
    "sending home retains formation preferences")
assert(KnoxPersistence.setPlayerCompanion("independent", playerId, "follow", 24))
local recalledDuty = KnoxPersistence.getSurvivorDuty("independent")
assert(recalledDuty.followerFormation == "single_file" and recalledDuty.followerSpacing == 3,
    "recalling a resident restores the selected formation")
assert(KnoxPersistence.setPlayerBaseResident("independent", playerId, base.id, 24))
assert(#KnoxPersistence.getCompanionIds(playerId) == 0)
assert(#KnoxPersistence.getBaseResidentIds(base.id) == 1)
assert(KnoxPersistence.setBaseJobPreference(
    "independent", playerId, base.id, "farming", 24
), "base resident preference persists")
assert(KnoxPersistence.getSurvivorDuty("independent").jobPreference == "farming")
assert(not KnoxPersistence.setBaseJobPreference(
    "independent", playerId, base.id, "not-a-job", 24
), "unknown preference rejected")
assert(KnoxPersistence.setBaseSupplyOrder(
    "independent", playerId, base.id, "find_tools", 24, 12
), "player can assign a bounded supply run to their base resident")
local supplyDuty = KnoxPersistence.getSurvivorDuty("independent")
assert(supplyDuty.baseSupplyOrder.kind == "find_tools"
    and supplyDuty.baseSupplyOrder.expiresAtHours == 36
    and supplyDuty.baseSupplyOrder.attempts == 0,
    "base supply order round trips through the resident duty")
assert(KnoxPersistence.recordBaseSupplyOrderAttempt(
    "independent", base.id, 24.5
) == 1, "base supply retry count persists")
assert(KnoxPersistence.getSurvivorDuty("independent").baseSupplyOrder.attempts == 1,
    "base supply retry count survives controller reconstruction")
assert(KnoxPersistence.beginBaseSupplyRun(
    "independent", base.id, "find_tools", 24.75
), "loaded supply work receives one durable in-flight owner")
local activeSupplyDuty = KnoxPersistence.getSurvivorDuty("independent")
assert(activeSupplyDuty.activeSupplyRun.kind == "find_tools"
    and activeSupplyDuty.lastSupplyOutcome == "started",
    "active supply run and rotation history persist together")
local activeOrderedSupplyStatus = assert(KnoxPersistence.getBaseResidentWorkStatus(
    "independent", base.id
))
assert(activeOrderedSupplyStatus.state == "supply_run"
    and activeOrderedSupplyStatus.taskType == "find_tools",
    "an in-flight supply run must outrank its retained explicit request in the roster")
assert(KnoxPersistence.finishBaseSupplyRun(
    "independent", base.id, "find_tools", "collected", 25
), "supply completion releases its durable in-flight owner")
local completedSupplyDuty = KnoxPersistence.getSurvivorDuty("independent")
assert(completedSupplyDuty.activeSupplyRun == nil
    and completedSupplyDuty.lastSupplyKind == "find_tools"
    and completedSupplyDuty.lastSupplyOutcome == "collected"
    and completedSupplyDuty.lastSupplyRunAtHours == 25,
    "completion history supports fair selection after reconstruction")
local supplyStatus = assert(KnoxPersistence.getBaseResidentWorkStatus(
    "independent", base.id
))
assert(supplyStatus.state == "supply_order"
    and supplyStatus.taskType == "find_tools" and supplyStatus.attempts == 1,
    "base roster exposes the active supply run instead of reporting idle")
assert(KnoxPersistence.setSurvivorLifeIntent("independent", {
    kind = "find_tools", phase = "traveling", targetKey = "container:tools",
    targetX = 12, targetY = 22, targetZ = 0,
}, 24), "base resident supply-search intent persists")
assert(KnoxPersistence.setSurvivorLifeIntent("independent", {
    kind = "base_supply_deposit", phase = "returning", targetKey = "Base.Hammer",
}, 25), "base resident return/deposit handoff persists")
local depositIntent = assert(KnoxPersistence.getSurvivorLifeIntent("independent"))
assert(depositIntent.kind == "base_supply_deposit"
    and depositIntent.phase == "returning",
    "base supply return survives the persistence boundary")
assert(KnoxPersistence.beginBaseSupplyRun(
    "independent", base.id, "find_tools", 25
), "replacement-order cancellation fixture starts an active run")
assert(KnoxPersistence.clearBaseSupplyOrder(
    "independent", playerId, base.id, 25
), "completed base supply order clears through ownership validation")
local clearedSupplyDuty = KnoxPersistence.getSurvivorDuty("independent")
assert(clearedSupplyDuty.baseSupplyOrder == nil
    and clearedSupplyDuty.activeSupplyRun == nil,
    "cleared base supply order cannot restart an in-flight search")
assert(KnoxPersistence.beginBaseSupplyRun(
    "independent", base.id, "find_food", 25.25
), "automatic supply runs use the same durable ownership boundary")
local automaticSupplyStatus = assert(KnoxPersistence.getBaseResidentWorkStatus(
    "independent", base.id
))
assert(automaticSupplyStatus.state == "supply_run"
    and automaticSupplyStatus.taskType == "find_food",
    "automatic supply work is visible to the resident roster")
assert(KnoxPersistence.finishBaseSupplyRun(
    "independent", base.id, "find_food", "empty", 25.5
), "automatic supply ownership releases after an empty search")

local zone = assert(KnoxPersistence.addBaseZone(base.id, "guard", {
    x1 = 9, y1 = 19, x2 = 12, y2 = 22, z = 0,
}, "Front gate"))
assert(zone.type == "guard" and base.zones[zone.id] == zone)
local queuedZoneTask = assert(KnoxPersistence.queueBaseTask(base.id, "guard", {
    autoZoneId = zone.id, x1 = 9, y1 = 19, x2 = 12, y2 = 22, z = 0,
}, {}, 50))
assert(KnoxPersistence.removeBaseZone(base.id, zone.id))
assert(base.zones[zone.id] == nil and base.tasks[queuedZoneTask.id] == nil,
    "removing an inactive zone clears its queued work")
local activeZone = assert(KnoxPersistence.addBaseZone(base.id, "guard", {
    x1 = 9, y1 = 19, x2 = 12, y2 = 22, z = 0,
}, "Active gate"))
local activeTask = assert(KnoxPersistence.queueBaseTask(base.id, "guard", {
    autoZoneId = activeZone.id, x1 = 9, y1 = 19, x2 = 12, y2 = 22, z = 0,
}, {}, 50))
assert(KnoxPersistence.claimBaseTask(base.id, activeTask.id, "independent", 24))
local loadedTaskStatus = assert(KnoxPersistence.getBaseResidentWorkStatus(
    "independent", base.id
))
assert(loadedTaskStatus.state == "claimed" and loadedTaskStatus.offscreen == false,
    "a fresh loaded task claim must not be presented as off-screen work")
activeTask.offscreenWorkHours = 2
local offscreenTaskStatus = assert(KnoxPersistence.getBaseResidentWorkStatus(
    "independent", base.id
))
assert(offscreenTaskStatus.offscreen == true
    and offscreenTaskStatus.offscreenHours == 2,
    "actual off-screen work time must remain visible to the resident roster")
local removedActive, activeReason = KnoxPersistence.removeBaseZone(base.id, activeZone.id)
assert(not removedActive and activeReason == "zone_has_active_task"
    and base.zones[activeZone.id] ~= nil, "active work areas are protected")
assert(KnoxPersistence.requeueBaseTasksForSurvivor(
    "independent", base.id, "test_release"
) == 1, "test claimant must release its active task before claiming another")

local policy = assert(KnoxPersistence.setBaseStoragePolicy(base.id, {
    key = "container-stable-1",
    x = 10,
    y = 20,
    z = 0,
    objectIndex = 2,
    containerIndex = 1,
    containerType = "crate",
}, "depot", true))
assert(policy.containerIndex == 1 and policy.category == "depot"
    and base.toolCupboardKey == "container-stable-1")
local rejectedStorage, rejectedStorageReason = KnoxPersistence.setBaseStoragePolicy(base.id, {
    key = "container-stable-2", x = 11, y = 20, z = 0,
    objectIndex = 3, containerIndex = 0, containerType = "crate",
}, "food", false)
assert(rejectedStorage == nil and rejectedStorageReason == "central_cupboard_only"
    and base.storage["container-stable-1"] ~= nil,
    "retired category storage cannot be recreated through persistence")

local firstTask = assert(KnoxPersistence.queueBaseTask(base.id, "chop_tree", {
    x = 30, y = 40, z = 0,
}, { skills = { Woodwork = 2 } }, 70))
local secondTask = assert(KnoxPersistence.queueBaseTask(base.id, "chop_tree", {
    x = 31, y = 40, z = 0,
}, { skills = { Woodwork = 2 } }, 70))
assert(firstTask.id ~= secondTask.id, "coordinate targets must not collapse")
local ghost, ghostResult = KnoxPersistence.claimBaseTask(
    base.id,
    firstTask.id,
    "not-a-survivor",
    24
)
assert(ghost == nil and ghostResult == "unknown_survivor")
assert(KnoxPersistence.setRecord("outsider", "record-outsider"))
local outsider, outsiderResult = KnoxPersistence.claimBaseTask(
    base.id,
    firstTask.id,
    "outsider",
    24
)
assert(outsider == nil and outsiderResult == "not_base_resident")
local unclaimedFinish, unclaimedFinishResult = KnoxPersistence.finishBaseTask(
    base.id,
    secondTask.id,
    "independent",
    true,
    "invalid",
    24
)
assert(unclaimedFinish == nil and unclaimedFinishResult == "not_claimed_by_survivor")
assert(KnoxPersistence.claimBaseTask(base.id, firstTask.id, "independent", 24))
local duplicateClaim, duplicateReason = KnoxPersistence.claimBaseTask(
    base.id, secondTask.id, "independent", 24
)
assert(duplicateClaim == nil and duplicateReason == "already_claimed_task",
    "one resident cannot own two active base tasks")
assert(KnoxPersistence.requeueBaseTasksForSurvivor(
    "independent", base.id, "test_release_again"
) == 1)
local claimed, claimResult = KnoxPersistence.claimBaseTask(
    base.id,
    firstTask.id,
    "independent",
    24
)
assert(claimed ~= nil and claimResult == "claimed")

assert(KnoxPersistence.setSurvivorIndependent("independent", "dismissed", 25))
assert(firstTask.state == "queued" and firstTask.claimedBy == nil,
    "leaving a base must release claimed work")
assert(KnoxPersistence.isIndependentSurvivor("independent"))
assert(KnoxPersistence.getFactionForSurvivor("independent") == nil)
assert(KnoxPersistence.getTravelGroupFor("independent") == nil)

for _, id in ipairs({ "x", "y", "z", "resident-two" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
end
local npcGroup = assert(KnoxPersistence.createTravelGroup({ "x", "y", "z" }, 25))
for _, id in ipairs({ "y", "z" }) do
    KnoxPersistence.recordEncounter("x", id, {
        worldAgeHours = 25,
        began = true,
        sharedRoam = 1,
    })
end
local npcFaction = assert(KnoxPersistence.evaluateTravelGroupFaction(npcGroup.id, 25))
assert(KnoxPersistence.setPlayerCompanion("resident-two", playerId, "follow", 25))
assert(KnoxPersistence.setPlayerBaseResident("resident-two", playerId, base.id, 25))
local transferredTask = assert(KnoxPersistence.queueBaseTask(base.id, "guard", {
    x = 14, y = 20, z = 0,
}, {}, 50))
assert(KnoxPersistence.claimBaseTask(base.id, transferredTask.id, "resident-two", 25))
assert(not KnoxPersistence.addFactionMember(npcFaction.id, "resident-two", 25))
local transferredDuty = KnoxPersistence.getSurvivorDuty("resident-two")
local transferredAffiliation = KnoxPersistence.getSurvivorAffiliation("resident-two")
assert(transferredAffiliation.kind == "player"
    and transferredAffiliation.ownerId == playerId)
assert(transferredDuty.mode == "base" and transferredDuty.baseId == base.id,
    "NPC factions must not absorb player-owned base residents")
assert(transferredTask.state == "claimed"
    and transferredTask.claimedBy == "resident-two",
    "rejected faction transfer must preserve player-base work")
assert(KnoxPersistence.finishBaseTask(
    base.id,
    transferredTask.id,
    "resident-two",
    true,
    "completed_guard",
    25
))
assert(transferredTask.state == "complete" and transferredTask.retryAtHours == 25.50)
local reopenedTask, reopenedTaskResult = KnoxPersistence.requeueBaseTask(
    base.id,
    transferredTask.id,
    25.50
)
assert(reopenedTask == transferredTask and reopenedTaskResult == "requeued")
assert(transferredTask.state == "queued" and transferredTask.runs == 1,
    "recurring base work should reopen the same persisted task")
local blockedTask = assert(KnoxPersistence.queueBaseTask(base.id, "repair", {
    x = 18, y = 20, z = 0,
}, {}, 50))
assert(KnoxPersistence.claimBaseTask(base.id, blockedTask.id, "resident-two", 25))
assert(KnoxPersistence.finishBaseTask(
    base.id, blockedTask.id, "resident-two", false, "missing_material", 25
))
assert(blockedTask.state == "blocked" and blockedTask.failureStreak == 1
    and blockedTask.retryAtHours == 25.25,
    "blocked work should enter a bounded retry cooldown")
assert(KnoxPersistence.requeueBaseTask(base.id, blockedTask.id, 25) == nil,
    "blocked work must not reopen during its cooldown")
assert(KnoxPersistence.requeueBaseTask(base.id, blockedTask.id, 25.25) == blockedTask,
    "blocked work should reopen after its cooldown")
assert(blockedTask.state == "queued" and blockedTask.runs == 1,
    "blocked work should retain its durable task record")
local retryHour = 25.25
for _ = 1, 6 do
    assert(KnoxPersistence.claimBaseTask(base.id, blockedTask.id, "resident-two", retryHour))
    assert(KnoxPersistence.finishBaseTask(
        base.id, blockedTask.id, "resident-two", false, "still_blocked", retryHour
    ))
    retryHour = blockedTask.retryAtHours
    assert(KnoxPersistence.requeueBaseTask(base.id, blockedTask.id, retryHour) == blockedTask)
end
assert(blockedTask.failureStreak == 6 and blockedTask.retryAtHours == nil,
    "bounded retry sequence should retain its cap after reopening")
assert(KnoxPersistence.claimBaseTask(base.id, blockedTask.id, "resident-two", retryHour))
assert(KnoxPersistence.finishBaseTask(
    base.id, blockedTask.id, "resident-two", true, "recovered", retryHour
))
assert(blockedTask.failureStreak == 0,
    "successful work should reset the persisted failure streak")
local cancelledTask, cancelledResult = KnoxPersistence.cancelBaseTask(
    base.id, transferredTask.id, 26
)
assert(cancelledTask == transferredTask and cancelledResult == "cancelled")
assert(transferredTask.state == "cancelled"
    and KnoxPersistence.requeueBaseTask(base.id, transferredTask.id, 27) == nil,
    "cancelled work remains stopped until a future explicit resume control")
local resumedTask, resumedResult = KnoxPersistence.resumeBaseTask(
    base.id, transferredTask.id, 27
)
assert(resumedTask == transferredTask and resumedResult == "resumed"
    and transferredTask.state == "queued",
    "player-cancelled work resumes on the same durable task record")

local recoveredHigh = assert(KnoxPersistence.queueBaseTask(base.id, "guard", {
    x = 13, y = 20, z = 0,
}, {}, 80))
local recoveredLow = assert(KnoxPersistence.queueBaseTask(base.id, "patrol", {
    x = 14, y = 20, z = 0,
}, {}, 40))
recoveredHigh.state, recoveredHigh.claimedBy, recoveredHigh.claimedAtHours =
    "claimed", "resident-two", 27
recoveredLow.state, recoveredLow.claimedBy, recoveredLow.claimedAtHours =
    "claimed", "resident-two", 27
local recoveredClaim = KnoxPersistence.getClaimedBaseTaskForSurvivor(
    "resident-two", base.id
)
assert(recoveredClaim == recoveredHigh,
    "controller restoration should recover the resident's authoritative claim")
assert(recoveredLow.state == "queued" and recoveredLow.claimedBy == nil
    and recoveredLow.interruptedReason == "duplicate_survivor_claim",
    "duplicate task ownership should be repaired before scheduling")
assert(KnoxPersistence.finishBaseTask(
    base.id, recoveredHigh.id, "resident-two", true, "restored", 27
))

local orphaned = assert(KnoxPersistence.queueBaseTask(base.id, "guard", {
    x = 15, y = 20, z = 0,
}, {}, 35))
orphaned.state, orphaned.claimedBy, orphaned.claimedAtHours =
    "claimed", "missing-resident", 27
KnoxPersistence.getClaimedBaseTaskForSurvivor("resident-two", base.id)
assert(orphaned.state == "queued" and orphaned.claimedBy == nil
    and orphaned.interruptedReason == "claimant_missing",
    "orphaned task claims should return to the queue safely")

local inProgressTask = assert(KnoxPersistence.queueBaseTask(base.id, "patrol", {
    x = 16, y = 20, z = 0,
}, {}, 50))
assert(KnoxPersistence.claimBaseTask(base.id, inProgressTask.id, "resident-two", 27))
inProgressTask.patrolStep = 2
inProgressTask.patrolStopsCompleted = 2
assert(KnoxPersistence.cancelBaseTask(base.id, inProgressTask.id, 27) == nil
    and inProgressTask.state == "claimed",
    "cancelling never interrupts a resident-owned world action")
assert(KnoxPersistence.finishBaseTask(
    base.id, inProgressTask.id, "resident-two", false, "combat_interrupt", 27
))
assert(KnoxPersistence.requeueBaseTask(
    base.id, inProgressTask.id, inProgressTask.retryAtHours
) == inProgressTask)
assert(inProgressTask.patrolStep == 2 and inProgressTask.patrolStopsCompleted == 2,
    "a patrol should resume persisted route progress after interruption")
assert(KnoxPersistence.claimBaseTask(base.id, inProgressTask.id, "resident-two", 28))

local blockedMove, blockedMoveResult = KnoxPersistence.relocateBase(base.id, {
    buildingId = "new-player-home", x = 105, y = 205, z = 0,
    minX = 100, minY = 200, width = 10, height = 8,
}, { minX = 94, minY = 194, maxX = 115, maxY = 213 }, 28)
assert(blockedMove == nil and blockedMoveResult == "task_in_progress",
    "base relocation must not orphan a resident-owned action")
assert(base.home.buildingId == "player-home", "failed relocation leaves the old base intact")
assert(KnoxPersistence.finishBaseTask(base.id, inProgressTask.id, "resident-two", true, "done", 28))
local moved, moveResult = KnoxPersistence.relocateBase(base.id, {
    buildingId = "new-player-home", x = 105, y = 205, z = 0,
    minX = 100, minY = 200, width = 10, height = 8,
}, { minX = 94, minY = 194, maxX = 115, maxY = 213 }, 28)
assert(moved == base and moveResult == "relocated", tostring(moveResult))
assert(base.home.buildingId == "new-player-home"
    and base.territory.minX == 94 and base.territory.maxY == 213,
    "relocation updates home and padded territory transactionally")
assert(next(base.zones) == nil and next(base.storage) == nil and next(base.tasks) == nil,
    "old location metadata is cleared without replacing the base identity")
assert(#KnoxPersistence.getBaseResidentIds(base.id) == 1,
    "resident ownership survives relocation through the stable base ID")

print("Companion/base domain PASS migration=true recruitment=true base=true tasks=true relocation=true")
