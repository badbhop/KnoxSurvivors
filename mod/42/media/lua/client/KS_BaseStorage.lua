require "KS_Persistence"
require "KS_ToolCupboard"
require "KS_BaseSupplyPlanner"
require "KS_SurvivorNeeds"
require "KS_SurvivorInventoryActions"
require "Util/AdjacentFreeTileFinder"

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

-- Keep the base-facing categories deliberately small and aligned with the storage
-- context menu.  A summary is only a view of loaded world containers; it never
-- becomes a second inventory or a source of simulated supplies.
Storage.RESOURCE_CATEGORIES = {
    "food",
    "water",
    "medical",
    "weapons",
    "ammunition",
    "tools",
    "building",
    "farming",
    "clothing",
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
        local stablePolicy = type(policy.key) == "string" and string.find(policy.key, ":container:", 1, true) ~= nil
        local matches = not stablePolicy and objectIndex == tonumber(policy.objectIndex)
        if stablePolicy and object ~= nil and object.getModData ~= nil then
            local data = object:getModData()
            local ids = data ~= nil and data.KnoxSurvivors ~= nil and data.KnoxSurvivors.storageIds or {}
            for _, id in pairs(ids or {}) do
                if id == policy.key then matches = true; break end
            end
        end
        if object ~= nil and matches then
            local containerIndex = tonumber(policy.containerIndex) or 0
            local container = object:getContainerByIndex(containerIndex)
            if container ~= nil and container:isExistYet() then
                local actualType = tostring(container:getType() or "container")
                local expectedType = tostring(policy.containerType or actualType)
                if expectedType == actualType or expectedType == "container" then
                    if policy.toolCupboard == true and object.getModData ~= nil
                        and container.getCapacity ~= nil and container.setCapacity ~= nil then
                        local data = object:getModData()
                        if data.KnoxToolCupboard == nil then
                            data.KnoxToolCupboard = { key = policy.key,
                                originalCapacity = container:getCapacity() }
                        end
                    end
                    if policy.toolCupboard == true and KnoxToolCupboard ~= nil
                        and KnoxToolCupboard.apply(object, container, policy.key) then
                        policy.toolCupboard = true
                    end
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
    return nil, "storage_object_missing"
end

-- The main cupboard holds every supply type. Optional food stores are explicit
-- player/AI assignments, not a revival of legacy sorting jobs or virtual stock.
function Storage.policies(base)
    if base == nil then return {} end
    local candidates, foodStores = {}, {}
    for _, policy in pairs(base.storage or {}) do
        if type(policy) == "table" and type(policy.key) == "string" then
            if policy.storageRole == "food" then
                foodStores[#foodStores + 1] = policy
            else
                candidates[#candidates + 1] = policy
            end
        end
    end
    table.sort(candidates, function(a, b)
        if (a.depot == true) ~= (b.depot == true) then return a.depot == true end
        return a.key < b.key
    end)
    table.sort(foodStores, function(a, b) return a.key < b.key end)
    local key = base.toolCupboardKey
    if key == nil then
        for _, policy in ipairs(candidates) do
            if KnoxToolCupboard.isDryContainerType(policy.containerType) then
                key = policy.key
                break
            end
        end
    end
    local selected = key ~= nil and base.storage[key] or nil
    local result, retained = {}, {}
    if selected ~= nil and selected.storageRole ~= "food" then
        base.toolCupboardKey = key
        selected.category, selected.depot, selected.toolCupboard = "depot", true, true
        selected.storageRole = "supplies"
        result[#result + 1], retained[key] = selected, selected
    end
    for _, policy in ipairs(foodStores) do
        policy.category, policy.depot, policy.toolCupboard = "food", false, false
        result[#result + 1], retained[policy.key] = policy, policy
    end
    -- Leave legacy references alone if no usable assignment was found. Never
    -- replace a missing named cupboard with an unrelated container.
    if #result > 0 then base.storage = retained end
    return result
end

function Storage.mainPolicy(base)
    for _, policy in ipairs(Storage.policies(base)) do
        if policy.toolCupboard == true then return policy end
    end
    return nil
end

function Storage.label(policy)
    return policy ~= nil and policy.storageRole == "food" and "Food & Drink Storage" or "Main Supplies"
end

function Storage.acceptsDeposit(policy, item)
    if policy == nil or item == nil then return false end
    if policy.storageRole ~= "food" then return true end
    -- Raw ingredients belong in the kitchen too; edibility is checked separately
    -- when choosing a meal. Keep unsafe food out of the ready-to-eat stock count.
    return safeBoolean(item, "IsFood") == true
        or (item.getDisplayCategory ~= nil and item:getDisplayCategory() == "Food")
        or KnoxSurvivorNeeds.isWaterItem(item, false)
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
        return (rawget(_G, "ItemTag") ~= nil and ItemTag.AMMO ~= nil
                and safeBoolean(item, "hasTag", ItemTag.AMMO) == true)
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

function Storage.classifyItem(item)
    for _, category in ipairs(Storage.RESOURCE_CATEGORIES) do
        if Storage.matchesCategory(item, category) then
            return category
        end
    end
    return "other"
end

local function itemQuantity(item)
    if item ~= nil and item.getCount ~= nil then
        local success, count = pcall(item.getCount, item)
        if success and tonumber(count) ~= nil then
            return math.max(1, math.floor(tonumber(count)))
        end
    end
    return 1
end

local function emptyResourceTotals()
    local totals = { other = 0 }
    for _, category in ipairs(Storage.RESOURCE_CATEGORIES) do
        totals[category] = 0
    end
    return totals
end

-- Returns an honest snapshot of assigned storage that is currently available in
-- the loaded cell.  Unloaded/missing containers are reported separately rather
-- than assumed empty or treated as an abstract stockpile.
function Storage.summarize(base)
    local summary = {
        totals = emptyResourceTotals(),
        loadedPolicies = 0,
        unavailablePolicies = 0,
        misplacedItems = 0,
    }
    for _, policy in ipairs(Storage.policies(base)) do
        local resolved = Storage.resolvePolicy(policy)
        if resolved == nil then
            summary.unavailablePolicies = summary.unavailablePolicies + 1
        else
            summary.loadedPolicies = summary.loadedPolicies + 1
            local items = resolved.container:getItems()
            for index = 0, items:size() - 1 do
                local item = items:get(index)
                local category = Storage.classifyItem(item)
                local quantity = itemQuantity(item)
                local policyCategory = tostring(policy.category or "general")
                if Storage.acceptsDeposit(policy, item) then
                    summary.totals[category] = (summary.totals[category] or 0) + quantity
                else
                    summary.misplacedItems = summary.misplacedItems + quantity
                end
            end
        end
    end
    return summary
end

local function hasRoom(container, item, character)
    if container == nil then
        return false
    end
    if container.hasRoomFor ~= nil then
        local success, result = pcall(function()
            return container:hasRoomFor(character, item)
        end)
        return success and result == true
    end
    return false
end

-- Cleanup deposits never target arbitrary nearby homes or foreign storage.
-- The caller supplies only this survivor's canonical assigned/owned base.
local function findDeposit(base, character, item, trip, excluded, ticks, policyKey)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    if base == nil or origin == nil then return nil, "no_owned_storage" end
    local candidates = {}
    for _, policy in ipairs(Storage.policies(base)) do
        local dx, dy = (tonumber(policy.x) or math.huge) - origin:getX(),
            (tonumber(policy.y) or math.huge) - origin:getY()
        local category = tostring(policy.category or "general")
        local floorDifference = math.abs((tonumber(policy.z) or math.huge) - origin:getZ())
        if (floorDifference == 0 or (trip and floorDifference <= 2))
            and dx * dx + dy * dy <= (trip and 128 * 128 or 2)
            and (policyKey == nil or policy.key == policyKey)
            and (excluded == nil or (excluded[policy.key] or 0) <= (ticks or 0))
            and Storage.acceptsDeposit(policy, item) then
            local resolved = Storage.resolvePolicy(policy)
            if resolved ~= nil and hasRoom(resolved.container, item, character)
                and safeBoolean(resolved.container, "isItemAllowed", item) == true then
                -- Native transfer validity does not itself reject every wall
                -- between two containers. Require a clear adjacent interaction.
                local approach = trip and AdjacentFreeTileFinder.Find(resolved.square, character) or origin
                local clear = approach ~= nil and approach:getZ() == resolved.square:getZ()
                    and (approach:getX() - resolved.square:getX()) ^ 2
                        + (approach:getY() - resolved.square:getY()) ^ 2 <= 2
                    and (approach == resolved.square or (approach.isSomethingTo ~= nil
                        and not approach:isSomethingTo(resolved.square)))
                if clear then
                    resolved.approach = approach
                    resolved.preference = policy.storageRole == "food" and 0 or 1
                    resolved.distance = dx * dx + dy * dy
                    candidates[#candidates + 1] = resolved
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.preference ~= b.preference then return a.preference < b.preference end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.policy.key < b.policy.key
    end)
    return candidates[1], candidates[1] ~= nil and "nearby_storage" or "no_reachable_storage"
end

function Storage.findNearbyDeposit(base, character, item, policyKey)
    return findDeposit(base, character, item, false, nil, nil, policyKey)
end

-- Only loaded owned containers within a practical local trip. The native
-- adjacent-square finder picks the interaction side; existing movement owns routing.
function Storage.findDepositTrip(base, character, item, excluded, ticks)
    return findDeposit(base, character, item, true, excluded, ticks)
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

-- Withdrawal follows actual contents, including a misplaced tool in a fridge.
-- Never fabricate an item from its type: native food/fluid methods need a real item.
local function policyCanSupply(policy)
    return policy ~= nil
end

-- Finds one real item needed by a claimed base task.  It deliberately searches
-- only assigned base storage and returns one transfer at a time, allowing the
-- normal timed-action queue to remain the sole owner of the inventory change.
function Storage.findRequiredTransfer(base, character, requirements)
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() then
        return nil, "requirements_ready"
    end
    local inventory = character ~= nil and character:getInventory() or nil
    local requiredItems = requirements ~= nil and requirements.items or {}
    for itemType, required in pairs(requiredItems) do
        local needed = math.max(0, math.floor(tonumber(required) or 0))
        if needed > KnoxBaseSupplyPlanner.inventoryCount(inventory, itemType, requirements) then
            for _, policy in ipairs(Storage.policies(base)) do
                if policyCanSupply(policy, tostring(itemType)) then
                    local resolved = Storage.resolvePolicy(policy)
                    if resolved ~= nil then
                        local items = resolved.container:getItems()
                        for index = 0, items:size() - 1 do
                            local item = items:get(index)
                            if fullType(item) == tostring(itemType)
                                and KnoxBaseSupplyPlanner.matchesRequirement(item, requirements) then
                                return {
                                    sourcePolicy = policy,
                                    source = resolved,
                                    item = item,
                                    itemType = tostring(itemType),
                                    required = needed,
                                }, "found"
                            end
                        end
                    end
                end
            end
            return nil, "missing_assigned_item=" .. tostring(itemType)
        end
    end
    return nil, "requirements_ready"
end

-- Discovery may inspect assigned, loaded storage to name a concrete requirement.
-- The normal transfer action still owns moving the selected item to the resident.
function Storage.findItemType(base, predicate)
    if type(predicate) ~= "function" then return nil end
    for _, policy in ipairs(Storage.policies(base)) do
        local resolved = Storage.resolvePolicy(policy)
        local items = resolved ~= nil and resolved.container:getItems() or nil
        if items ~= nil then
            for index = 0, items:size() - 1 do
                local item = items:get(index)
                local success, matches = pcall(predicate, item)
                if success and matches == true then
                    return fullType(item), item
                end
            end
        end
    end
    return nil
end

function Storage.requirementsAvailable(base, character, requirements)
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() then
        return true, "requirements_disabled"
    end
    local inventory = character ~= nil and character:getInventory() or nil
    local requiredItems = requirements ~= nil and requirements.items or {}
    for itemType, required in pairs(requiredItems) do
        local remaining = math.max(0, math.floor(tonumber(required) or 0))
            - KnoxBaseSupplyPlanner.inventoryCount(inventory, itemType, requirements)
        if remaining > 0 then
            for _, policy in ipairs(Storage.policies(base)) do
                if policyCanSupply(policy, tostring(itemType)) then
                    local resolved = Storage.resolvePolicy(policy)
                    if resolved ~= nil then
                        local items = resolved.container:getItems()
                        for index = 0, items:size() - 1 do
                            local item = items:get(index)
                            if fullType(item) == tostring(itemType)
                                and KnoxBaseSupplyPlanner.matchesRequirement(item, requirements) then
                                remaining = remaining - itemQuantity(item)
                                if remaining <= 0 then break end
                            end
                        end
                    end
                end
                if remaining <= 0 then break end
            end
        end
        if remaining > 0 then
            return false, "missing_assigned_item=" .. tostring(itemType)
        end
    end
    return true, "available"
end

function Storage.approachSquare(transfer, character)
    local square = transfer ~= nil and transfer.source ~= nil and transfer.source.square or nil
    if square == nil then return nil end
    local approach = AdjacentFreeTileFinder ~= nil
        and AdjacentFreeTileFinder.Find(square, character) or nil
    if approach ~= nil then return approach end
    return square.canStand ~= nil and square:canStand() and square or nil
end

-- Old saved task targets must fail closed, never resume container sorting.
function Storage.findTransfer(base) return nil, "sorting_retired" end
function Storage.transferTarget(transfer) return nil, "sorting_retired" end
function Storage.resolveTransfer(base, target) return nil, "sorting_retired" end

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
