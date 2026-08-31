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
require "KS_Persistence"
local persistence = KnoxPersistence
local population = require "KS_WorldPopulation"
local simulation = require "KS_UnloadedSurvival"
local sleepEnabled = true
KnoxSurvivorNeeds = { sleepRequired = function() return sleepEnabled end }
KnoxJavaBridge = { consumeNpcRecordSupply = function() return nil end }
local function near(a, b) return math.abs(a - b) < .000001 end
local function state(id) return persistence.getUnloadedSurvivalState(id) end
local function reset()
    data = {}
    sleepEnabled = true
    for index, id in ipairs({ "a", "b", "c" }) do
        persistence.setRecord(id, "record-" .. id)
        persistence.setUnloadedSurvivalState(id, { hunger = .1, thirst = .1, health = 100,
            fatigue = .1, endurance = .9, lastHours = 0, virtualX = 100,
            virtualY = 100 + (index - 1) * 3, virtualZ = 0, status = "hibernated" })
    end
    return assert(persistence.createTravelGroup({ "a", "b", "c" }, 0))
end
local function edit(id, values)
    local current = state(id)
    for key, value in pairs(values) do current[key] = value end
    persistence.setUnloadedSurvivalState(id, current)
end
local group = reset()
local itineraryCalls = 0
local advanceItinerary = population.advanceItinerary
population.advanceItinerary = function(...)
    itineraryCalls = itineraryCalls + 1
    return advanceItinerary(...)
end
simulation.advanceAll({}, 1)
assert(itineraryCalls == 1, "one shared goal decision, not a catalog search per member")
assert(near(state("a").virtualX, 140), "group progresses toward real nearby catalog destination")
assert(near(state("b").virtualX, state("a").virtualX) and near(state("c").virtualY - state("a").virtualY, 6),
    "shared travel preserves member offsets instead of stacking")
assert(state("a").endurance < .9 and state("a").fatigue > .1, "group travel has real ledger costs")
assert(group.unloadedTravel.travelTarget and group.unloadedTravel.fatigue == nil
    and group.unloadedTravel.endurance == nil, "group persists itinerary, not duplicate physiology")
local target = group.unloadedTravel.travelTarget.key
edit("c", { endurance = .2 })
simulation.advanceAll({}, 2)
assert(near(state("a").virtualX, 140) and near(state("c").virtualX, 140),
    "one exhausted member pauses the whole group")
assert(state("a").restMode == "rest" and state("c").restMode == "rest"
    and group.unloadedTravel.travelTarget.key == target, "shared rest preserves the trip")
simulation.advanceAll({}, 9)
assert(state("a").virtualX > 140 and near(state("a").virtualX, state("c").virtualX),
    "group resumes together after its least-rested member recovers")
local x = state("a").virtualX
simulation.advanceAll({}, 9)
assert(state("a").virtualX == x, "same-time refresh does not double group travel")

-- Reload halfway through sleep: real ModData copies and no module-local itinerary.
group = reset()
edit("b", { fatigue = .8 })
simulation.advanceAll({}, 3)
assert(state("a").virtualX == 100 and state("b").restMode == "sleep", "group sleeps in place")
local saved = {}
for _, id in ipairs(group.memberIds) do saved[id] = state(id) end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {} for k, v in pairs(value) do result[k] = copy(v) end return result
end
local savedTrip = copy(group.unloadedTravel)
simulation.advanceAll({}, 10)
local straight = state("b")
for id, snapshot in pairs(saved) do persistence.setUnloadedSurvivalState(id, snapshot) end
group.unloadedTravel = savedTrip
package.loaded.KS_UnloadedSurvival = nil
KnoxUnloadedSurvival = nil
simulation = require "KS_UnloadedSurvival"
for hour = 4, 10 do simulation.advanceAll({}, hour) end
local segmented = state("b")
assert(near(straight.virtualX, segmented.virtualX) and near(straight.virtualY, segmented.virtualY)
    and near(straight.fatigue, segmented.fatigue) and near(straight.endurance, segmented.endurance),
    "sleep/reload/segmented updates preserve group progress and condition")

-- Partial activation gives native controllers ownership; stored members wait.
group = reset()
simulation.advanceAll({ "a" }, 2)
assert(state("a").lastHours == 0 and state("a").hunger == .1,
    "active member record and physiology are untouched")
assert(state("b").virtualX == 100 and state("b").hunger > .1 and state("b").activity == "group_waiting",
    "stored members wait but needs continue while an ally is active")
