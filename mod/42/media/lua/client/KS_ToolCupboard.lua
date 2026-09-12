require "KS_Settings"
local Cupboard = {}
KnoxToolCupboard = Cupboard

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
    local capacity = KnoxSettings.toolCupboardCapacity()
    if container:getCapacity() ~= capacity then container:setCapacity(capacity) end
    return true
end

function Cupboard.designate(base, object, containerIndex, manager)
    if base == nil or object == nil or not manager.containsSquare(base, object:getSquare()) then
        return nil, "outside_base"
    end
    local container = object:getContainerByIndex(containerIndex or 0)
    if container == nil or container.setCapacity == nil then return nil, "not_a_container" end
    local kind = string.lower(tostring(container:getType() or ""))
    if not Cupboard.isDryContainerType(kind) then return nil, "use_dry_storage" end
    local reference = manager.containerReference(object, containerIndex, base.id)
    if reference == nil then return nil, "not_a_container" end
    local oldResolved, oldPolicy
    if base.toolCupboardKey ~= nil and base.toolCupboardKey ~= reference.key then
        local storage = rawget(_G, "KnoxBaseStorage")
        local previous = base.storage ~= nil and base.storage[base.toolCupboardKey] or nil
        if storage == nil or previous == nil then return nil, "base_already_has_cupboard" end
        local resolved, reason = storage.resolvePolicy(previous)
        -- An unloaded cupboard may still contain supplies. Never replace its
        -- ownership until its actual world object can be checked.
        if resolved == nil and reason ~= "storage_object_missing" then
            return nil, "visit_existing_cupboard_first"
        end
        if resolved ~= nil then
            local oldData = resolved.object:getModData()
            local marker = oldData.KnoxToolCupboard
            if type(marker) ~= "table" or marker.key ~= previous.key then
                return nil, "cupboard_identity_mismatch"
            end
        end
        oldResolved, oldPolicy = resolved, previous
    end
    local policy, reason = manager.setStoragePolicy(base.id, object, "depot", containerIndex)
    if policy == nil then return nil, reason end
    -- Do not retire the current cupboard until the replacement policy has
    -- actually been accepted. A rejected assignment must leave it usable.
    if oldResolved ~= nil then
        local oldData = oldResolved.object:getModData()
        oldResolved.container:setCapacity(tonumber(oldData.KnoxToolCupboard.originalCapacity) or 40)
        oldData.KnoxToolCupboard = nil
        if oldResolved.object.transmitModData ~= nil then oldResolved.object:transmitModData() end
    end
    if oldPolicy ~= nil then oldPolicy.toolCupboard = false end
    local data = object:getModData()
    local previous = data.KnoxToolCupboard
    data.KnoxToolCupboard = { key = policy.key, baseId = base.id,
        originalCapacity = type(previous) == "table" and previous.key == policy.key
            and previous.originalCapacity or container:getCapacity() }
    base.toolCupboardKey = policy.key
    local retained = { [policy.key] = policy }
    for otherKey, other in pairs(base.storage or {}) do
        if otherKey ~= policy.key and other.storageRole == "food" then retained[otherKey] = other end
    end
    base.storage = retained
    policy.storageRole, policy.toolCupboard = "supplies", true
    Cupboard.apply(object, container, policy.key)
    if object.transmitModData ~= nil then object:transmitModData() end
    return policy, "cupboard_ready"
end
return Cupboard
