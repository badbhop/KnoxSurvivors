local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path

local records = {
    survivor = "record-0",
    empty = "record-empty",
    base = "record-base",
    ["group-a"] = "record-group-a",
    ["group-b"] = "record-group-b",
    away = "record-away",
    returner = "record-returner",
}
local summaries = {
    ["record-0"] = "Base.WaterBottleFull=1;Base.CannedSoup=1",
    ["record-empty"] = "",
}
local states = {
    survivor = {
        hunger = 0.58, thirst = 0.58, fatigue = 0.80, endurance = 0.20,
        health = 100, bleedingParts = 0, lastHours = 0, status = "hibernated",
    },
    empty = {
        hunger = 0.98, thirst = 0.98, fatigue = 0.2, endurance = 0.8,
        health = 5, bleedingParts = 0, lastHours = 0, status = "hibernated",
    },
}
for _, id in ipairs({ "base", "group-a", "group-b", "away", "returner" }) do
    states[id] = {
        hunger = 0.1, thirst = 0.1, fatigue = 0.2, endurance = 0.8,
        health = 100, bleedingParts = 0, lastHours = 0, status = "hibernated",
    }
end
local dead = {}
local duties = {
    base = { mode = "base", baseId = "base-1" },
    away = { mode = "away", missionId = "mission-1" },
    returner = { mode = "base", baseId = "base-return" },
}

KnoxPersistence = {
    isSurvivorAlive = function(id) return not dead[id] end,
    getRecord = function(id) return records[id] end,
    setRecord = function(id, record) records[id] = record return true end,
    getInventorySummary = function(id) return summaries[records[id]] or "" end,
    setInventorySummary = function(id, summary) summaries[records[id]] = summary return true end,
    getUnloadedSurvivalState = function(id) return states[id] end,
    setUnloadedSurvivalState = function(id, state) states[id] = state return true end,
    markSurvivorDead = function(id) dead[id] = true return true end,
    getActivatableSurvivorIds = function()
        return { "empty", "survivor", "base", "group-a", "group-b", "away", "returner" }
    end,
    getSurvivorDuty = function(id) return duties[id] or { mode = "autonomous" } end,
    getAwayTeamForSurvivor = function(id)
        if id == "away" then
            return { id = "mission-1", destination = { x = 310, y = 420, z = 0 } }
        end
        return nil
    end,
    getBase = function(id)
        if id == "base-1" then
            return { territory = { minX = 90, minY = 190, width = 20, height = 20, z = 0 } }
        end
        if id == "base-return" then
            return { id = id, territory = { minX = 500, minY = 200, width = 1, height = 1, z = 0 } }
        end
        return nil
    end,
    getTravelGroupFor = function(id)
        if id == "group-a" or id == "group-b" then return { id = "travel-group-1" } end
        return nil
    end,
    getSurvivorAffiliation = function() return {} end,
}

local consumeCount = 0
KnoxJavaBridge = {
    consumeNpcRecordSupply = function(_, record, kind, requested)
        local typeName = kind == "water" and "Base.WaterBottleFull" or "Base.CannedSoup"
        local summary = summaries[record] or ""
        if not string.find(summary, typeName .. "=1", 1, true) then
            return nil
        end
        consumeCount = consumeCount + 1
        local nextRecord = record .. "-" .. tostring(consumeCount)
        summaries[nextRecord] = kind == "water" and summary or summary:gsub(typeName .. "=1;?", "")
        local fields = { record = nextRecord, itemType = typeName,
            hungerRelief = kind == "food" and math.min(requested, 0.3) or 0,
            thirstRelief = kind == "water" and math.min(requested, 0.6) or 0 }
        return { get = function(_, key) return fields[key] end }
    end,
    getNpcRecordInventorySummary = function(_, record)
        return summaries[record] or ""
    end,
    getTestNpcRecordX = function() return 100 end,
    getTestNpcRecordY = function() return 200 end,
    getTestNpcRecordZ = function() return 0 end,
}

InventoryItemFactory = {
    CreateItem = function() error("offscreen consumption must never classify a default item") end,
}

