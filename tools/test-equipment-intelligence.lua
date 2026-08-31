local rootPath = arg[1] or "."

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(fullType, options)
    options = options or {}
    return {
        fullType = fullType,
        weapon = options.weapon,
        ranged = options.ranged,
        broken = options.broken,
        location = options.location,
        capacity = options.capacity,
        reduction = options.reduction,
        bite = options.bite,
        scratch = options.scratch,
        insulation = options.insulation,
        condition = options.condition or 10,
        conditionMax = options.conditionMax or 10,
        minDamage = options.minDamage or 0,
        maxDamage = options.maxDamage or 0,
        range = options.range or 0,
        speed = options.speed or 0,
        critical = options.critical or 0,
        IsWeapon = function(self) return self.weapon == true end,
        isRanged = function(self) return self.ranged == true end,
        isBroken = function(self) return self.broken == true end,
        getCondition = function(self) return self.condition end,
        getConditionMax = function(self) return self.conditionMax end,
        getMinDamage = function(self) return self.minDamage end,
        getMaxDamage = function(self) return self.maxDamage end,
        getMaxRange = function(self) return self.range end,
        getBaseSpeed = function(self) return self.speed end,
        getCriticalChance = function(self) return self.critical end,
        IsInventoryContainer = function(self) return self.capacity ~= nil end,
        IsClothing = function(self) return self.bite ~= nil end,
        getCapacity = function(self) return self.capacity or 0 end,
        getWeightReduction = function(self) return self.reduction or 0 end,
        getBodyLocation = function(self) return self.location end,
        canBeEquipped = function(self) return self.location end,
        getBiteDefense = function(self) return self.bite or 0 end,
        getScratchDefense = function(self) return self.scratch or 0 end,
        getInsulation = function(self) return self.insulation or 0 end,
        getFullType = function(self) return self.fullType end,
    }
end

local weak = item("Base.KitchenKnife", { weapon = true, minDamage = 0.4, maxDamage = 0.8, range = 0.8 })
local strong = item("Base.BaseballBat", { weapon = true, minDamage = 1.0, maxDamage = 1.6, range = 1.2 })
local broken = item("Base.BrokenAxe", { weapon = true, broken = true, minDamage = 4, maxDamage = 5 })
local gun = item("Base.Pistol", { weapon = true, ranged = true, minDamage = 1, maxDamage = 2 })
local smallBag = item("Base.Bag_Small", { location = "Back", capacity = 6, reduction = 20 })
local largeBag = item("Base.Bag_Large", { location = "Back", capacity = 18, reduction = 60 })
local thinShirt = item("Base.Tshirt", { location = "Torso", bite = 1, scratch = 2, insulation = 0.1 })
local jacket = item("Base.Jacket", { location = "Torso", bite = 8, scratch = 12, insulation = 0.6 })
local unknown = { getFullType = function() return "Mod.Unknown" end }
local javaNull = setmetatable({}, { __tostring = function() return "null" end })

local character = { primary = weak, worn = { Back = smallBag, Torso = thinShirt }, actions = false }
character.inventory = { getItems = function()
    return list({ weak, javaNull, strong, broken, gun, largeBag, jacket, unknown })
end }
function character:getInventory() return self.inventory end
function character:getPrimaryHandItem() return self.primary end
function character:getWornItem(location) return self.worn[location] end
function character:getCharacterActions() return { isEmpty = function() return not character.actions end } end

local weaponEquips, wearEquips = 0, 0
local bridge = {
    equipNpcOwnedWeapon = function(_, id, fullType)
        assert(id == "gear")
        for _, candidate in ipairs({ weak, strong, broken, gun }) do
            if candidate.fullType == fullType then character.primary = candidate end
        end
        weaponEquips = weaponEquips + 1
        return "EQUIPPED_WEAPON " .. fullType
    end,
    wearNpcOwnedItem = function(_, id, fullType)
        assert(id == "gear")
        for _, candidate in ipairs({ largeBag, jacket }) do
            if candidate.fullType == fullType then character.worn[candidate.location] = candidate end
        end
        wearEquips = wearEquips + 1
        return "WORN_OWNED " .. fullType
    end,
}

