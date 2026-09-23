local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function point(x, y, z)
    return { posX = x, posY = y, posZ = z or 0 }
end

local function room(name, x, y)
    local rect = {
        getX = function() return x end, getY = function() return y end,
        getW = function() return 4 end, getH = function() return 4 end,
    }
    return {
        getName = function() return name end,
        getZ = function() return 0 end,
        getRects = function() return list({ rect }) end,
    }
end

local function building(id, rooms)
    return {
        getID = function() return id end,
        getRooms = function() return list(rooms) end,
    }
end

local roots = {
    KnoxSurvivors_IsoPlayer = {
        schemaVersion = 17,
        survivors = {
            legacy = {
                alive = true,
                origin = { x = 700, y = 700, z = 0, key = "700,700,0",
                    region = "Old", regionKey = "Old#1", source = "player_spawn" },
                capabilities = { professionId = "base:doctor", traitIds = {}, skills = {} },
            },
            damaged = {
                alive = true,
                origin = { x = 701, y = 700, z = 0, key = "701,700,0",
                    region = "Old", regionKey = "Old#1", source = "player_spawn",
                    context = "secret_lab", professionCandidates = { "base:doctor" } },
            },
        },
    },
}
ModData = { getOrCreate = function(key) roots[key] = roots[key] or {} return roots[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 12 end } end

local empty = list({})
local doctor = {
    getType = function() return "base:doctor" end,
    getCost = function() return 0 end,
    getGrantedTraits = function() return empty end,
}
local police = {
    getType = function() return "base:policeofficer" end,
    getCost = function() return 0 end,
    getGrantedTraits = function() return empty end,
}
CharacterProfessionDefinition = {
    getProfessions = function() return list({ doctor, police }) end,
    getCharacterProfessionDefinition = function(id)
        if id == "base:doctor" then return doctor end
        if id == "base:policeofficer" then return police end
        return nil
    end,
}
CharacterTraitDefinition = {
    getTraits = function() return empty end,
    getCharacterTraitDefinition = function() return nil end,
}
isMultiplayer = function() return false end

SpawnRegionMgr = { getSpawnRegions = function()
    return { { name = "Test", points = {
        doctor = { point(100, 100), point(110, 100), point(120, 100) },
        policeofficer = { point(100, 100), point(110, 100), point(120, 100) },
    } } }
end }
package.preload.SpawnRegions = function() return true end

local buildings = list({
    building(1, { room("livingroom", 250, 250) }),
    building(2, { room("hospitalroom", 260, 260) }),
})
getWorld = function()
    return {
        getMap = function() return "Context Map" end,
        getMetaGrid = function()
            return { getBuildings = function() return buildings end }
        end,
    }
end
getNumActivePlayers = function() return 0 end
SandboxVars = { KnoxSurvivors = {
    WorldPopulation = 1, PopulationRefillDays = 0,
    InitialGroupChance = 0, InitialGroupMaxSize = 2,
} }

require "KS_Settings"
require "KS_Persistence"
require "KS_WorldPopulation"

local legacy = assert(KnoxPersistence.getSurvivorOrigin("legacy"))
assert(legacy.context == nil and legacy.professionCandidates == nil
    and KnoxPersistence.getSurvivorCapabilities("legacy").professionId == "base:doctor",
    "schema-17 survivor origin and capabilities are preserved without inference")
assert(roots.KnoxSurvivors_IsoPlayer.schemaVersion == 18, "origin metadata migration advances schema")
local damaged = assert(KnoxPersistence.getSurvivorOrigin("damaged"))
assert(damaged.context == "generic" and damaged.professionCandidates == nil,
    "invalid old metadata sanitizes to generic")

local catalog = assert(KnoxWorldPopulation.spawnCatalog())
assert(#catalog.origins == 4 and catalog.buildingOrigins == 1,
    "one building origin per bucket preserves catalog thinning")
local merged = assert(catalog.byKey["100,100,0"])
assert(#merged.professionCandidates == 2
    and merged.professionCandidates[1] == "base:doctor"
    and merged.professionCandidates[2] == "base:policeofficer"
    and merged.context == "generic",
    "duplicate spawn coordinates merge sorted profession evidence without false context")
local facility = assert(catalog.byKey["262,262,0"])
assert(facility.context == "medical" and facility.buildingId == "2",
    "semantic building outranks a generic building in the same thinning bucket")

local initialized = KnoxWorldPopulation.maintain(12, { initialAllocationBudget = 1 })
assert(initialized.status == "initialized" and #initialized.addedIds == 1)
local id = initialized.addedIds[1]
local profile = assert(KnoxPersistence.getSurvivorCapabilities(id))
assert(profile.professionId == "base:doctor" or profile.professionId == "base:policeofficer",
    "ordinary identities receive contextual native capabilities before materialization")
local savedOrigin = assert(KnoxPersistence.getSurvivorOrigin(id))
local reread = assert(KnoxPersistence.getSurvivorOrigin(id))
if savedOrigin.professionCandidates ~= nil then
    savedOrigin.professionCandidates[1] = "base:unemployed"
    assert(reread.professionCandidates[1] ~= "base:unemployed",
        "origin candidate lists are returned defensively and remain immutable in the save")
end

assert(KnoxPersistence.setRecord("traveler", "record"))
assert(KnoxPersistence.setSurvivorCapabilities("traveler", {
    version = 1, professionId = "base:doctor", traitIds = {}, skills = {},
}))
local state = {
    virtualX = 200, virtualY = 200, virtualZ = 0,
    lastHours = 0, departAtHours = 0, travelSequence = 0,
}
assert(KnoxWorldPopulation.advanceItinerary("traveler", state, 0, 1))
assert(state.travelTarget ~= nil and state.travelTarget.key == facility.key,
    "profession affinity selects a matching facility only from valid travel candidates")
local repeatState = {
    virtualX = 200, virtualY = 200, virtualZ = 0,
    lastHours = 0, departAtHours = 0, travelSequence = 0,
}
assert(KnoxWorldPopulation.advanceItinerary("traveler", repeatState, 0, 1))
assert(repeatState.travelTarget.key == state.travelTarget.key,
    "facility travel preference is deterministic")
local excludedState = {
    virtualX = 200, virtualY = 200, virtualZ = 0,
    lastHours = 0, departAtHours = 0, travelSequence = 0,
    previousTravelKey = facility.key,
}
assert(KnoxWorldPopulation.advanceItinerary("traveler", excludedState, 0, 1))
assert(excludedState.travelTarget ~= nil and excludedState.travelTarget.key ~= facility.key,
    "facility affinity cannot bypass the existing previous-target hard gate")

print("Contextual origins PASS merge=true building_priority=true schema=true early_capability=true travel=true")
