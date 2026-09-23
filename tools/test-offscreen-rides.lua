local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = {}
ModData = { getOrCreate = function(key) data[key] = data[key] or {} return data[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 0 end } end
package.preload.SpawnRegions = function() return true end
SpawnRegionMgr = { getSpawnRegions = function()
    return { { name = "Town", points = { unemployed = {
        { posX = 100, posY = 100, posZ = 0 }, { posX = 500, posY = 100, posZ = 0 },
        { posX = 900, posY = 100, posZ = 0 },
    } } } }
end }
CharacterStat = { HUNGER = "h", THIRST = "t", FATIGUE = "f", ENDURANCE = "e" }
KnoxSurvivorNeeds = { sleepRequired = function() return false end }

require "KS_Persistence"
local persistence = KnoxPersistence
local population = require "KS_WorldPopulation"
local simulation = require "KS_UnloadedSurvival"
assert(rawget(_G, "KnoxOffscreenStoriesDisabled") ~= true, "rides run with storylets enabled")

local function resetSolo(id, x)
    persistence.setRecord(id, "record-" .. id)
    persistence.setUnloadedSurvivalState(id, {
        hunger = .1, thirst = .1, fatigue = .2, endurance = .8, health = 100,
        bleedingParts = 0, lastHours = 0, status = "hibernated", activity = "exploring",
        virtualX = x or 100, virtualY = 100, virtualZ = 0, virtualAtHours = 0,
    })
end

-- Solo legs ride at vehicle pace with no walking drain.
resetSolo("rider", 100)
local rider = persistence.getUnloadedSurvivalState("rider")
rider.vehicleTrip = { targetX = 500, targetY = 100, targetZ = 0, atHours = 0 }
persistence.setUnloadedSurvivalState("rider", rider)
assert(simulation.advanceHibernated("rider", 1))
rider = persistence.getUnloadedSurvivalState("rider")
local rode = math.sqrt((rider.virtualX - 100) ^ 2 + (rider.virtualY - 100) ^ 2)
assert(rode >= 290 and rode <= 310, "vehicle legs advance near 300 tiles per hour")
assert(rider.activity == "riding", "riding legs report riding")
assert(rider.endurance >= 0.8, "riders do not pay walking endurance")
assert(rider.vehicleTrip ~= nil, "trips persist mid-journey")
print("Solo ride PASS distance=" .. string.format("%.1f", rode))

-- Arrival dissolves the trip with history.
rider.vehicleTrip = { targetX = rider.virtualX + 5, targetY = 100, targetZ = 0, atHours = 1 }
rider.lastHours = 1
persistence.setUnloadedSurvivalState("rider", rider)
assert(simulation.advanceHibernated("rider", 2))
rider = persistence.getUnloadedSurvivalState("rider")
assert(rider.vehicleTrip == nil, "arrival dissolves the trip")
local arrived = false
for _, entry in ipairs(rider.history or {}) do
    if entry.kind == "ride" and entry.outcome == "arrived" then arrived = true break end
end
assert(arrived, "arrivals append ride history")
print("Ride arrival PASS")

-- Stale trips time out instead of stranding travelers.
rider.vehicleTrip = { targetX = 5000, targetY = 100, targetZ = 0, atHours = 0 }
rider.lastHours = 0
rider.virtualX, rider.virtualY = 100, 100
persistence.setUnloadedSurvivalState("rider", rider)
assert(simulation.advanceHibernated("rider", 30))
rider = persistence.getUnloadedSurvivalState("rider")
assert(rider.vehicleTrip == nil, "24-hour trips time out")
print("Ride timeout PASS")

-- Catch-a-ride storylets only fire for far goals, never nearby ones.
resetSolo("driver", 100)
persistence.setRecord("driver", "record-driver")
resetSolo("passenger", 103)
persistence.setRecord("passenger", "record-passenger")
local group = assert(persistence.createTravelGroup({ "driver", "passenger" }, 0))
assert(persistence.setSurvivorLifeIntent("driver", {
    kind = "investigate_building", phase = "traveling",
    targetKey = "building:900:100:0", targetX = 900, targetY = 100, targetZ = 0,
}, 0))
assert(persistence.setTravelGroupObjective(group.id, "driver", persistence.getSurvivorLifeIntent("driver"), 0))
local stories = assert(rawget(_G, "KnoxOffscreenStories"))
local rode_at = nil
for phase = 1, 200 do
    local probe = {
        hunger = .1, thirst = .1, fatigue = .2, endurance = .8, health = 100,
        bleedingParts = 0, lastHours = (phase - 1) * 6, status = "hibernated",
        activity = "group_objective", virtualX = 100, virtualY = 100, virtualZ = 0,
    }
    if stories.resolveFor("driver", probe, phase * 6, 6) == "riding" then
        rode_at = phase
        assert(probe.vehicleTrip ~= nil and probe.vehicleTrip.targetX == 900, "rides target the far goal")
        break
    end
end
assert(rode_at ~= nil, "far goals eventually catch rides")
assert(stories.rideTarget("passenger", persistence.getUnloadedSurvivalState("passenger")) == nil,
    "only the canonical group leader may own a virtual ride")
local followerRides = 0
for phase = 1, 200 do
    local probe = {
        hunger = .1, thirst = .1, fatigue = .2, endurance = .8, health = 100,
        bleedingParts = 0, lastHours = (phase - 1) * 6, status = "hibernated",
        activity = "group_objective", virtualX = 103, virtualY = 100, virtualZ = 0,
    }
    if stories.resolveFor("passenger", probe, phase * 6, 6) == "riding" then
        followerRides = followerRides + 1
    end
    assert(probe.vehicleTrip == nil, "followers never acquire independent virtual trips")
end
assert(followerRides == 0, "catch-ride story is leader gated")
local nearHits = 0
for phase = 1, 200 do
    local probe = {
        hunger = .1, thirst = .1, fatigue = .2, endurance = .8, health = 100,
        bleedingParts = 0, lastHours = (phase - 1) * 6, status = "hibernated",
        activity = "group_objective", virtualX = 850, virtualY = 100, virtualZ = 0,
    }
    if stories.resolveFor("driver", probe, phase * 6, 6) == "riding" then
        nearHits = nearHits + 1
    end
end
assert(nearHits == 0, "nearby goals never catch rides")
print("Catch-a-ride PASS far_phase=" .. tostring(rode_at))

-- Group cohorts ride together when the leader holds a trip.
local driver = persistence.getUnloadedSurvivalState("driver")
driver.virtualX, driver.virtualY, driver.virtualZ = 100, 100, 0
driver.lastHours = 0
driver.endurance = 0.8
driver.vehicleTrip = { targetX = 900, targetY = 100, targetZ = 0, atHours = 0 }
persistence.setUnloadedSurvivalState("driver", driver)
local passenger = persistence.getUnloadedSurvivalState("passenger")
passenger.virtualX, passenger.virtualY, passenger.virtualZ = 103, 100, 0
passenger.lastHours = 0
passenger.endurance = 0.8
persistence.setUnloadedSurvivalState("passenger", passenger)
simulation.advanceAll({}, 1)
driver = persistence.getUnloadedSurvivalState("driver")
passenger = persistence.getUnloadedSurvivalState("passenger")
assert(driver.virtualX >= 390 and driver.virtualX <= 410, "cohort rides at vehicle pace")
assert(passenger.endurance >= 0.8, "passengers do not pay walking endurance")
local shared = persistence.getTravelGroupFor("driver")
assert(shared ~= nil, "cohort intact after riding")
print("Cohort ride PASS leader_x=" .. string.format("%.1f", driver.virtualX))

-- New foot routes and materialization dissolve trips.
assert(simulation.beginBaseReturn("driver",
    { id = "home-base", territory = { minX = 0, minY = 0, maxX = 2, maxY = 2, z = 0 } }, 2))
assert(persistence.getUnloadedSurvivalState("driver").vehicleTrip == nil, "base returns supersede rides")
driver = persistence.getUnloadedSurvivalState("driver")
driver.vehicleTrip = { targetX = 900, targetY = 100, targetZ = 0, atHours = 2 }
driver.status = "hibernated"
driver.pendingMaterialization = nil
persistence.setUnloadedSurvivalState("driver", driver)
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z or 0 end }
end
local body = {
    getCurrentSquare = function() return square(100, 100, 0) end,
    getStats = function() return { set = function() end } end,
    getBodyDamage = function() return { setOverallBodyHealth = function() end } end,
}
local applied, reason = simulation.applyToLoaded("driver", body)
assert(applied and reason == "applied", "materialization applies stored state")
assert(persistence.getUnloadedSurvivalState("driver").vehicleTrip == nil, "trips dissolve on load")
print("Ride dissolve PASS")

print("Offscreen rides PASS solo=true arrival=true timeout=true catch=true cohort=true dissolve=true")
