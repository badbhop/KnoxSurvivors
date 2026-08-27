local Simulation = rawget(_G, "KnoxUnloadedSurvival") or {}
_G.KnoxUnloadedSurvival = Simulation

-- Hibernated survivors are not hidden active characters.  This module advances a
-- small persisted survival ledger between body capture and reconstruction.  It
-- never creates supplies: food and water are removed from the encoded portable
-- inventory before the relief is recorded.
local MAX_STEP_HOURS = 6
local FOOD_TRIGGER = 0.60
local WATER_TRIGGER = 0.60
local FOOD_AFTER_MEAL = 0.22
local WATER_AFTER_DRINK = 0.22
local HUNGER_PER_HOUR = 0.026
local THIRST_PER_HOUR = 0.040
local FATIGUE_RECOVERY_PER_HOUR = 0.055
local ENDURANCE_RECOVERY_PER_HOUR = 0.090
local STARVATION_DAMAGE_PER_HOUR = 1.20
local DEHYDRATION_DAMAGE_PER_HOUR = 2.00

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function nowHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and tonumber(getGameTime():getWorldAgeHours()) or 0
end

local function summaryCounts(summary)
    local counts = {}
    for typeName, amount in string.gmatch(tostring(summary or ""), "([^;=]+)=([0-9]+)") do
        counts[typeName] = math.max(0, math.floor(tonumber(amount) or 0))
    end
    return counts
end

local function classify(typeName)
    if InventoryItemFactory == nil or InventoryItemFactory.CreateItem == nil then
        return nil
    end
    local ok, item = pcall(InventoryItemFactory.CreateItem, typeName)
    if not ok or item == nil then
        return nil
    end
    local food = false
    local water = false
    pcall(function()
        food = item:IsFood() and item:getHungerChange() < 0
    end)
    pcall(function()
        local fluid = item:getFluidContainer()
        water = fluid ~= nil and fluid:getAmount() > 0
    end)
    return { food = food, water = water }
end

local function chooseSupply(summary, wanted)
    for typeName, amount in pairs(summaryCounts(summary)) do
        if amount > 0 then
            local item = classify(typeName)
            if item ~= nil and item[wanted] then
                return typeName
            end
        end
    end
    return nil
end

local function consumeStoredItem(id, typeName)
    local persistence = rawget(_G, "KnoxPersistence")
    local bridge = rawget(_G, "KnoxJavaBridge")
    if persistence == nil or bridge == nil or bridge.consumeNpcRecordItem == nil then
        return false, "record_mutator_unavailable"
    end
    local record = persistence.getRecord(id)
    if record == nil then
        return false, "record_unavailable"
    end
    local ok, updated = pcall(bridge.consumeNpcRecordItem, bridge, record, typeName)
    if not ok or type(updated) ~= "string" or updated == "" then
        return false, "item_not_present"
    end
    if not persistence.setRecord(id, updated) then
        return false, "record_save_failed"
    end
    local summaryOk, summary = pcall(bridge.getNpcRecordInventorySummary, bridge, updated)
    if summaryOk and type(summary) == "string" then
        persistence.setInventorySummary(id, summary, nowHours())
    end
    return true, typeName
end

