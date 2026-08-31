local projectRoot = arg[1] or "."

require = function() return true end

CharacterStat = {
    HUNGER = "hunger",
    THIRST = "thirst",
    FATIGUE = "fatigue",
    ENDURANCE = "endurance",
}
CharacterTrait = {
    INSOMNIAC = "insomniac",
    NEEDS_LESS_SLEEP = "lessSleep",
    NEEDS_MORE_SLEEP = "moreSleep",
}
Fluid = { TaintedWater = "tainted" }
isClient = function() return false end

local queued = {}
ISTimedActionQueue = {
    add = function(action) queued[#queued + 1] = action end,
}
ISEatFoodAction = {
    new = function(_, character, item, percentage)
        return { character = character, item = item, percentage = percentage }
    end,
}
ISDrinkFromBottle = {
    new = function(_, character, item, uses)
        return { character = character, item = item, uses = uses }
    end,
}

local treatment = nil
local injury = nil
KnoxMedicalActions = {
    mostUrgentInjury = function() return injury end,
    queueBandage = function(character, item, bodyPart)
        local action = { character = character, item = item, bodyPart = bodyPart }
        ISTimedActionQueue.add(action)
        return action, "queued"
    end,
}
KnoxMedicalSupplies = {
    findTreatment = function() return treatment end,
    plan = function() return { kind = "search_world" } end,
    queueImprovisation = function() return false, "unavailable" end,
}

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function inventory(values)
    return {
        getItems = function() return list(values) end,
        contains = function(_, target)
            for _, value in ipairs(values) do
                if value == target then return true end
            end
            return false
        end,
    }
end

local function food(name, hunger, options)
    options = options or {}
    return {
        getFullType = function() return name end,
        IsFood = function() return true end,
        IsInventoryContainer = function() return false end,
        getFluidContainer = function() return nil end,
        getHungerChange = function() return hunger end,
        getUnhappyChange = function() return options.unhappy or 0 end,
        isRotten = function() return options.rotten == true end,
        isPoison = function() return options.poison == true end,
        getPoisonPower = function() return options.poisonPower or 0 end,
        isbDangerousUncooked = function() return options.dangerous == true end,
        isCooked = function() return options.cooked == true end,
    }
end

local function water(name, amount, tainted)
    local fluid = {
        isEmpty = function() return amount <= 0 end,
        isWaterSource = function() return true end,
        contains = function(_, kind) return kind == Fluid.TaintedWater and tainted end,
        getAmount = function() return amount end,
    }
    return {
        getFullType = function() return name end,
        IsFood = function() return false end,
        IsInventoryContainer = function() return false end,
        getFluidContainer = function() return fluid end,
    }
end

local statsValues = {
    hunger = 0,
    thirst = 0,
    fatigue = 0,
    endurance = 1,
}
local bleedingParts = 0
local health = 100
local asleep = false
local bed = nil
local bedType = nil
local traits = {}
local carried = {}
local bodyDamage = {
    getNumPartsBleeding = function() return bleedingParts end,
    getHealth = function() return health end,
}
local character = {
    getInventory = function() return inventory(carried) end,
    getStats = function()
        return { get = function(_, key) return statsValues[key] end }
    end,
    getBodyDamage = function() return bodyDamage end,
    hasTrait = function(_, trait) return traits[trait] == true end,
    isAsleep = function() return asleep end,
    setAsleep = function(_, value) asleep = value end,
    setAsleepTime = function() end,
    setForceWakeUpTime = function() end,
    setVariable = function() end,
    setBed = function(_, value) bed = value end,
    setBedType = function(_, value) bedType = value end,
}

GameTime = {
    getInstance = function()
        return { getTimeOfDay = function() return 20 end }
    end,
}
local sleepStarted = 0
local woke = 0
getSleepingEvent = function()
    return {
        setPlayerFallAsleep = function(_, _, hours) sleepStarted = hours end,
        wakeUp = function()
            woke = woke + 1
            asleep = false
        end,
    }
end

local modulePath = projectRoot .. "/mod/42/media/lua/client/KS_SurvivorNeeds.lua"
assert(loadfile(modulePath))()
local Needs = assert(KnoxSurvivorNeeds)

local meal = food("Base.Beans", -0.40)
local rotten = food("Base.Rotten", -0.80, { rotten = true })
local bottle = water("Base.WaterBottle", 0.8, false)
local badWater = water("Base.TaintedBottle", 1.0, true)
carried = { rotten, meal, badWater, bottle }

statsValues.hunger = 0.54
statsValues.thirst = 0.54
assert(Needs.decide(character, nil).kind == "roam",
    "sub-threshold hunger and thirst do not trigger robotic self-care")

statsValues.hunger = 0.80
statsValues.thirst = 0.85
assert(Needs.decide(character, {}).kind == "fight",
    "immediate danger outranks critical carried-resource needs")

bleedingParts = 1
injury = {
    bandaged = function() return false end,
    bleeding = function() return true end,
}
treatment = { getFullType = function() return "Base.Bandage" end }
assert(Needs.decide(character, nil).kind == "bandage",
    "bleeding treatment outranks thirst and hunger")

bleedingParts = 0
treatment = nil
local decision = Needs.decide(character, nil)
assert(decision.kind == "drink" and decision.item == bottle,
    "critical thirst selects clean carried water before hunger")
local action, _, intent = Needs.execute(character, decision)
assert(action ~= nil and intent.kind == "drink" and #queued == 1,
    "drink queues one native action with explicit ownership intent")
assert(not Needs.verify(character, intent),
    "empty queue without a real thirst change is not completion")
statsValues.thirst = 0.35
assert(Needs.verify(character, intent),
    "real native thirst reduction verifies completion")

statsValues.thirst = 0.20
decision = Needs.decide(character, nil)
assert(decision.kind == "eat" and decision.item == meal,
    "safe carried food is selected while rotten food is rejected")
action, _, intent = Needs.execute(character, decision)
statsValues.hunger = 0.40
assert(action ~= nil and Needs.verify(character, intent),
    "real native hunger reduction verifies eating")

carried = {}
statsValues.thirst = 0.80
assert(Needs.decide(character, nil).kind == "find_water",
    "missing carried water fails into the existing bounded world-search decision")

statsValues.thirst = 0
statsValues.hunger = 0
statsValues.endurance = 0.2
assert(Needs.decide(character, nil).kind == "rest",
    "low endurance requests safe native rest")
local restIntent = { kind = "rest", before = Needs.snapshot(character) }
statsValues.endurance = 0.5
assert(Needs.verifyRecovery(character, restIntent),
    "endurance recovery must change the real stat")

statsValues.endurance = 1
statsValues.fatigue = 0.8
assert(Needs.decide(character, nil).kind == "sleep",
    "meaningful fatigue requests native sleep when sleep is required")
local started = Needs.startSleep(character, nil, "floor")
assert(started and asleep and sleepStarted >= 3 and bed == nil and bedType == "floor",
    "sleep uses the native off-slot sleeping event without local-player UI")
assert(Needs.wakeForDanger(character) and not asleep and woke == 1,
    "immediate danger wakes native sleep")

print("Survivor needs PASS priority=true resources=true verification=true sleep=true")
