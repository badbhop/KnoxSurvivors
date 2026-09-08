require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFromBottle"
require "TimedActions/ISTimedActionQueue"
require "KS_SurvivalMedical"
require "KS_SurvivorMedicalActions"
require "KS_SurvivorInventoryActions"

local Needs = rawget(_G, "KnoxSurvivorNeeds") or {}
_G.KnoxSurvivorNeeds = Needs

Needs.thresholds = {
    bleeding = 1,
    thirst = 0.55,
    hunger = 0.55,
    lowEndurance = 0.30,
    fatigue = 0.72,
}

local NEED_CHANGE_EPSILON = 0.001

local function actionAccepted(character, action)
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    return action ~= nil and queue:indexOf(action) ~= -1
end

local function walkInventory(container, visitor)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        visitor(item, container)
        if item:IsInventoryContainer() then
            walkInventory(item:getInventory(), visitor)
        end
    end
end

local function isSafeFood(item)
    if item == nil or not item:IsFood() or item:getHungerChange() >= -0.01 then
        return false
    end
    if item:isRotten() or item:isPoison() or item:getPoisonPower() > 0 then
        return false
    end
    if item:isbDangerousUncooked() and not item:isCooked() then
        return false
    end
    return true
end

local function foodScore(item)
    local hunger = math.abs(item:getHungerChange())
    local unhappinessPenalty = math.max(0, item:getUnhappyChange()) / 100
    return hunger - unhappinessPenalty
end

local function waterState(item)
    if item == nil or item:getFluidContainer() == nil then
        return nil
    end
    local fluid = item:getFluidContainer()
    if fluid:isEmpty() or not fluid:isWaterSource() then
        return nil
    end
    local tainted = false
    local success, result = pcall(function()
        return fluid:contains(Fluid.TaintedWater)
    end)
    if success then
        tainted = result == true
    end
    return { item = item, tainted = tainted, amount = fluid:getAmount() }
end

function Needs.findBestFood(character)
    local best = nil
    local bestScore = -math.huge
    walkInventory(character:getInventory(), function(item)
        if isSafeFood(item) then
            local score = foodScore(item)
            if score > bestScore then
                best = item
                bestScore = score
            end
        end
    end)
    return best
end

function Needs.isSafeFood(item)
    return isSafeFood(item)
end

function Needs.isWaterItem(item, allowTainted)
    local state = waterState(item)
    return state ~= nil and (allowTainted or not state.tainted)
end

function Needs.findBestWater(character, allowTainted)
    local best = nil
    walkInventory(character:getInventory(), function(item)
        local state = waterState(item)
        if state ~= nil and (allowTainted or not state.tainted) then
            if best == nil
                or (best.tainted and not state.tainted)
                or (best.tainted == state.tainted and state.amount > best.amount) then
                best = state
            end
        end
    end)
    return best ~= nil and best.item or nil, best ~= nil and best.tainted or false
end

function Needs.snapshot(character)
    local stats = character:getStats()
    return {
        hunger = stats:get(CharacterStat.HUNGER),
        thirst = stats:get(CharacterStat.THIRST),
        fatigue = stats:get(CharacterStat.FATIGUE),
        endurance = stats:get(CharacterStat.ENDURANCE),
        bleedingParts = character:getBodyDamage():getNumPartsBleeding(),
        health = character:getBodyDamage():getHealth(),
    }
end

function Needs.sleepRequired()
    if not isClient() then
        return true
    end
    local options = getServerOptions()
    return options:getBoolean("SleepAllowed") and options:getBoolean("SleepNeeded")
end

function Needs.describe(snapshot)
    return "hunger=" .. tostring(snapshot.hunger)
        .. " thirst=" .. tostring(snapshot.thirst)
        .. " fatigue=" .. tostring(snapshot.fatigue)
        .. " endurance=" .. tostring(snapshot.endurance)
        .. " bleedingParts=" .. tostring(snapshot.bleedingParts)
        .. " health=" .. tostring(snapshot.health)
end

