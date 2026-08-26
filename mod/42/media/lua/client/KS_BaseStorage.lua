require "KS_Persistence"
require "KS_SurvivorNeeds"
require "KS_SurvivorInventoryActions"

local Storage = rawget(_G, "KnoxBaseStorage") or {}
_G.KnoxBaseStorage = Storage

local MEDICAL_TYPES = {
    ["Base.AlcoholWipes"] = true,
    ["Base.BottleDisinfectant"] = true,
    ["Base.Pills"] = true,
    ["Base.PillsAntiDep"] = true,
    ["Base.PillsBeta"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.SutureNeedle"] = true,
    ["Base.Tweezers"] = true,
}

local TOOL_TYPES = {
    ["Base.Axe"] = true,
    ["Base.HandAxe"] = true,
    ["Base.Hammer"] = true,
    ["Base.Saw"] = true,
    ["Base.Screwdriver"] = true,
    ["Base.Wrench"] = true,
    ["Base.LugWrench"] = true,
    ["Base.Jack"] = true,
    ["Base.TirePump"] = true,
}

local BUILDING_TYPES = {
    ["Base.Plank"] = true,
    ["Base.SheetMetal"] = true,
    ["Base.SmallSheetMetal"] = true,
    ["Base.Nails"] = true,
    ["Base.Woodglue"] = true,
    ["Base.Screws"] = true,
    ["Base.DuctTape"] = true,
}

local FARMING_TYPES = {
    ["Base.WateredCan"] = true,
    ["Base.WaterCan"] = true,
    ["Base.HandShovel"] = true,
    ["Base.GardeningSprayEmpty"] = true,
    ["Base.Fertilizer"] = true,
}

local function fullType(item)
    if item == nil or item.getFullType == nil then
        return ""
    end
    return tostring(item:getFullType() or "")
end

local function safeBoolean(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    return success and value == true or nil
end

function Storage.resolvePolicy(policy)
    if policy == nil or getCell == nil or getCell() == nil then
        return nil, "cell_unavailable"
    end
    local square = getCell():getGridSquare(
        tonumber(policy.x) or 0,
        tonumber(policy.y) or 0,
        tonumber(policy.z) or 0
    )
    if square == nil or square.getObjects == nil then
        return nil, "storage_square_unloaded"
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local objectIndex = object ~= nil and object:getObjectIndex() or -1
        if object ~= nil and objectIndex == tonumber(policy.objectIndex) then
            local containerIndex = tonumber(policy.containerIndex) or 0
            local container = object:getContainerByIndex(containerIndex)
            if container ~= nil and container:isExistYet() then
                local actualType = tostring(container:getType() or "container")
                local expectedType = tostring(policy.containerType or actualType)
                if expectedType == actualType or expectedType == "container" then
                    return {
                        policy = policy,
                        square = square,
                        object = object,
                        container = container,
                    }, "resolved"
                end
            end
        end
    end
    return nil, "storage_object_unloaded"
end

function Storage.policies(base)
    local policies = {}
    for _, policy in pairs(base ~= nil and base.storage or {}) do
        if policy ~= nil and type(policy.key) == "string" then
            policies[#policies + 1] = policy
        end
    end
    table.sort(policies, function(first, second)
        return tostring(first.key) < tostring(second.key)
    end)
    return policies
end

local function hasPrefix(value, prefix)
    return string.sub(value, 1, #prefix) == prefix
end

function Storage.matchesCategory(item, category)
    if item == nil then
        return false
    end
    local full = fullType(item)
    category = tostring(category or "general")
    if category == "general" then
        return true
    end
    if category == "food" then
        return KnoxSurvivorNeeds.isSafeFood(item)
    end
    if category == "water" then
        return KnoxSurvivorNeeds.isWaterItem(item, false)
    end
    if category == "medical" then
        return (item.isCanBandage ~= nil and item:isCanBandage())
            or MEDICAL_TYPES[full] == true
    end
    if category == "weapons" then
        return item.IsWeapon ~= nil and item:IsWeapon()
    end
    if category == "ammunition" then
        return safeBoolean(item, "isAmmo") == true
            or hasPrefix(full, "Base.Bullets")
            or hasPrefix(full, "Base.ShotgunShells")
    end
    if category == "tools" then
        return TOOL_TYPES[full] == true
    end
    if category == "building" then
        return BUILDING_TYPES[full] == true
    end
    if category == "farming" then
        return FARMING_TYPES[full] == true
            or hasPrefix(full, "Base.Seed")
            or hasPrefix(full, "Base.Fertilizer")
    end
    if category == "clothing" then
        return item.IsClothing ~= nil and item:IsClothing()
            or item.IsInventoryContainer ~= nil and item:IsInventoryContainer()
    end
    return false
end

local function hasRoom(container, item)
    if container == nil then
        return false
    end
    if container.hasRoomFor ~= nil then
        local success, result = pcall(function()
            return container:hasRoomFor(item)
        end)
        if success and result == false then
            return false
        end
    end
    return true
end

local function firstMatchingItem(container, category)
    if container == nil or container:getItems() == nil then
        return nil
    end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if Storage.matchesCategory(item, category) then
            return item
        end
    end
    return nil
end

function Storage.findTransfer(base)
    local policies = Storage.policies(base)
    local depots = {}
    local destinations = {}
    for _, policy in ipairs(policies) do
        if policy.depot == true or policy.category == "depot" then
            depots[#depots + 1] = policy
        elseif policy.category ~= nil and policy.category ~= "general" then
            destinations[#destinations + 1] = policy
        end
    end
    for _, sourcePolicy in ipairs(depots) do
        local source = Storage.resolvePolicy(sourcePolicy)
        if source ~= nil then
            local items = source.container:getItems()
            for index = 0, items:size() - 1 do
                local item = items:get(index)
                for _, destinationPolicy in ipairs(destinations) do
                    if Storage.matchesCategory(item, destinationPolicy.category) then
                        local destination = Storage.resolvePolicy(destinationPolicy)
                        if destination ~= nil and destination.container ~= source.container
                            and hasRoom(destination.container, item) then
                            return {
                                sourcePolicy = sourcePolicy,
                                destinationPolicy = destinationPolicy,
                                source = source,
                                destination = destination,
                                item = item,
                                itemType = fullType(item),
                                category = destinationPolicy.category,
                            }, "found"
                        end
                    end
                end
            end
        end
    end
    return nil, "no_matching_depot_item"
end

function Storage.transferTarget(transfer)
    if transfer == nil or transfer.sourcePolicy == nil
        or transfer.destinationPolicy == nil then
        return nil
    end
    return {
        id = "sort-depot:" .. tostring(transfer.sourcePolicy.key)
            .. ":" .. tostring(transfer.destinationPolicy.key),
        auto = true,
        zoneType = "sort_depot",
        sourceKey = transfer.sourcePolicy.key,
        destinationKey = transfer.destinationPolicy.key,
        itemType = transfer.itemType,
        category = transfer.category,
        x = transfer.source.square:getX(),
        y = transfer.source.square:getY(),
        z = transfer.source.square:getZ(),
    }
end

function Storage.resolveTransfer(base, target)
    if target == nil then
        return nil, "missing_transfer_target"
    end
    local sourcePolicy = base ~= nil and base.storage[target.sourceKey] or nil
    local destinationPolicy = base ~= nil and base.storage[target.destinationKey] or nil
    if sourcePolicy == nil or destinationPolicy == nil then
        return nil, "storage_policy_missing"
    end
    local source, sourceResult = Storage.resolvePolicy(sourcePolicy)
    local destination, destinationResult = Storage.resolvePolicy(destinationPolicy)
    if source == nil or destination == nil then
        return nil, source == nil and sourceResult or destinationResult
    end
    local items = source.container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if fullType(item) == tostring(target.itemType or "")
            and Storage.matchesCategory(item, target.category)
            and hasRoom(destination.container, item) then
            return {
                source = source,
                destination = destination,
                item = item,
                itemType = fullType(item),
                category = target.category,
            }, "resolved"
        end
    end
    return nil, "item_no_longer_available"
end

function Storage.queueTransfer(character, transfer)
    if character == nil or transfer == nil then
        return nil, "missing_transfer"
    end
    local parent = transfer.source.container:getParent()
    if parent ~= nil then
        character:faceThisObject(parent)
        if character:shouldBeTurning() then
            return nil, "turning_to_storage"
        end
    end
    return KnoxInventoryActions.queueTransfer(
        character,
        transfer.item,
        transfer.source.container,
        transfer.destination.container,
        nil
    )
end

return Storage
