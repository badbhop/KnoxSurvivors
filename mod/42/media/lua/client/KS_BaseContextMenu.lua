require "ISUI/ISContextMenu"
require "KS_BaseManager"
require "KS_ActivityFeed"

local BaseContextMenu = rawget(_G, "KnoxBaseContextMenu") or {}
_G.KnoxBaseContextMenu = BaseContextMenu

local STORAGE_LABELS = {
    { "Depot", "depot" },
    { "Food", "food" },
    { "Water", "water" },
    { "Medical", "medical" },
    { "Weapons", "weapons" },
    { "Ammunition", "ammunition" },
    { "Tools", "tools" },
    { "Building Materials", "building" },
    { "Farming", "farming" },
    { "Clothing", "clothing" },
    { "General", "general" },
}

local function firstSquare(worldobjects)
    for _, object in ipairs(worldobjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        if square ~= nil then
            return square
        end
    end
    return nil
end

local function containerObjects(worldobjects, base)
    local found = {}
    for _, object in ipairs(worldobjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        local count = object ~= nil and object.getContainerCount ~= nil
            and object:getContainerCount()
            or 0
        if square ~= nil and count > 0 and KnoxBaseManager.containsSquare(base, square) then
            found[#found + 1] = object
        end
    end
    return found
end

function BaseContextMenu.establish(player, square)
    local base, result = KnoxBaseManager.establishPlayerBase(player, square)
    if base ~= nil then
        KnoxActivityFeed.event("Home base established.")
    else
        KnoxActivityFeed.event("Could not establish a base here: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.setStorage(baseId, object, containerIndex, category)
    local policy, result = KnoxBaseManager.setStoragePolicy(
        baseId,
        object,
        category,
        containerIndex
    )
    if policy ~= nil then
        KnoxActivityFeed.event("Storage set to " .. tostring(category) .. ".")
    else
        KnoxActivityFeed.event("Could not set storage: " .. tostring(result) .. ".")
    end
end

local function addStorageMenu(parent, base, object)
    local count = object:getContainerCount()
    local objectOption = parent:addOption(
        count > 1 and "Set Storage Containers" or "Set Storage",
        object,
        nil
    )
    local objectMenu = ISContextMenu:getNew(parent)
    parent:addSubMenu(objectOption, objectMenu)
    for containerIndex = 0, count - 1 do
        local container = object:getContainerByIndex(containerIndex)
        if container ~= nil then
            local targetMenu = objectMenu
            if count > 1 then
                local containerOption = objectMenu:addOption(
                    tostring(container:getType() or "Container")
                        .. " " .. tostring(containerIndex + 1),
                    container,
                    nil
                )
                targetMenu = ISContextMenu:getNew(objectMenu)
                objectMenu:addSubMenu(containerOption, targetMenu)
            end
            for _, definition in ipairs(STORAGE_LABELS) do
                targetMenu:addOption(
                    definition[1],
                    base.id,
                    BaseContextMenu.setStorage,
                    object,
                    containerIndex,
                    definition[2]
                )
            end
        end
    end
end

function BaseContextMenu.onFill(playerNum, context, worldobjects, test)
    local player = getSpecificPlayer(playerNum)
    local square = firstSquare(worldobjects)
    if player == nil or square == nil then
        return
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = KnoxBaseManager.getForOwner("player", playerId)
    local containers = base ~= nil and containerObjects(worldobjects, base) or {}
    local canEstablish = base == nil and square:getBuilding() ~= nil
    if not canEstablish and #containers == 0 then
        return
    end
    if test then
        if ISWorldObjectContextMenu.Test then
            return true
        end
        return ISWorldObjectContextMenu.setTest()
    end
    local rootOption = context:addOption("Knox Survivors", worldobjects, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, menu)
    if canEstablish then
        menu:addOption("Establish Home Base", player, BaseContextMenu.establish, square)
    end
    for _, object in ipairs(containers) do
        addStorageMenu(menu, base, object)
    end
end

Events.OnFillWorldObjectContextMenu.Add(BaseContextMenu.onFill)

return BaseContextMenu