local simulation = require "KS_UnloadedSurvival"
local sleepEnabled = true
KnoxSurvivorNeeds = { sleepRequired = function() return sleepEnabled end }
local itineraryCalls = 0
KnoxWorldPopulation = { advanceItinerary = function(_, state, startHours, endHours)
    itineraryCalls = itineraryCalls + 1
    state.virtualX = state.virtualX + (endHours - startHours) * 40
    state.travelTarget = state.travelTarget or { x = 900, y = 200, z = 0, key = "nearby-building" }
    return true, "travel_advanced", endHours - startHours
end }
local advanced, event = simulation.advanceHibernated("survivor", 6)
assert(advanced and event ~= "died", "stored survivor advances")
assert(math.abs(states.survivor.thirst - 0.22) < 0.00001
    and math.abs(states.survivor.hunger - 0.436) < 0.00001,
    "need relief reflects actual consumed supply, not a fixed meal reset")
assert(states.survivor.fatigue < 0.80 and states.survivor.endurance > 0.20,
    "sleep recovers fatigue and endurance")
assert(summaries[records.survivor] == "Base.WaterBottleFull=1;",
    "consumed food leaves stored inventory but reusable bottle remains")
assert(states.survivor.activity == "sleeping"
    and states.survivor.virtualX == 100 and states.survivor.virtualY == 200,
    "sleeping survivor remains at their current location")
assert(simulation.advanceHibernated("survivor", 10))
assert(states.survivor.activity == "surviving" and states.survivor.virtualX > 100,
    "rested survivor resumes existing itinerary")

assert(simulation.advanceHibernated("base", 6), "base resident advances")
assert(states.base.activity == "base_life"
    and states.base.virtualX >= 90 and states.base.virtualX < 110
    and states.base.virtualY >= 190 and states.base.virtualY < 210,
    "base resident advances within its own persisted base territory")
assert(simulation.advanceHibernated("group-a", 6), "first group member advances")
assert(simulation.advanceHibernated("group-b", 6), "second group member advances")
assert(states["group-a"].activity == "group_waiting"
    and states["group-a"].virtualX == 100 and states["group-b"].virtualX == 100,
    "isolated member update waits for the cohort scheduler instead of drifting")
local awayBefore = states.away.lastHours
local awayHungerBefore = states.away.hunger
simulation.advanceAll({ "survivor", "empty", "base", "group-a", "group-b", "returner" }, 6)
assert(states.away.lastHours > awayBefore and states.away.hunger > awayHungerBefore,
    "away-team physiology advances without taking ownership of mission travel")
assert(states.away.activity == "away_mission"
    and states.away.virtualX == 310 and states.away.virtualY == 420,
    "away-team ledger retains its destination for post-mission materialization")

assert(simulation.beginBaseReturn("returner", KnoxPersistence.getBase("base-return"), 0),
    "base-return handoff creates a durable virtual route")
assert(simulation.advanceHibernated("returner", 6), "base return advances off-screen")
assert(states.returner.activity == "returning_to_base"
    and states.returner.virtualX == 340,
    "base return moves from the captured origin instead of teleporting")
assert(simulation.advanceHibernated("returner", 12), "base return can reach its destination")
assert(states.returner.activity == "base_life" and states.returner.baseReturn == nil
    and states.returner.virtualX == 500 and states.returner.virtualY == 200,
    "arrived base resident switches to normal base life")

advanced, event = simulation.advanceHibernated("empty", 6)
assert(advanced and event == "died" and dead.empty,
    "no-resource starvation/dehydration can persist death")

records.unknown = "record-without-needs"
local unknown, unknownReason = simulation.advanceHibernated("unknown", 100)
assert(not unknown and unknownReason == "real_survival_snapshot_required" and not dead.unknown,
    "missing needs snapshot must not invent zero health and kill a stored survivor")
assert(not simulation.beginBaseReturn("unknown", KnoxPersistence.getBase("base-return"), 100),
    "base-return handoff cannot seed fake needs when capture data is missing")
local savedSetRecord = KnoxPersistence.setRecord
KnoxPersistence.setRecord = function() return false end
states.rejected = { hunger = .61, thirst = .61, health = 100, fatigue = .1, endurance = .9, lastHours = 0 }
records.rejected = "record-0"
simulation.advanceHibernated("rejected", 1)
assert(states.rejected.hunger > .61 and states.rejected.thirst > .61
    and records.rejected == "record-0", "failed record commit cannot grant relief")