function Needs.decide(character, threat)
    local state = Needs.snapshot(character)
    if threat ~= nil then
        return { kind = "fight", target = threat, state = state }
    end
    if state.bleedingParts >= Needs.thresholds.bleeding then
        local injury = KnoxMedicalActions.mostUrgentInjury(character)
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        if treatment ~= nil then
            return {
                kind = "bandage",
                item = treatment,
                bodyPart = injury,
                state = state,
            }
        end
        local supplyPlan = KnoxMedicalSupplies.plan(character, 8)
        local canImprovise = supplyPlan.kind == "rip_owned_sheet"
            or supplyPlan.kind == "rip_owned_spare_clothing"
        return {
            kind = canImprovise and "improvise_medical" or "find_medical",
            supplyPlan = supplyPlan,
            state = state,
        }
    end
    if state.thirst >= Needs.thresholds.thirst then
        local water, tainted = Needs.findBestWater(character, state.thirst >= 0.90)
        return {
            kind = water ~= nil and "drink" or "find_water",
            item = water,
            tainted = tainted,
            state = state,
        }
    end
    if state.hunger >= Needs.thresholds.hunger then
        local food = Needs.findBestFood(character)
        return {
            kind = food ~= nil and "eat" or "find_food",
            item = food,
            state = state,
        }
    end
    if state.endurance <= Needs.thresholds.lowEndurance then
        return { kind = "rest", state = state }
    end
    if state.fatigue >= Needs.thresholds.fatigue and Needs.sleepRequired() then
        return { kind = "sleep", state = state }
    end
    return { kind = "roam", state = state }
end

function Needs.execute(character, decision)
    if decision == nil then
        return nil, "missing_decision"
    end
    if decision.kind == "bandage" then
        local action, result = KnoxMedicalActions.queueBandage(
            character,
            decision.item,
            decision.bodyPart
        )
        return action, result, {
            kind = "bandage",
            before = decision.state,
            item = decision.item,
            bodyPart = decision.bodyPart,
        }
    end
    if decision.kind == "drink" or decision.kind == "eat" then
        local inventory, source = character:getInventory(), nil
        walkInventory(inventory, function(item, container)
            if item == decision.item then source = container end
        end)
        if source == nil then return nil, "supply_no_longer_carried" end
        if source ~= inventory then
            -- Native eating validates main-inventory ownership. Retrieving a
            -- bagged meal is a separate verified action, never consumption.
            local action, reason = KnoxInventoryActions.queueTransfer(
                character, decision.item, source, inventory)
            if not actionAccepted(character, action) then return nil, "supply_transfer_rejected" end
            return action, reason, { kind = "prepare_supply", needKind = decision.kind,
                before = decision.state, item = decision.item }
        end
    end
    if decision.kind == "drink" then
        local thirst = decision.state.thirst
        local uses = math.max(1, math.ceil(math.max(0, thirst - 0.15) / 0.1))
        local action = ISDrinkFromBottle:new(character, decision.item, uses)
        ISTimedActionQueue.add(action)
        if not actionAccepted(character, action) then return nil, "drink_queue_rejected" end
        return action, "queued_drink", {
            kind = "drink",
            before = decision.state,
            item = decision.item,
        }
    end
    if decision.kind == "eat" then
        local benefit = math.max(0.01, math.abs(decision.item:getHungerChange()))
        local percentage = math.max(
            0.25,
            math.min(1.0, math.max(0, decision.state.hunger - 0.15) / benefit)
        )
        local action = ISEatFoodAction:new(character, decision.item, percentage)
        ISTimedActionQueue.add(action)
        if not actionAccepted(character, action) then return nil, "eat_queue_rejected" end
        return action, "queued_eat percentage=" .. tostring(percentage), {
            kind = "eat",
            before = decision.state,
            item = decision.item,
        }
    end
    if decision.kind == "improvise_medical" then
        local action, result = KnoxMedicalSupplies.queueImprovisation(
            character,
            decision.supplyPlan
        )
        return action, result, {
            kind = "improvise_medical",
            before = decision.state,
            item = decision.supplyPlan ~= nil and decision.supplyPlan.item or nil,
        }
    end
    return nil, "decision_requires_world_action=" .. tostring(decision.kind)