simulation.advanceAll({}, 3)
assert(near(state("a").virtualX, 140) and near(state("b").virtualX, 140),
    "different capture clocks align in place before shared movement")

group = reset()
edit("c", { virtualX = 0 })
simulation.advanceAll({}, 1)
assert(state("a").virtualX == 100 and near(state("c").virtualX, 39.928194),
    "leader waits and separated member approaches gradually without teleporting")
simulation.advanceAll({}, 3)
local dx, dy = state("a").virtualX - state("c").virtualX, state("a").virtualY - state("c").virtualY
assert(math.sqrt(dx * dx + dy * dy) <= 6.000001, "lagging member rejoins within bounded spacing")
simulation.advanceAll({}, 4)
assert(state("a").virtualX > 100, "regroup completes and leader continues")

group = reset()
edit("c", { virtualZ = 1 })
simulation.advanceAll({}, 1)
assert(state("a").virtualX == 100 and state("c").virtualZ == 1,
    "different-floor members do not invent an offscreen stair traversal")

group = reset()
edit("b", { hunger = .99, thirst = .99, health = 1 })
simulation.advanceAll({}, 1)
assert(not persistence.isSurvivorAlive("b") and persistence.isSurvivorAlive("a"),
    "real no-supply death remains authoritative inside a group")
assert(persistence.getTravelGroupFor("b") == nil, "dead member ownership cleaned by existing lifecycle")
simulation.advanceAll({}, 2)
assert(persistence.getTravelGroupFor("a") and not persistence.isSurvivorAlive("b"),
    "surviving group resumes without resurrecting its lost member")

group = reset()
simulation.advanceAll({}, 1)
persistence.removeTravelGroupMember("a")
simulation.advanceAll({}, 2)
local remaining = persistence.getTravelGroupFor("b")
assert(remaining and remaining.leaderId == "b" and remaining.unloadedTravel.members:find("leader:b", 1, true),
    "leader replacement invalidates old shared ownership")

group = reset()
sleepEnabled = false
edit("c", { fatigue = .95 })
simulation.advanceAll({}, 1)
assert(state("a").virtualX > 100 and state("c").fatigue == .95,
    "sleep-disabled group is not stranded by fatigue")

group = reset()
edit("a", { hunger = .99, thirst = .99, health = 1 })
simulation.advanceAll({}, 1)
assert(not persistence.isSurvivorAlive("a") and persistence.getTravelGroupFor("b").leaderId == "b",
    "native identity cleanup elects surviving group leader")
simulation.advanceAll({}, 2)
assert(persistence.getTravelGroupFor("b").unloadedTravel.members:find("leader:b", 1, true),
    "dead leader cannot retain shared trip ownership")

group = reset()
edit("c", { lastHours = 2 })
simulation.advanceAll({}, 1)
assert(state("c").lastHours == 2 and state("a").virtualX == 100,
    "clock rollback cannot rewind a member or start a contradictory cohort trip")

group = reset()
local root = data["KnoxSurvivors_IsoPlayer"]
root.survivors.c.unloadedSurvival = nil
simulation.advanceAll({}, 1)
assert(state("c") == nil and persistence.isSurvivorAlive("c") and state("a").virtualX == 100,
    "missing real needs snapshot pauses shared travel without inventing health")

group = reset()
local supplyCalls = {}
KnoxJavaBridge.consumeNpcRecordSupply = function(_, record, kind, amount)
    local key = record:sub(1, 8) .. ":" .. kind
    supplyCalls[key] = (supplyCalls[key] or 0) + 1
    local values = { record = record .. ":used", itemType = "real-test-supply",
        hungerRelief = kind == "food" and amount or 0,
        thirstRelief = kind == "water" and amount or 0 }
    return { get = function(_, key) return values[key] end }
end
for _, id in ipairs({ "a", "b", "c" }) do edit(id, { hunger = .65, thirst = .65 }) end
simulation.advanceAll({}, 1)
simulation.advanceAll({}, 1)
for _, id in ipairs({ "a", "b", "c" }) do
    assert(supplyCalls["record-" .. id .. ":food"] == 1 and supplyCalls["record-" .. id .. ":water"] == 1,
        "cohort update consumes each member's own real supplies once")
    assert(persistence.getRecord(id) == "record-" .. id .. ":used:used",
        "member resource changes commit to its own encoded record")
end
print("Unloaded groups PASS shared_travel=true rest=true regroup=true partial_activation=true persistence=true death=true")
