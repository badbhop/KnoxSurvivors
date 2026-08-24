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
    getSurvivorCapabilities = function() return { professionId = "park-ranger" } end,
    getPlayerRelationshipSnapshot = function()
        return { firstMetHours = 52 }
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

loaded.affiliation.kind = "changed"
assert(affiliation.kind == "player")
loaded.duty.order = "changed"
assert(duty.order == "follow")

local party = viewModel.getForPlayer(0)
assert(#party == 1)
assert(party[1].id == "survivor-1")

print("survivor view-model tests passed")
