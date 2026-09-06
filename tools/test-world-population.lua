local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path

local modData = {}
ModData = {
    getOrCreate = function(key)
        modData[key] = modData[key] or {}
        return modData[key]
    end,
}
Events = {
    OnSave = { Add = function() end },
    OnGameStart = { Add = function() end },
}
getGameTime = function()
    return { getWorldAgeHours = function() return 10 end }
end

local function point(x, y, z)
    return { posX = x, posY = y, posZ = z or 0 }
end

local spawnRegionCalls = 0
SpawnRegionMgr = {
    getSpawnRegions = function()
        spawnRegionCalls = spawnRegionCalls + 1
        return {
            {
                name = "Alpha",
                points = {
                    unemployed = {
                        point(100, 100), point(101, 100), point(102, 100),
                        point(103, 100), point(104, 100), point(105, 100),
                    },
                    carpenter = { point(100, 100), point(101, 100) },
                },
            },
            {
                name = "Bravo",
                points = {
                    unemployed = {
                        point(200, 200), point(201, 200), point(202, 200),
                        point(203, 200), point(204, 200), point(205, 200),
                    },
                },
            },
            {
                name = "Charlie",
                points = {
                    unemployed = {
                        point(300, 300), point(301, 300), point(302, 300),
                        point(303, 300), point(304, 300), point(305, 300),
                    },
                },
            },
        }
    end,
}
package.preload.SpawnRegions = function()
    return true
end

getWorld = function()
    return { getMap = function() return "Test Map" end }
end

local squareState = {}
local function squareKey(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z or 0)
end

local function makeSquare(x, y, z)
    local state = { standable = true, visible = false, fire = false, occupied = false }
    local square = {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return state.standable end,
        isCanSee = function() return state.visible end,
        isCouldSee = function() return state.visible end,
        haveFire = function() return state.fire end,
        getMovingObjects = function()
            return { size = function() return state.occupied and 1 or 0 end }
        end,
    }
    squareState[squareKey(x, y, z)] = { square = square, state = state }
    return square, state
end

local cell = {
    getGridSquare = function(_, x, y, z)
        local entry = squareState[squareKey(x, y, z)]
        return entry ~= nil and entry.square or nil
    end,
}
getCell = function()
    return cell
end

local playerSquare = makeSquare(0, 0, 0)
local player = {
    getCurrentSquare = function() return playerSquare end,
    getPlayerNum = function() return 0 end,
}
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return player end

SandboxVars = nil
require "KS_Settings"
assert(KnoxSettings.worldPopulation() == 48, "world population balanced default")
assert(KnoxSettings.maxActiveSurvivors() == 16, "active population balanced default")
assert(KnoxSettings.populationRefillDays() == 5, "replacement cadence balanced default")
assert(KnoxSettings.minimumSpawnDistance() == 40, "hidden encounter distance balanced default")

SandboxVars = { KnoxSurvivors = {
    WorldPopulation = 6,
    InitialGroupChance = 100,
    InitialGroupMaxSize = 2,
    MaxActiveSurvivors = 99,
    PopulationRefillDays = 3,
    MinimumSpawnDistance = 2,
} }
assert(KnoxSettings.maxActiveSurvivors() == 48, "active population clamp")
assert(KnoxSettings.minimumSpawnDistance() == 25, "minimum distance clamp")

require "KS_Persistence"
require "KS_WorldPopulation"

local appliedAge = nil
KnoxPersistence.ensureSurvivorIdentity("identity-age-test", "", "", 0)
local identity = KnoxPersistence.ensureSurvivorIdentityFromCharacter(
    "identity-age-test",
    {
        getDescriptor = function()
            return {
                getForename = function() return "Morgan" end,
                getSurname = function() return "Reed" end,
            }
        end,
        getHoursSurvived = function() return 0 end,
        setAge = function(_, age) appliedAge = age end,
    },
    10
)
assert(identity.forename == "Morgan" and identity.surname == "Reed",
    "empty legacy names filled from live descriptor")
