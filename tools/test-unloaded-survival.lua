local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path

local records = {
    survivor = "record-0",
    empty = "record-empty",
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
local dead = {}

KnoxPersistence = {
    isSurvivorAlive = function(id) return not dead[id] end,
    getRecord = function(id) return records[id] end,
    setRecord = function(id, record) records[id] = record return true end,
    getInventorySummary = function(id) return summaries[records[id]] or "" end,
    setInventorySummary = function(id, summary) summaries[records[id]] = summary return true end,
    getUnloadedSurvivalState = function(id) return states[id] end,
    setUnloadedSurvivalState = function(id, state) states[id] = state return true end,
    markSurvivorDead = function(id) dead[id] = true return true end,
    getActivatableSurvivorIds = function() return { "empty", "survivor" } end,
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

advanced, event = simulation.advanceHibernated("empty", 6)
assert(advanced and event == "died" and dead.empty,
    "no-resource starvation/dehydration can persist death")

print("Unloaded survival PASS stored_resources=true recovery=true durable_death=true")