KnoxPersistence.setRecord = savedSetRecord
local callsBefore = consumeCount
simulation.advanceHibernated("rejected", 1)
assert(consumeCount == callsBefore, "same game time cannot re-consume resources")
local boundedCalls = 0
KnoxJavaBridge.consumeNpcRecordSupply = function(_, record, kind)
    boundedCalls = boundedCalls + 1
    local fields = { record = record .. ":supply", itemType = "small-portion",
        hungerRelief = kind == "food" and .01 or 0,
        thirstRelief = kind == "water" and .01 or 0 }
    return { get = function(_, key) return fields[key] end }
end
states.bounded = { hunger = .7, thirst = .7, health = 100, fatigue = .1, endurance = .9, lastHours = 0 }
records.bounded = "bounded-record"
simulation.advanceHibernated("bounded", 1)
assert(boundedCalls == 8, "small supplies use at most four attempts per need per simulation step")
local function stored(id, fatigue, endurance)
    records[id] = "record-" .. id
    states[id] = { hunger = .1, thirst = .1, health = 100, fatigue = fatigue,
        endurance = endurance, lastHours = 0, virtualX = 100, virtualY = 200, virtualZ = 0 }
    return states[id]
end
local walker = stored("walker", .1, .9)
simulation.advanceHibernated("walker", 1)
assert(walker.virtualX == 140 and walker.fatigue > .1 and walker.endurance < .9,
    "awake travel progresses meaningfully and cannot grant sleep or endurance recovery")
local savedTarget = walker.travelTarget
walker.endurance = .2
simulation.advanceHibernated("walker", 2)
assert(walker.virtualX == 140 and walker.restMode == "rest" and walker.travelTarget == savedTarget,
    "exhaustion pauses travel without erasing its destination")
simulation.advanceHibernated("walker", 9)
assert(walker.virtualX > 140 and walker.travelTarget == savedTarget,
    "bounded rest ends and the same trip resumes")
local noSleep = stored("no-sleep", .95, .9)
sleepEnabled = false
simulation.advanceHibernated("no-sleep", 1)
assert(noSleep.virtualX == 140 and noSleep.fatigue == .95 and noSleep.restMode == nil,
    "disabled sleep rules cannot trap a tired survivor or manufacture sleep recovery")
sleepEnabled = true
local companion = stored("companion", .1, .9)
duties.companion = { mode = "companion", order = "hold" }
companion.baseReturn = { baseId = "base-return", targetX = 500, targetY = 200 }
simulation.advanceHibernated("companion", 1)
assert(companion.virtualX == 100 and companion.baseReturn == nil and duties.companion.order == "hold",
    "new companion duty cancels stale home travel without replacing Hold")
local relocated = stored("relocated", .1, .9)
duties.relocated = { mode = "base", baseId = "base-return" }
simulation.beginBaseReturn("relocated", KnoxPersistence.getBase("base-return"), 0)
relocated.baseReturn.targetX = 900
simulation.advanceHibernated("relocated", 1)
assert(relocated.baseReturn.targetX == 500 and relocated.virtualX == 140,
    "base relocation refreshes destination without teleporting")
local sleepingReturn = stored("sleeping-return", .8, .9)
duties["sleeping-return"] = { mode = "base", baseId = "base-return" }
simulation.beginBaseReturn("sleeping-return", KnoxPersistence.getBase("base-return"), 0)
simulation.advanceHibernated("sleeping-return", 3)
assert(sleepingReturn.baseReturn and sleepingReturn.virtualX == 100,
    "sleep preserves return-home intent without travelling")
local noCatalog = stored("no-catalog", .1, .9)
KnoxWorldPopulation = nil
simulation.advanceHibernated("no-catalog", 1)
assert(noCatalog.virtualX == 100 and noCatalog.activity == "sheltering",
    "missing location catalog does not fall back to arbitrary drifting")
print("Unloaded survival PASS stored_resources=true proportional=true transaction=true recovery=true durable_death=true virtual_life=true")
