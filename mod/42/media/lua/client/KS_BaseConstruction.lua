require "BuildingObjects/ISBuildIsoEntity"
require "BuildingObjects/TimedActions/ISBuildAction"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"

local Construction = rawget(_G, "KnoxBaseConstruction") or {}
_G.KnoxBaseConstruction = Construction

local STAGES = {
    wall_frame = { entity = "WoodenWallFrame", skill = 2,
        items = { ["Base.Plank"] = 2, ["Base.Nails"] = 2 } },
    wall = { entity = "WoodenWallLvl1", skill = 2,
        items = { ["Base.Plank"] = 2, ["Base.Nails"] = 4 } },
    door_frame = { entity = "WoodDoorFrameLvl1", skill = 2,
        items = { ["Base.Plank"] = 4, ["Base.Nails"] = 4 } },
    door = { entity = "WoodenDoorLvl1", skill = 3,
        items = { ["Base.Plank"] = 4, ["Base.Nails"] = 4,
            ["Base.Hinge"] = 2, ["Base.Doorknob"] = 1 } },
}

local HAMMERS = {
    ["Base.Hammer"] = true, ["Base.BallPeenHammer"] = true,
    ["Base.ClubHammer"] = true, ["Base.WoodenMallet"] = true,
}

local function call(object, method, ...)
    if object == nil or object[method] == nil then return nil end
    local args = { ... }
    local ok, value = pcall(function() return object[method](object, unpack(args)) end)
    return ok and value or nil
end

local function nameOf(object)
    local value = call(object, "getName")
    return value ~= nil and tostring(value) or ""
end

local function northOf(object)
    return call(object, "getNorth") == true
end

local function forObjects(square, visitor)
    for _, getter in ipairs({ "getSpecialObjects", "getObjects" }) do
        local objects = call(square, getter)
        if objects ~= nil then
            for index = 0, objects:size() - 1 do
                if visitor(objects:get(index)) then return true end
            end
        end
    end
    return false
end

local function isEdgeObject(object, north)
    if object == nil then return false end
    local oriented = call(object, "getNorth")
    if oriented ~= nil and oriented ~= north then return false end
    local named = nameOf(object)
    if named == "WoodenWallFrame" or named == "WoodenWallLvl1"
        or named == "WoodDoorFrameLvl1" or named == "WoodenDoorLvl1" then
        return true
    end
    local sprite = call(object, "getSprite")
    local props = sprite ~= nil and call(sprite, "getProperties") or nil
    if props == nil or props.has == nil or IsoFlagType == nil then return false end
    local flags = north and { IsoFlagType.collideN, IsoFlagType.WallN,
        IsoFlagType.WallNW, IsoFlagType.WindowN, IsoFlagType.DoorWallN,
        IsoFlagType.HoppableN } or { IsoFlagType.collideW, IsoFlagType.WallW,
        IsoFlagType.WallNW, IsoFlagType.WindowW, IsoFlagType.DoorWallW,
        IsoFlagType.HoppableW }
    for _, flag in ipairs(flags) do
        if flag ~= nil and props:has(flag) then return true end
    end
    return false
end

local function edgeState(square, north)
    local result = { occupied = false, frame = false, doorFrame = false, door = false }
    forObjects(square, function(object)
        if isEdgeObject(object, north) then
            result.occupied = true
            local objectName = nameOf(object)
            result.frame = result.frame or objectName == "WoodenWallFrame"
            result.doorFrame = result.doorFrame or objectName == "WoodDoorFrameLvl1"
                or call(object, "isDoorFrame") == true
            result.door = result.door or objectName == "WoodenDoorLvl1"
                or call(object, "isDoor") == true
        end
        return false
    end)
    return result
end

local function stageFor(state, gate)
    if gate then
        if state.door then return nil end
        return state.doorFrame and "door" or (state.occupied and nil or "door_frame")
    end
    return state.frame and "wall" or (state.occupied and nil or "wall_frame")
end

local function findHammer(character)
    local found = nil
    local function visit(container)
        local items = call(container, "getItems")
        if items == nil then return end
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local fullType = item ~= nil and tostring(call(item, "getFullType") or "") or ""
            if found == nil and HAMMERS[fullType]
                and (item.isBroken == nil or not item:isBroken()) then found = item end
            if item ~= nil and item.IsInventoryContainer ~= nil and item:IsInventoryContainer() then
                visit(item:getInventory())
            end
        end
    end
    visit(character ~= nil and character:getInventory() or nil)
    return found
end

local function canCarry(character, stage)
    local definition = STAGES[stage]
    if definition == nil or findHammer(character) == nil then return false end
    local inventory = character:getInventory()
    for itemType, count in pairs(definition.items) do
        if (tonumber(call(inventory, "getItemCount", itemType, true)) or 0) < count then
            return false
        end
    end
    return true
end

local function infoFor(entityName)
    if SpriteConfigManager == nil then return nil end
    local ok, info = pcall(function() return SpriteConfigManager.GetObjectInfo(entityName) end)
    return ok and info or nil
