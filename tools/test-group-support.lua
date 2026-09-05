local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.preload.KS_SurvivorNeeds = function() return true end
package.preload.KS_SurvivorInventoryActions = function() return true end

local function list(values)
    return {
        values = values,
        size = function(self) return #self.values end,
        get = function(self, index) return self.values[index + 1] end,
    }
end

local function inventory(values)
    local result = { values = values or {} }
    function result:getItems() return list(self.values) end
    function result:contains(item)
        for _, value in ipairs(self.values) do if value == item then return true end end
        return false
    end
    return result
end

local function item(name, kind, value)
    local result = { name = name, kind = kind, value = value or 1 }
    function result:getFullType() return self.name end
    function result:getContainer() return self.container end
    function result:IsInventoryContainer() return false end
    function result:isFavorite() return false end
    function result:isCanBandage() return self.kind == "medical" end
    function result:getBandagePower() return self.kind == "medical" and self.value or 0 end
    function result:getHungerChange() return self.kind == "food" and -self.value or 0 end
    function result:getFluidContainer()
        return self.kind == "water" and {
            getAmount = function() return self.value end,
        } or nil
    end
    return result
end

local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z or 0 end }
end

local function character(name, x, need, state, values)
    local bag = inventory(values)
    local result = { name = name, need = need, needState = state, bag = bag,
        square = square(x, 0, 0) }
    function result:getInventory() return self.bag end
    function result:getCurrentSquare() return self.square end
    function result:isDead() return false end
    function result:isEquipped() return false end
    for _, value in ipairs(values or {}) do value.container = bag end
    return result
end

KnoxSurvivorNeeds = {
    decide = function(character)
        return { kind = character.need or "roam", state = character.needState or {} }
    end,
    snapshot = function(character) return character.needState or {} end,
    isSafeFood = function(value) return value.kind == "food" end,
    isWaterItem = function(value) return value.kind == "water" end,
}

local queued = nil
KnoxInventoryActions = {
    queueTransfer = function(donor, value, source, destination)
        queued = { donor = donor, item = value, source = source, destination = destination }
        return {}, "queued"
    end,
}

local Support = require "KS_GroupSupport"
local foodA, foodB = item("Base.Apple", "food", .2), item("Base.Soup", "food", .5)
local waterA, waterB = item("Base.WaterBottle", "water", .5),
    item("Base.WaterBottleFull", "water", 1)
local bandageA, bandageB = item("Base.Bandage", "medical", 2),
    item("Base.AlcoholBandage", "medical", 4)
local donor = character("donor", 0, nil, {}, {
    foodA, foodB, waterA, waterB, bandageA, bandageB,
})
local hungry = character("hungry", 2, "find_food", { hunger = .8 }, {})
local thirsty = character("thirsty", 2, "find_water", { thirst = .9 }, {})
local bleeding = character("bleeding", 2, "find_medical", { bleedingParts = 1 }, {})

local plan = assert(Support.plan(donor, { hungry, thirsty, bleeding }, {}, {}))
assert(plan.recipient == bleeding and plan.kind == "find_medical"
    and plan.item == bandageB, "bleeding ally receives the highest-priority useful spare")
assert(Support.queue(donor, plan) ~= nil and queued.destination == bleeding.bag,
    "support uses the existing native inventory-transfer queue")
table.remove(donor.bag.values, 6)
bleeding.bag.values[1] = bandageB
assert(Support.verify(plan), "real source/destination state verifies completion")
local groupNeed = assert(Support.mostUrgentNeed(donor, { hungry, thirsty, bleeding }))
assert(groupNeed.recipient == bleeding and groupNeed.kind == "find_medical",
    "leader sees the group's most urgent nearby shortage")

local medicalOnly = character("medical-only", 0, nil, {}, { bandageA })
assert(Support.findSafeSurplus(medicalOnly, "find_medical") == nil,
    "last carried treatment remains protected")
local hungryDonor = character("hungry-donor", 0, "find_food", { hunger = .8 },
    { foodA, foodB })
assert(Support.findSafeSurplus(hungryDonor, "find_food") == nil,
    "a donor with the same need protects an additional reserve")
assert(Support.plan(donor, {
    character("far", 4, "find_water", { thirst = 1 }, {}),
}, {}, {}) == nil, "support does not transfer across an implausible distance")
thirsty.square = square(1, 0, 1)
assert(Support.plan(donor, { thirsty }, {}, {}) == nil,
    "support does not transfer through floors")
assert(Support.plan(donor, { hungry }, { [hungry] = "other" }, {}) == nil,
    "recipient reservation prevents duplicate gifts")

print("Group support PASS priority=true reserves=true native_transfer=true range=true reservation=true")