end

-- An empty timed-action queue proves only that native ownership ended. These
-- checks prove that the authoritative game state actually changed before the
-- controller records self-care as successful.
function Needs.verify(character, intent)
    if character == nil or intent == nil or intent.before == nil then
        return false, "missing_intent"
    end
    local after = Needs.snapshot(character)
    if intent.kind == "prepare_supply" then
        return character:getInventory():contains(intent.item), "supply_main_inventory"
    end
    if intent.kind == "eat" then
        return after.hunger < intent.before.hunger - NEED_CHANGE_EPSILON,
            "hunger=" .. tostring(intent.before.hunger) .. "->" .. tostring(after.hunger)
    end
    if intent.kind == "drink" then
        return after.thirst < intent.before.thirst - NEED_CHANGE_EPSILON,
            "thirst=" .. tostring(intent.before.thirst) .. "->" .. tostring(after.thirst)
    end
    if intent.kind == "bandage" then
        local treated = intent.bodyPart ~= nil
            and (intent.bodyPart:bandaged() or not intent.bodyPart:bleeding())
        return treated,
            "bleedingParts=" .. tostring(intent.before.bleedingParts)
                .. "->" .. tostring(after.bleedingParts)
    end
    if intent.kind == "improvise_medical" then
        local treatment = KnoxMedicalSupplies.findTreatment(character)
        return treatment ~= nil, treatment ~= nil
            and "treatment_created=" .. tostring(treatment:getFullType())
            or "no_treatment_created"
    end
    return false, "unsupported_intent=" .. tostring(intent.kind)
end

function Needs.verifyRecovery(character, intent)
    if character == nil or intent == nil or intent.before == nil then
        return false, "missing_recovery_intent"
    end
    local after = Needs.snapshot(character)
    if intent.kind == "rest" then
        return after.endurance > intent.before.endurance + NEED_CHANGE_EPSILON,
            "endurance=" .. tostring(intent.before.endurance)
                .. "->" .. tostring(after.endurance)
    end
    if intent.kind == "sleep" then
        return after.fatigue < intent.before.fatigue - NEED_CHANGE_EPSILON,
            "fatigue=" .. tostring(intent.before.fatigue)
                .. "->" .. tostring(after.fatigue)
    end
    return false, "unsupported_recovery=" .. tostring(intent.kind)
end

function Needs.sleepHours(character, fatigue)
    local value = tonumber(fatigue) or 0
    local hours = math.floor(value * 10) + 1
    if character:hasTrait(CharacterTrait.INSOMNIAC) then
        hours = math.floor(hours * 0.5)
    end
    if character:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) then
        hours = math.floor(hours * 0.75)
    end
    if character:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) then
        hours = math.ceil(hours * 1.18)
    end
    return math.max(3, math.min(16, hours))
end

-- This is the same native sleep transition used by Build 42's world context
-- menu, without touching local-player UI or time controls for the off-slot NPC.
function Needs.startSleep(character, bed, bedType)
    if character == nil or character:isAsleep() then
        return false, "sleep_unavailable"
    end
    local state = Needs.snapshot(character)
    local hours = Needs.sleepHours(character, state.fatigue)
    local wakeAt = GameTime.getInstance():getTimeOfDay() + hours
    if wakeAt >= 24 then
        wakeAt = wakeAt - 24
    end
    character:setVariable("ExerciseStarted", false)
    character:setVariable("ExerciseEnded", true)
    character:setBed(bed)
    character:setBedType(bedType or (bed ~= nil and "averageBed" or "floor"))
    character:setForceWakeUpTime(wakeAt)
    character:setAsleepTime(0.0)
    character:setAsleep(true)
    getSleepingEvent():setPlayerFallAsleep(character, hours)
    return true, "native_sleep hours=" .. tostring(hours)
end

function Needs.wakeForDanger(character)
    if character == nil or not character:isAsleep() then
        return false
    end
    getSleepingEvent():wakeUp(character)
    return true
end