assert(identity.ageYears == 18 and appliedAge == 18,
    "stable randomized age replaces the engine default and is applied")
KnoxPersistence.ensureSurvivorIdentity("saved-age-test", "Avery", "Cole", 0, 42)
KnoxPersistence.ensureSurvivorIdentityFromCharacter(
    "saved-age-test",
    {
        getDescriptor = function()
            return {
                getForename = function() return "Changed" end,
                getSurname = function() return "Name" end,
            }
        end,
        getHoursSurvived = function() return 0 end,
        setAge = function(_, age) appliedAge = age end,
    },
    10
)
assert(appliedAge == 42, "saved identity age wins during reconstruction")

local catalog = assert(KnoxWorldPopulation.spawnCatalog())
assert(#catalog.regions == 3, "all spawn regions loaded")
assert(#catalog.origins == 18, "profession duplicates removed")
local scoutOrigin = assert(KnoxWorldPopulation.nearestScoutingOrigin(
    100, 100, 0, "faction-test", "100,100,0"
))
assert(scoutOrigin.key ~= "100,100,0" and scoutOrigin.z == 0,
    "faction scouting chooses a different same-floor real origin")

SandboxVars.KnoxSurvivors.PopulationRefillDays = 0
local firstInitialBatch = KnoxWorldPopulation.maintain(10, {
    players = { player }, initialAllocationBudget = 2,
})
assert(firstInitialBatch.status == "initializing"
    and #firstInitialBatch.addedIds == 2 and firstInitialBatch.living == 2,
    "fresh population initialization yields after its bounded allocation budget")
local secondInitialBatch = KnoxWorldPopulation.maintain(10, {
    players = { player }, initialAllocationBudget = 2,
})
assert(secondInitialBatch.status == "initializing"
    and #secondInitialBatch.addedIds == 2 and secondInitialBatch.living == 4,
    "fresh population initialization resumes on a later maintenance pass")
local initialized = KnoxWorldPopulation.maintain(10, {
    players = { player }, initialAllocationBudget = 2,
})
assert(initialized.status == "initialized", "initial allocation status")
assert(#initialized.addedIds == 2 and initialized.living == 6,
    "initial population reaches target without one unbounded pass")
local initialAddedIds = KnoxPersistence.getLivingWorldSurvivorIds()
assert(#initialAddedIds == 6, "all initial batches retain their durable identities")
assert(KnoxPersistence.getPopulationState().nextRefillHours == 0
    and KnoxWorldPopulation.maintain(10).status == "refill_disabled",
    "disabling refill preserves the full bounded initial population")
SandboxVars.KnoxSurvivors.PopulationRefillDays = 3

local regionCounts = {}
local used = {}
for _, id in ipairs(KnoxPersistence.getAllWorldSurvivorIds()) do
    local origin = assert(KnoxPersistence.getSurvivorOrigin(id))
    regionCounts[origin.region] = (regionCounts[origin.region] or 0) + 1
    assert(not used[origin.key], "origin reused during initial allocation")
    used[origin.key] = true
end
assert(regionCounts.Alpha == 4 and regionCounts.Bravo == 1 and regionCounts.Charlie == 1,
    "initial allocation reserves a bounded cohort in the player's starting region")
local populationState = KnoxPersistence.getPopulationState()
assert(populationState.initialRegionKey == "Alpha#1"
    and populationState.initialRegionTarget == 4,
    "starting-region presence policy is persisted and inspectable")
assert(populationState.initialGroupsCreated and populationState.initialGroupCount == 1,
    "opening population includes one bounded compact pair")
local initialGroup = nil
for _, id in ipairs(initialAddedIds) do
    local group = KnoxPersistence.getTravelGroupFor(id)
    if group ~= nil then initialGroup = group break end
end
assert(initialGroup ~= nil and #initialGroup.memberIds == 2 and initialGroup.originCohort,
    "pre-materialization identities use the canonical persisted travel-group domain")
local firstGroupState = KnoxPersistence.getUnloadedSurvivalState(initialGroup.memberIds[1])
local secondGroupState = KnoxPersistence.getUnloadedSurvivalState(initialGroup.memberIds[2])
local beforeDx = secondGroupState.virtualX - firstGroupState.virtualX
local beforeDy = secondGroupState.virtualY - firstGroupState.virtualY
assert(KnoxWorldPopulation.advanceOriginTravel(initialGroup.leaderId, 20),
    "pre-materialization group advances through one shared itinerary")
firstGroupState = KnoxPersistence.getUnloadedSurvivalState(initialGroup.memberIds[1])
secondGroupState = KnoxPersistence.getUnloadedSurvivalState(initialGroup.memberIds[2])
assert(math.abs((secondGroupState.virtualX - firstGroupState.virtualX) - beforeDx) < 0.001
    and math.abs((secondGroupState.virtualY - firstGroupState.virtualY) - beforeDy) < 0.001,
    "shared origin itinerary preserves compact member offsets")
local soloIds = {}
for _, id in ipairs(initialAddedIds) do
    if KnoxPersistence.getTravelGroupFor(id) == nil then soloIds[#soloIds + 1] = id end
end
assert(#soloIds == 4, "initial mix retains independent survivors")

local deadId = soloIds[1]
local deadOrigin = KnoxPersistence.getSurvivorOrigin(deadId)
assert(KnoxPersistence.markSurvivorDead(deadId, 20, "test"), "death persisted")
local deficitStarted = KnoxWorldPopulation.maintain(20)
assert(deficitStarted.status == "waiting", "population deficit starts refill clock")
local waiting = KnoxWorldPopulation.maintain(91)
assert(waiting.status == "waiting" and #waiting.addedIds == 0,
    "replacement waits for refill interval")
local refilled = KnoxWorldPopulation.maintain(92)
assert(refilled.status == "refilled" and #refilled.addedIds == 1,
    "one replacement allocated when due")
assert(refilled.groupId == nil or type(refilled.groupId) == "string",
    "replacement group linkage remains optional and persisted")
assert(KnoxPersistence.getSurvivorOrigin(refilled.addedIds[1]).key ~= deadOrigin.key,
    "dead survivor origin is never reused")
assert(spawnRegionCalls == 1, "spawn definitions cached between maintenance passes")

local spawnId = soloIds[2]
local spawnOrigin = assert(KnoxPersistence.getSurvivorOrigin(spawnId))
for x = spawnOrigin.x - 4, spawnOrigin.x + 4 do
    for y = spawnOrigin.y - 4, spawnOrigin.y + 4 do
        makeSquare(x, y, spawnOrigin.z)
    end
end
squareState[spawnOrigin.key].state.standable = false
playerSquare = makeSquare(spawnOrigin.x + 100, spawnOrigin.y, spawnOrigin.z)
local spawnCandidate = assert(KnoxWorldPopulation.activationCandidate(
    spawnId,
    {},
    { players = { player }, minimumDistance = 25, maximumDistance = 150 }
))
assert(spawnCandidate.mode == "spawn" and spawnCandidate.firstMaterialization,
    "new survivor gets first-materialization candidate")
assert(spawnCandidate.square ~= squareState[spawnOrigin.key].square,
    "unsafe origin uses nearby standable square")

for x = spawnOrigin.x - 4, spawnOrigin.x + 4 do
    for y = spawnOrigin.y - 4, spawnOrigin.y + 4 do
        squareState[squareKey(x, y, spawnOrigin.z)].state.visible = true
    end
end
local hiddenCandidate, hiddenReason = KnoxWorldPopulation.activationCandidate(
    spawnId,
    {},
    { players = { player }, minimumDistance = 25, maximumDistance = 150 }
)
assert(hiddenCandidate == nil and hiddenReason == "no_safe_hidden_loaded_square",
    "first materialization never occurs in player sight")

local restoreId = soloIds[3]
assert(KnoxPersistence.setRecord(restoreId, "saved-record"), "record stored")
local exactSquare, exactState = makeSquare(400, 500, 0)
exactState.visible = true
playerSquare = exactSquare
local bridge = {
    getTestNpcRecordX = function() return 400 end,
    getTestNpcRecordY = function() return 500 end,
    getTestNpcRecordZ = function() return 0 end,
}
local restoreCandidate = assert(KnoxWorldPopulation.activationCandidate(
    restoreId,
    bridge,
    { players = { player }, minimumDistance = 150, maximumDistance = 150 }
))
assert(restoreCandidate.mode == "restore" and restoreCandidate.exact,
    "saved survivor uses restore mode")
assert(restoreCandidate.square == exactSquare,
    "restoration preserves exact saved square despite visibility and minimum distance")

local virtualId = "virtual-traveller"
assert(KnoxPersistence.setRecord(virtualId, "virtual-record"),
    "virtual traveller record stored")
KnoxPersistence.setUnloadedSurvivalState(virtualId, {
    status = "hibernated", activity = "surviving",
    virtualX = 450, virtualY = 500, virtualZ = 0,
})
local virtualSquare = makeSquare(450, 500, 0)
local relocatedRecord = nil
bridge.relocateNpcRecord = function(_, record, x, y, z)
    relocatedRecord = record .. "@" .. x .. "," .. y .. "," .. z
    return relocatedRecord
end
local virtualCandidate = assert(KnoxWorldPopulation.activationCandidate(
    virtualId,
    bridge,
    { players = { player }, maximumDistance = 150 }
))
assert(virtualCandidate.mode == "restore" and virtualCandidate.square == virtualSquare,
    "virtual traveller materializes at its progressed loaded location")
assert(virtualCandidate.record == relocatedRecord
    and KnoxPersistence.getRecord(virtualId) == relocatedRecord,
    "virtual location is transactionally written into the Java survivor record")

local baseVirtualId = "virtual-base-resident"
assert(KnoxPersistence.setRecord(baseVirtualId, "base-virtual-record"),
    "base resident record stored")
KnoxPersistence.setUnloadedSurvivalState(baseVirtualId, {
    status = "hibernated", activity = "base_life",
    virtualX = 475, virtualY = 500, virtualZ = 0,
})
local baseVirtualSquare = makeSquare(475, 500, 0)
local nativeGetDuty = KnoxPersistence.getSurvivorDuty
KnoxPersistence.getSurvivorDuty = function(id)
    if id == baseVirtualId then return { mode = "base", baseId = "base-1" } end
    return nativeGetDuty(id)
end
local baseVirtualCandidate = assert(KnoxWorldPopulation.activationCandidate(
    baseVirtualId,
    bridge,
    { players = { player }, maximumDistance = 150 }
))
assert(baseVirtualCandidate.mode == "restore"
    and baseVirtualCandidate.square == baseVirtualSquare,
    "base life materializes at its progressed loaded location")
assert(KnoxPersistence.getRecord(baseVirtualId) ~= "base-virtual-record",
    "base-life location is transactionally written into the Java survivor record")
KnoxPersistence.getSurvivorDuty = nativeGetDuty

assert(KnoxPersistence.setRecord("ks-dev-1", "developer-record"),
    "developer survivor record stored")
local durableCandidates = KnoxWorldPopulation.activationCandidates(
    bridge,
    {},
    100,
    { players = { player }, maximumDistance = 150 }
)
local developerRestored = false
for _, candidate in ipairs(durableCandidates) do
    assert(candidate.activationPriority ~= nil,
        "activation candidate carries deterministic ownership priority")
    if candidate.id == "ks-dev-1" and candidate.mode == "restore" then
        developerRestored = true
    end
end
assert(developerRestored, "saved non-population survivor is eligible after reload")

squareState[squareKey(400, 500, 0)] = nil
local unloaded, unloadedReason = KnoxWorldPopulation.activationCandidate(
    restoreId,
    bridge,
    { players = { player }, maximumDistance = 150 }
)
assert(unloaded == nil and unloadedReason == "saved_square_not_loaded",
    "saved survivor waits instead of falling back to origin")

SandboxVars.KnoxSurvivors.WorldPopulation = 1
local finiteLiving = #KnoxPersistence.getLivingWorldSurvivorIds()
SandboxVars.KnoxSurvivors.PopulationRefillDays = 0
SandboxVars.KnoxSurvivors.DisableSurvivorCaps = true
local finite = KnoxWorldPopulation.maintain(99)
assert(finite.status == "refill_disabled" and #finite.addedIds == 0
    and finite.nextRefillHours == 0,
    "finite population suppresses uncapped arrivals and clears old deadlines")
SandboxVars.KnoxSurvivors.DisableSurvivorCaps = false
SandboxVars.KnoxSurvivors.WorldPopulation = finiteLiving + 1
assert(KnoxWorldPopulation.maintain(99999).status == "refill_disabled"
    and #KnoxPersistence.getLivingWorldSurvivorIds() == finiteLiving,
    "finite population never replaces losses, even after a large time skip")
SandboxVars.KnoxSurvivors.PopulationRefillDays = 3
local resumed = KnoxWorldPopulation.maintain(100000)
assert(resumed.status == "waiting" and resumed.nextRefillHours == 100072,
    "re-enabling arrivals starts a full interval with no accumulated catch-up")
assert(#KnoxWorldPopulation.maintain(100071).addedIds == 0,
    "re-enabled replacement waits until the full interval has passed")
SandboxVars.KnoxSurvivors.WorldPopulation = 1
local oldLiving = #KnoxPersistence.getLivingWorldSurvivorIds()
assert(KnoxWorldPopulation.maintain(100).status == "at_target", "configured target still limits ordinary refill")
SandboxVars.KnoxSurvivors.DisableSurvivorCaps = true
assert(KnoxWorldPopulation.maintain(101).status == "waiting", "uncapped arrivals start a clock rather than a burst")
assert(#KnoxWorldPopulation.maintain(172).addedIds == 0, "uncapped arrivals still wait the refill interval")
local uncappedArrival = KnoxWorldPopulation.maintain(173)
assert(#uncappedArrival.addedIds == 1 and uncappedArrival.living == oldLiving + 1,
    "uncapped arrivals may exceed the configured population target")
assert(#KnoxWorldPopulation.maintain(173).addedIds == 0, "same-tick reconciliation cannot create another arrival")
assert(#KnoxWorldPopulation.maintain(100000).addedIds == 1,
    "large time jump creates one arrival, never an accumulated spawning burst")
local preserved = #KnoxPersistence.getLivingWorldSurvivorIds()
SandboxVars.KnoxSurvivors.DisableSurvivorCaps = false
assert(KnoxWorldPopulation.maintain(100001).status == "at_target"
    and #KnoxPersistence.getLivingWorldSurvivorIds() == preserved,
    "re-enabling caps stops arrivals without deleting existing survivors")
SandboxVars.KnoxSurvivors.DisableSurvivorCaps = true
for interval = 1, 25 do
    local result = KnoxWorldPopulation.maintain(100001 + interval * 72)
    assert(#result.addedIds <= 1, "uncapped allocation rate remains bounded")
end
assert(KnoxWorldPopulation.maintain(200000).status == "spawn_origins_exhausted",
    "uncapped population never recycles occupied/dead origins or manufactures infinite sites")
assert(#KnoxPersistence.getAllWorldSurvivorIds() == #catalog.origins,
    "finite world catalog is a spatial resource, not runaway population generation")

print("World population PASS starting_region=true initial_groups=true shared_origin_travel=true map_balance=true refill=one exact_restore=true durable_restore=true hidden_spawn=true virtual_restore=true uncapped=true")