end

local function target(base, zone, stage, square, north)
    local definition = STAGES[stage]
    return {
        id = "construct:" .. base.id .. ":" .. stage .. ":" .. square:getX()
            .. ":" .. square:getY() .. ":" .. square:getZ() .. ":" .. (north and "N" or "W"),
        action = "construct_defense", kind = stage, entityName = definition.entity,
        zoneType = "construction", zoneId = zone.id,
        x = square:getX(), y = square:getY(), z = square:getZ(), north = north,
        requiredItems = definition.items,
    }
end

local function consider(base, zone, cell, x, y, z, north, gate, character)
    local square = cell:getGridSquare(x, y, z)
    if square == nil then return nil end
    local stage = stageFor(edgeState(square, north), gate)
    return stage ~= nil and canCarry(character, stage)
        and target(base, zone, stage, square, north) or nil
end

function Construction.findTask(base, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or character == nil or cell == nil then return nil end
    local zones = {}
    for _, zone in pairs(base.zones or {}) do
        if zone.enabled ~= false and (zone.type == "construction" or zone.type == "defense") then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(a, b) return tostring(a.id) < tostring(b.id) end)
    for _, zone in ipairs(zones) do
        local x1, x2 = math.min(zone.x1, zone.x2), math.max(zone.x1, zone.x2)
        local y1, y2 = math.min(zone.y1, zone.y2), math.max(zone.y1, zone.y2)
        local z = tonumber(zone.z) or 0
        if x2 - x1 >= 2 and y2 - y1 >= 2 then
            local gateX = math.floor((x1 + x2) / 2)
            local found = consider(base, zone, cell, gateX, y2, z, true, true, character)
            if found then return found, "gate" end
            for x = x1, x2 do
                if x ~= gateX then
                    found = consider(base, zone, cell, x, y1, z, true, false, character)
                        or consider(base, zone, cell, x, y2, z, true, false, character)
                    if found then return found, "wall" end
                end
            end
            for y = y1 + 1, y2 - 1 do
                found = consider(base, zone, cell, x1, y, z, false, false, character)
                    or consider(base, zone, cell, x2, y, z, false, false, character)
                if found then return found, "wall" end
            end
        end
    end
    return nil, "no_construction_ready"
end

function Construction.requirements(targetValue, character)
    local definition = targetValue ~= nil and STAGES[targetValue.kind] or nil
    local hammer = findHammer(character)
    if definition == nil or hammer == nil then return nil end
    local items = { [hammer:getFullType()] = 1 }
    for itemType, count in pairs(definition.items) do items[itemType] = count end
    return { items = items, skills = { Woodwork = definition.skill } }
end

function Construction.resolveTarget(base, targetValue, character)
    local cell = getCell ~= nil and getCell() or nil
    local info = targetValue ~= nil and infoFor(targetValue.entityName) or nil
    if base == nil or targetValue == nil or cell == nil or info == nil then return nil end
    local square = cell:getGridSquare(targetValue.x, targetValue.y, targetValue.z)
    if square == nil then return nil end
    local stage = stageFor(edgeState(square, targetValue.north == true),
        targetValue.kind == "door" or targetValue.kind == "door_frame")
    if stage ~= targetValue.kind then return nil end
    local approach = AdjacentFreeTileFinder.Find(square, character)
    if approach == nil then return nil end
    return { square = square, approach = approach, info = info, target = targetValue }
end

function Construction.resolveTaskSquare(base, targetValue, character)
    local resolved = Construction.resolveTarget(base, targetValue, character)
    return resolved ~= nil and resolved.approach or nil
end

function Construction.queueAction(character, resolved)
    local hammer = findHammer(character)
    if character == nil or resolved == nil or hammer == nil then return nil, "missing_target_or_hammer" end
    local containers = ArrayList.new()
    containers:add(character:getInventory())
    local build = ISBuildIsoEntity:new(character, resolved.info,
        resolved.target.north and 2 or 1, containers)
    local sprite = build:getSprite()
    local action = ISBuildAction:new(character, build, resolved.target.x, resolved.target.y,
        resolved.target.z, resolved.target.north, sprite, tonumber(build.maxTime) or 200)
    build.buildPanelLogic:startCraftAction(action)
    if not build.buildPanelLogic:canPerformCurrentRecipe() or not build:isValid(resolved.square) then
        build.buildPanelLogic:stopCraftAction()
        return nil, "recipe_or_placement_invalid"
    end
    character:setPrimaryHandItem(hammer)
    ISTimedActionQueue.add(action)
    resolved.build = build
    return action, "queued"
end

function Construction.isComplete(resolved)
    if resolved == nil then return false end
    local found = false
    forObjects(resolved.square, function(object)
        if nameOf(object) == resolved.target.entityName
            and northOf(object) == (resolved.target.north == true) then found = true; return true end
        return false
    end)
    return found
end

return Construction