local function ensureState(id, snapshot, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local existing = persistence ~= nil and persistence.getUnloadedSurvivalState(id) or nil
    if existing ~= nil then
        return existing
    end
    return {
        hunger = clamp(snapshot and snapshot.hunger, 0, 1),
        thirst = clamp(snapshot and snapshot.thirst, 0, 1),
        fatigue = clamp(snapshot and snapshot.fatigue, 0, 1),
        endurance = clamp(snapshot and snapshot.endurance, 0, 1),
        health = clamp(snapshot and snapshot.health, 0, 100),
        bleedingParts = math.max(0, math.floor(tonumber(snapshot and snapshot.bleedingParts) or 0)),
        lastHours = hours,
        status = "stored",
    }
end

function Simulation.captureLoaded(id, snapshot, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or type(id) ~= "string" or snapshot == nil then
        return false
    end
    local state = ensureState(id, snapshot, tonumber(hours) or nowHours())
    state.hunger = clamp(snapshot.hunger, 0, 1)
    state.thirst = clamp(snapshot.thirst, 0, 1)
    state.fatigue = clamp(snapshot.fatigue, 0, 1)
    state.endurance = clamp(snapshot.endurance, 0, 1)
    state.health = clamp(snapshot.health, 0, 100)
    state.bleedingParts = math.max(0, math.floor(tonumber(snapshot.bleedingParts) or 0))
    state.lastHours = tonumber(hours) or nowHours()
    state.status = "loaded"
    return persistence.setUnloadedSurvivalState(id, state)
end

local function advanceOne(id, state, hours)
    local elapsed = math.max(0, hours - (tonumber(state.lastHours) or hours))
    if elapsed <= 0 then
        return state, nil
    end
    state.hunger = clamp(state.hunger + HUNGER_PER_HOUR * elapsed, 0, 1)
    state.thirst = clamp(state.thirst + THIRST_PER_HOUR * elapsed, 0, 1)
    state.fatigue = clamp(state.fatigue - FATIGUE_RECOVERY_PER_HOUR * elapsed, 0, 1)
    state.endurance = clamp(state.endurance + ENDURANCE_RECOVERY_PER_HOUR * elapsed, 0, 1)
    local persistence = rawget(_G, "KnoxPersistence")
    local summary = persistence ~= nil and persistence.getInventorySummary(id) or ""
    local events = {}
    if state.thirst >= WATER_TRIGGER then
        local water = chooseSupply(summary, "water")
        if water ~= nil then
            local consumed, evidence = consumeStoredItem(id, water)
            if consumed then
                state.thirst = WATER_AFTER_DRINK
                events[#events + 1] = "drank=" .. evidence
                summary = persistence.getInventorySummary(id)
            end
        end
    end
    if state.hunger >= FOOD_TRIGGER then
        local food = chooseSupply(summary, "food")
        if food ~= nil then
            local consumed, evidence = consumeStoredItem(id, food)
            if consumed then
                state.hunger = FOOD_AFTER_MEAL
                events[#events + 1] = "ate=" .. evidence
            end
        end
    end
    if state.hunger >= 0.95 then
        state.health = clamp(state.health - STARVATION_DAMAGE_PER_HOUR * elapsed, 0, 100)
        events[#events + 1] = "starving"
    end
    if state.thirst >= 0.95 then
        state.health = clamp(state.health - DEHYDRATION_DAMAGE_PER_HOUR * elapsed, 0, 100)
        events[#events + 1] = "dehydrated"
    end
    state.lastHours = hours
    state.status = state.health <= 0 and "dead" or "hibernated"
    return state, #events > 0 and table.concat(events, ",") or nil
end

function Simulation.advanceHibernated(id, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or not persistence.isSurvivorAlive(id) or persistence.getRecord(id) == nil then
        return false, "not_hibernated"
    end
    local targetHours = tonumber(hours) or nowHours()
    local state = ensureState(id, nil, targetHours)
    local events = {}
    while (tonumber(state.lastHours) or targetHours) < targetHours do
        local stepHours = math.min(
            targetHours,
            (tonumber(state.lastHours) or targetHours) + MAX_STEP_HOURS
        )
        local nextState, event = advanceOne(id, state, stepHours)
        state = nextState
        if event ~= nil then
            events[#events + 1] = event
        end
        if state.status == "dead" then
            break
        end
    end
    persistence.setUnloadedSurvivalState(id, state)
    if state.status == "dead" then
        persistence.markSurvivorDead(id, targetHours, "unloaded_survival")
        return true, "died"
    end
    return true, #events > 0 and table.concat(events, ",") or "advanced"
end

function Simulation.advanceAll(activeIds, hours)
    local active = {}
    for _, id in ipairs(activeIds or {}) do
        active[id] = true
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then
        return 0, 0
    end
    local advanced, notable = 0, 0
    for _, id in ipairs(persistence.getActivatableSurvivorIds()) do
        if not active[id] and persistence.getRecord(id) ~= nil then
            local ok, result = Simulation.advanceHibernated(id, hours)
            if ok then
                advanced = advanced + 1
                if result ~= "advanced" then
                    notable = notable + 1
                    print("[KnoxSurvivors][Unloaded] id=" .. id .. " event=" .. tostring(result))
                end
            end
        end
    end
    return advanced, notable
end

function Simulation.applyToLoaded(id, character)
    local persistence = rawget(_G, "KnoxPersistence")
    local state = persistence ~= nil and persistence.getUnloadedSurvivalState(id) or nil
    if state == nil or character == nil then
        return false, "no_stored_state"
    end
    local ok, evidence = pcall(function()
        local stats = character:getStats()
        stats:set(CharacterStat.HUNGER, clamp(state.hunger, 0, 1))
        stats:set(CharacterStat.THIRST, clamp(state.thirst, 0, 1))
        stats:set(CharacterStat.FATIGUE, clamp(state.fatigue, 0, 1))
        stats:set(CharacterStat.ENDURANCE, clamp(state.endurance, 0, 1))
        local bodyDamage = character:getBodyDamage()
        -- BodyDamage has no setHealth() in Build 42.20.3.  The aggregate
        -- body-health setter is the supported counterpart to getHealth(); the
        -- old call was caught by pcall, so a survivor still spawned but every
        -- spawn produced a Lua error and skipped its unloaded-health restore.
        bodyDamage:setOverallBodyHealth(clamp(state.health, 0, 100))
    end)
    if ok then
        state.status = "loaded"
        state.lastHours = nowHours()
        persistence.setUnloadedSurvivalState(id, state)
        return true, "applied"
    end
    return false, tostring(evidence)
end

return Simulation
