require "KS_Settings"
local Cupboard = {}
KnoxToolCupboard = Cupboard

-- Build 42.20.3 enforces 100 for ordinary world ItemContainers.  A vehicle
-- container can use the larger native vehicle limit; nested item containers
-- have the smaller native bag limit.  Never ask the engine to apply a value it
-- will reject and warn about.
local WORLD_CONTAINER_MAX = 100
local BAG_CONTAINER_MAX = 50
local VEHICLE_CONTAINER_MAX = 1000

function Cupboard.nativeCapacityLimit(container)
    if container == nil then return WORLD_CONTAINER_MAX end
    if container.isVehiclePart ~= nil then
        local ok, vehiclePart = pcall(container.isVehiclePart, container)
        if ok and vehiclePart == true then return VEHICLE_CONTAINER_MAX end
    end
    if container.getContainingItem ~= nil then
        local ok, containingItem = pcall(container.getContainingItem, container)
        if ok and containingItem ~= nil then return BAG_CONTAINER_MAX end
    end
    return WORLD_CONTAINER_MAX
end

function Cupboard.effectiveCapacity(container)
    local requested = KnoxSettings.toolCupboardCapacity()
    return math.max(1, math.min(requested, Cupboard.nativeCapacityLimit(container)))
end

function Cupboard.isDryContainerType(containerType)
    local kind = string.lower(tostring(containerType or "container"))
    return kind ~= "corpse" and not kind:find("fridge", 1, true)
        and not kind:find("freezer", 1, true) and not kind:find("water", 1, true)
        and not kind:find("rain", 1, true)
end

function Cupboard.apply(object, container, key)
    local data = object ~= nil and object.getModData ~= nil and object:getModData() or nil
    local marker = data ~= nil and data.KnoxToolCupboard or nil
    if type(marker) ~= "table" or marker.key ~= key or container == nil
        or container.setCapacity == nil then return false end
    local capacity = Cupboard.effectiveCapacity(container)
    if container:getCapacity() ~= capacity then container:setCapacity(capacity) end
    return true
end

-- Assigned storage areas use the native maximum plus a Lua/native bypass for
-- true infinite weight. The engine caps ordinary world containers at 100, so
-- we set that max for display and mark the container infinite for bypasses.
function Cupboard.applyInfinite(object, container, key)
    if object == nil or container == nil or container.setCapacity == nil then return false end
    local capacity = Cupboard.nativeCapacityLimit(container)
    local ok = pcall(function()
        if container:getCapacity() ~= capacity then container:setCapacity(capacity) end
    end)
    local data = object.getModData ~= nil and object:getModData() or nil
    if data ~= nil then
        data.KnoxInfiniteStorage = data.KnoxInfiniteStorage or {}
        data.KnoxInfiniteStorage[tostring(key or "assigned")] = true
        if object.transmitModData ~= nil then
            pcall(function() object:transmitModData() end)
        end
    end
    return ok
end

function Cupboard.isInfiniteContainer(container)
    if container == nil then return false end
    -- World containers expose their parent object; bags expose containing item.
    -- Assigned storage is marked via parent modData, or via maxed capacity + custom name.
    local parent = nil
    if container.getParent ~= nil then
        local ok, value = pcall(function() return container:getParent() end)
        if ok then parent = value end
    end
    if parent ~= nil and parent.getModData ~= nil then
        local ok, data = pcall(function() return parent:getModData() end)
        if ok and data ~= nil then
            if data.KnoxInfiniteStorage ~= nil then return true end
            local ks = data.KnoxSurvivors
            if ks ~= nil and ks.storageIds ~= nil then
                for _ in pairs(ks.storageIds) do return true end
            end
            if data.KnoxToolCupboard ~= nil then return true end
        end
    end
    return false
end

function Cupboard.designate(base, object, containerIndex, manager)
    -- Main Supplies retired: typed storages set via other menus are canonical.
    -- Kept for legacy saves; always fails for new assignments.
    return nil, "main_supplies_retired"
end
return Cupboard
