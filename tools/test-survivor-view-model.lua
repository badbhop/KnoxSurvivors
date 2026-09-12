package.path = "mod/42/media/lua/client/?.lua;" .. package.path

local function stubModule(name)
    package.preload[name] = function()
        return true
    end
end

stubModule("KS_CompanionService")
stubModule("KS_Persistence")
stubModule("KS_SurvivorCapabilities")
stubModule("KS_SurvivorNeeds")
stubModule("KS_SurvivorRuntime")

local identity = {
    forename = "Morgan",
    surname = "Reed",
    ageYears = 31,
    createdAtHours = 28,
}
local affiliation = {
    kind = "player",
    ownerId = "player-1",
    joinedAtHours = 52,
}
local duty = {
    mode = "companion",
    order = "follow",
    ownerId = "player-1",
    directive = { kind = "loot_area" },
}
local liveCharacter = nil

local player = {
    getModData = function()
        return { KnoxSurvivors = { playerId = "player-1" } }
    end,
    getX = function() return 10 end,
    getY = function() return 10 end,
    getZ = function() return 0 end,
}

getSpecificPlayer = function(playerNum)
    return playerNum == 0 and player or nil
end
getGameTime = function()
    return { getWorldAgeHours = function() return 100 end }
end

KnoxPersistence = {
    getSurvivorIdentity = function() return identity end,
    getSurvivorAffiliation = function() return affiliation end,
    getSurvivorDuty = function() return duty end,
    getSurvivorCapabilities = function() return {
        professionId = "park-ranger", traitIds = { "Brave", "Outdoorsman" },
        skills = { Woodwork = { level = 3, xp = 200 } },
    } end,
    getPlayerRelationshipSnapshot = function()
        return { firstMetHours = 52, trust = 61, meetings = 4 }
    end,
    getSurvivorLifeIntent = function()
        return { kind = "find_food", phase = "traveling" }
    end,
    getBase = function() return nil end,
}
KnoxCompanionService = {
    getCompanionIds = function() return { "survivor-1" } end,
}
KnoxSurvivorCapabilities = {
    professionLabel = function() return "Park Ranger" end,
}
KnoxSurvivorNeeds = {
    thresholds = {
        hunger = 0.65,
        thirst = 0.65,
        fatigue = 0.72,
        lowEndurance = 0.25,
    },
    snapshot = function()
        return {
            hunger = 0.8,
            thirst = 0.4,
            fatigue = 0.6,
            endurance = 0.5,
            bleedingParts = 1,
            health = 65,
        }
    end,
}
KnoxSurvivorRuntime = {
    getCharacter = function() return liveCharacter end,
    snapshot = function()
        return liveCharacter ~= nil and { activity = "looting" } or nil
    end,
}

local viewModel = dofile("mod/42/media/lua/client/KS_SurvivorViewModel.lua")

local away = viewModel.getSurvivor("survivor-1", 0)
assert(away ~= nil)
assert(away.displayName == "Morgan Reed")
assert(away.ageYears == 31)
assert(away.daysSurvived == 3)
assert(away.daysKnown == 2)
assert(away.professionLabel == "Park Ranger")
assert(away.orderLabel == "Looting marked area")
assert(away.locationLabel == "Away")
assert(away.vitals.available == false)
assert(away.vitals.health == nil)
assert(away.health == 1)
assert(away.traits[1] == "Brave" and away.skills.Woodwork.level == 3)
assert(away.trust == 61 and away.relationshipMeetings == 4)
assert(away.lifeIntent ~= nil and away.lifeIntent.label == "Looking for food",
    "stored autonomous purpose is readable in the survivor card model")

liveCharacter = {
    getCurrentSquare = function() return {} end,
    getDescriptor = function()
        return {
            getForename = function() return "Changed" end,
            getSurname = function() return "Name" end,
        }
    end,
    getX = function() return 13 end,
    getY = function() return 14 end,
    getZ = function() return 0 end,
    getAge = function() return 31 end,
    getHoursSurvived = function() return 72 end,
    isDead = function() return false end,
    getPrimaryHandItem = function() return nil end,
    getSecondaryHandItem = function() return nil end,
}

local loaded = viewModel.getSurvivor("survivor-1", 0)
assert(loaded.loaded == true)
assert(loaded.displayName == "Morgan Reed")
assert(loaded.vitals.available == true)
assert(loaded.vitals.health == 0.65)
assert(loaded.vitals.hunger == 0.8)
assert(math.abs(loaded.needs.food - 0.2) < 0.000001)
assert(loaded.locationLabel == "With you - 5 tiles")
assert(loaded.activity == "Looting", "injury must not hide the survivor's actual activity")
assert(loaded.needSummary == 'Bleeding, Food', 'needs stay visible while another activity is active')
local originalNeedsSnapshot = KnoxSurvivorNeeds.snapshot
KnoxSurvivorNeeds.snapshot = function() return {
    health = 65, bleedingParts = 0, hunger = 0, thirst = 0, fatigue = 0, endurance = 1,
} end
assert(viewModel.getSurvivor('survivor-1', 0).needSummary == 'Hurt',
    'non-bleeding injury remains visible alongside activity')
local originalRuntimeSnapshot = KnoxSurvivorRuntime.snapshot
for activity, label in pairs({ fighting = "Fighting", resting = "Resting", following = "Following" }) do
    KnoxSurvivorRuntime.snapshot = function() return {activity = activity} end
    assert(viewModel.getSurvivor('survivor-1', 0).activity == label,
        'injury must not obscure ' .. activity)