local equipment = dofile(rootPath .. "/mod/42/media/lua/client/KS_EquipmentIntelligence.lua")
local firstDecision = equipment.choose(character)
assert(firstDecision ~= nil and firstDecision.kind == "melee",
    "better melee must be considered before worn upgrades: "
        .. tostring(firstDecision ~= nil and firstDecision.kind or "nil"))
local changed, firstResult = equipment.reconsider("gear", character, bridge, 0, true)
assert(changed and character.primary == strong and weaponEquips == 1,
    "better usable melee beats weak and broken alternatives: " .. tostring(firstResult))
local changedAgain, stable = equipment.reconsider("gear", character, bridge, 1, false)
assert(not changedAgain and stable == "equipment_cooldown" and weaponEquips == 1,
    "same equipment is not repeatedly reequiped")
changed = assert(select(1, equipment.reconsider("gear", character, bridge, 300, true)))
assert(changed and character.worn.Back == largeBag and wearEquips == 1,
    "meaningful backpack upgrade uses owned-item wear bridge")
changed = assert(select(1, equipment.reconsider("gear", character, bridge, 600, true)))
assert(changed and character.worn.Torso == jacket and wearEquips == 2,
    "meaningful protective clothing upgrade is selected once")
assert(equipment.choose(character) == nil,
    "equipped best gear remains stable")

character.primary = gun
local decision = equipment.choose(character)
assert(decision == nil, "usable firearm is not displaced by idle melee evaluation")

local tinyBag = item("Base.Bag_TinyUpgrade", { location = "Back", capacity = 18.2, reduction = 60 })
character.inventory = { getItems = function() return list({ tinyBag }) end }
assert(equipment.choose(character) == nil, "tiny container improvement does not cause gear thrash")

local safe, result = pcall(function()
    character.inventory = { getItems = function() return list({ unknown }) end }
    return equipment.choose(character)
end)
assert(safe and result == nil, "unknown/modded inventory item classification never throws")

safe, result = pcall(function()
    character.inventory = { getItems = function() return list({ javaNull }) end }
    return equipment.choose(character)
end)
assert(safe and result == nil, "Java null sentinel in an inventory list never throws")

local registryPath = rootPath .. "/java/src/main/java/com/knoxsurvivors/npc/KnoxNpcRegistry.java"
local trousers = item("Base.Trousers_Fireman", { location = "Pants", bite = 20, scratch = 40 })
local shorts = item("Base.Shorts_ShortFormal", { location = "Shorts", bite = 0, scratch = 0 })
character.worn = { Pants = trousers }
function character:getWornItems()
    local entries = {}
    for location, worn in pairs(self.worn) do
        entries[#entries + 1] = { getLocation = function() return location end,
            getItem = function() return worn end }
    end
    local result = list(entries)
    result.getBodyLocationGroup = function() return { isExclusive = function(_, a, b)
        return a == "Pants" and b == "Shorts" or a == "Shorts" and b == "Pants"
    end } end
    return result
end
character.inventory = { getItems = function() return list({ trousers, shorts }) end }
assert(equipment.choose(character) == nil, "inferior exclusive shorts cannot replace protective trousers")
character.worn = { Shorts = shorts }
assert(equipment.choose(character).item == trousers, "meaningful exclusive-slot upgrade is selected")
character.worn = { Pants = trousers }
assert(equipment.choose(character) == nil, "exclusive clothing upgrade does not oscillate")
character.getWornItems = function() error("unknown modded location") end
assert(equipment.choose(character) == nil, "unreadable worn-slot metadata must not throw or assume an empty slot")

local registry = assert(io.open(registryPath, "r")):read("*a")
assert(registry:find('if %(!"NO_MELEE_WEAPON"%.equals%(result%)%)', 1) ~= nil,
    "the normal unarmed result must not create repeated equipment log noise")

print("Equipment intelligence PASS melee=true broken=true bags=true clothing=true stable=true unknown_safe=true java_null_safe=true unarmed_log_quiet=true")
