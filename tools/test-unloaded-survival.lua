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
        hunger = 0.58, thirst = 0.58, fatigue = 0.70, endurance = 0.20,
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
            return { id = id, territory = { minX = 112, minY = 200, width = 1, height = 1, z = 0 } }
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
    consumeNpcRecordItem = function(_, record, typeName)
        local summary = summaries[record] or ""
        if not string.find(summary, typeName .. "=1", 1, true) then
            return ""
        end
        consumeCount = consumeCount + 1
        local nextRecord = record .. "-" .. tostring(consumeCount)
        summaries[nextRecord] = summary:gsub(typeName .. "=1;?", "")
        return nextRecord
    end,
    getNpcRecordInventorySummary = function(_, record)
        return summaries[record] or ""
    end,
    getTestNpcRecordX = function() return 100 end,
    getTestNpcRecordY = function() return 200 end,
    getTestNpcRecordZ = function() return 0 end,
}

InventoryItemFactory = {
    CreateItem = function(typeName)
        if typeName == "Base.CannedSoup" then
            return {
                IsFood = function() return true end,
                getHungerChange = function() return -0.3 end,
                getFluidContainer = function() return nil end,
            }
        end
        if typeName == "Base.WaterBottleFull" then
            return {
                IsFood = function() return false end,
                getHungerChange = function() return 0 end,
                getFluidContainer = function()
                    return { getAmount = function() return 10 end }
                end,
            }
        end
        return nil
    end,
}

local simulation = require "KS_UnloadedSurvival"
local advanced, event = simulation.advanceHibernated("survivor", 6)
assert(advanced and event ~= "died", "stored survivor advances")
assert(states.survivor.thirst == 0.22 and states.survivor.hunger == 0.22,
    "real stored food and water relieve needs")
assert(states.survivor.fatigue < 0.70 and states.survivor.endurance > 0.20,
    "hibernation recovers rest and endurance")
assert(summaries[records.survivor] == "", "consumed supplies leave stored inventory")
assert(states.survivor.activity == "surviving"
    and (states.survivor.virtualX ~= 100 or states.survivor.virtualY ~= 200),
    "unloaded autonomous survivor advances through the world")

assert(simulation.advanceHibernated("base", 6), "base resident advances")
assert(states.base.activity == "base_life"
    and states.base.virtualX >= 90 and states.base.virtualX < 110
    and states.base.virtualY >= 190 and states.base.virtualY < 210,
    "base resident advances within its own persisted base territory")
assert(simulation.advanceHibernated("group-a", 6), "first group member advances")
assert(simulation.advanceHibernated("group-b", 6), "second group member advances")
assert(states["group-a"].activity == "group_travel"
    and states["group-a"].virtualX == states["group-b"].virtualX
    and states["group-a"].virtualY == states["group-b"].virtualY,
    "unloaded travel group keeps a shared virtual heading")
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
    and states.returner.virtualX > 100 and states.returner.virtualX < 112,
    "base return moves from the captured origin instead of teleporting")
assert(simulation.advanceHibernated("returner", 12), "base return can reach its destination")
assert(states.returner.activity == "base_life" and states.returner.baseReturn == nil
    and states.returner.virtualX == 112 and states.returner.virtualY == 200,
    "arrived base resident switches to normal base life")

advanced, event = simulation.advanceHibernated("empty", 6)
assert(advanced and event == "died" and dead.empty,
    "no-resource starvation/dehydration can persist death")

print("Unloaded survival PASS stored_resources=true recovery=true durable_death=true virtual_life=true")