end
KnoxSurvivorRuntime.snapshot = originalRuntimeSnapshot
KnoxSurvivorNeeds.snapshot = function() return {
    health = 100, bleedingParts = 0, hunger = 0.8, thirst = 0.8, fatigue = 0.9, endurance = 0.1,
} end
assert(viewModel.getSurvivor('survivor-1', 0).needSummary == 'Water, Food, Catch breath, Sleep / rest')
KnoxSurvivorNeeds.snapshot = function() return {
    health = 100, bleedingParts = 0, hunger = 0, thirst = 0, fatigue = 0, endurance = 1,
} end
assert(viewModel.getSurvivor('survivor-1', 0).needSummary == nil, 'healthy survivor does not show false alarms')
KnoxSurvivorNeeds.snapshot = originalNeedsSnapshot

loaded.affiliation.kind = "changed"
assert(affiliation.kind == "player")
loaded.duty.order = "changed"
assert(duty.order == "follow")

local party = viewModel.getForPlayer(0)
assert(#party == 1)
assert(party[1].id == "survivor-1")

-- Base rows should expose the real claimed task even when the loaded runtime
-- has not published a fresh activity snapshot yet.
duty.mode = "base"
duty.baseId = "base-1"
duty.order = "survive"
KnoxPersistence.getBase = function(id)
    return id == "base-1" and {
        tasks = {
            { type = "farm_seed", state = "claimed", claimedBy = "survivor-1" },
        },
    } or nil
end
local resident = viewModel.getSurvivor("survivor-1", 0)
assert(resident.orderLabel == "Plant Crops",
    "base resident status should project the claimed canonical task")
for kind, label in pairs({ find_water = "Find Water", find_food = "Find Food",
    find_medical = "Find Medical Supplies", find_weapon = "Find Better Weapon", find_tools = "Find Useful Tools" }) do
    duty.baseSupplyOrder = { kind = kind, attempts = 0 }
    assert(viewModel.getSurvivor("survivor-1", 0).orderLabel == label,
        "explicit resident supply order must be visible even before its task is claimed: " .. kind)
end
duty.baseSupplyOrder = nil
assert(viewModel.getSurvivor("survivor-1", 0).orderLabel == "Plant Crops",
    "clearing a supply order restores the claimed base task label")

assert(resident.locationLabel == "Outside Home Base")
KnoxBaseManager = { containsSquare = function() return true end }
assert(viewModel.getSurvivor("survivor-1", 0).locationLabel == "At Home Base")
liveCharacter = nil
assert(viewModel.getSurvivor("survivor-1", 0).locationLabel == "Away - assigned to Home Base")
duty.mode = "companion"
KnoxPersistence.isSurvivorAlive = function() return false end
local dead = viewModel.getSurvivor("survivor-1", 0)
assert(dead.alive == false and dead.activity == "Dead" and dead.locationLabel == "Deceased")
assert(#viewModel.getForPlayer(0) == 0, "dead persisted companion must leave HUD before roster cleanup")
KnoxPersistence.isSurvivorAlive = function() return true end
KnoxSurvivorRuntime.snapshot = function() return {loaded = false, activity = "away"} end
KnoxPersistence.getSurvivorLifeIntent = function() return nil end
KnoxPersistence.getUnloadedSurvivalState = function() return {activity = "returning_to_base"} end
assert(viewModel.getSurvivor("survivor-1", 0).activity == "Returning to base",
    "real unloaded runtime snapshot must allow persisted activity projection")
KnoxPersistence.getSurvivorLifeIntent = function() return {kind = "find_food"} end
for activity, label in pairs({
    returning_to_base = "Returning to base", sleeping = "Sleeping", resting = "Resting",
    base_working = "Working at base", waiting_for_leader = "Waiting for leader",
    away_mission = "On a mission", seeking_supplies = "Looking for food",
}) do
    KnoxPersistence.getUnloadedSurvivalState = function() return {activity = activity} end
    assert(viewModel.getSurvivor("survivor-1", 0).activity == label,
        "persisted activity must take precedence over an old intent: " .. activity)
end
print("survivor view-model tests passed")

-- Project real controller states through Runtime and the shared HUD/Card model.
local runtime = dofile("mod/42/media/lua/client/KS_SurvivorRuntime.lua")
local sq = { getX = function() return 10 end, getY = function() return 10 end,
    getZ = function() return 0 end }
local actor = { getCurrentSquare = function() return sq end }
local controller = { character = actor }
assert(runtime.register("survivor-1", controller))
for state, label in pairs({ FLEEING = "Retreating", BASE_TASK_MOVE = "Working at base",
    BASE_TASK_ACTION = "Working at base", BASE_TASK_SUPPLY_MOVE = "Collecting job supplies",
    BASE_TASK_SUPPLY_WAIT = "Waiting for materials", BASE_AMBIENT_REST = "Resting",
    PLAYER_CONVERSATION = "Talking", COMPANION_GUARD = "Keeping watch",
    MOVING_TO_DEPOSIT = "Storing supplies" }) do
    controller.state = state
    assert(viewModel.getSurvivor("survivor-1", 0).activity == label, "live state label: " .. state)
end
controller.state, controller.activeDecision = "TIMED_ACTION", "eat"
assert(viewModel.getSurvivor("survivor-1", 0).activity == "Eating", "self-care is explained")

controller.baseTask={type="guard"}
controller.state="BASE_TASK_WORK"
assert(viewModel.getSurvivor("survivor-1",0).activity=="Keeping watch")
controller.baseTask.type="patrol"
controller.state="BASE_TASK_PATROL_WAIT"
assert(runtime.snapshot("survivor-1").activity=="patrolling")
controller.state="FLEEING"
assert(viewModel.getSurvivor("survivor-1",0).activity=="Retreating", "retained security job never hides the current emergency")
