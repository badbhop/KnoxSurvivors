require "ISUI/ISContextMenu"
require "KS_BaseManager"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_BaseTerritorySelector"
require "KS_BaseZoneSelector"
require "KS_SurvivorAutonomy"

local BaseContextMenu = rawget(_G, "KnoxBaseContextMenu") or {}
_G.KnoxBaseContextMenu = BaseContextMenu


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

function BaseContextMenu.confirmMove(_, button, player, square)
    if button == nil or button.internal ~= "YES" then
        KnoxActivityFeed.event("Home base move cancelled.")
        return
    end
    local base, result = KnoxBaseManager.movePlayerBase(player, square)
    if base ~= nil then
        KnoxActivityFeed.event("Home base moved. Items at the previous location were left untouched.")
    else
        KnoxActivityFeed.event("Could not move the base here: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.requestMove(player, square)
    local prompt = "Move your home base here? Existing items will stay at the old location, while old work areas, storage assignments, and queued jobs will be cleared."
    local modal = ISModalDialog:new(0, 0, 430, 170, prompt, true,
        BaseContextMenu, BaseContextMenu.confirmMove, player:getPlayerNum(), player, square)
    modal:initialise()
    modal:addToUIManager()
    modal.moveWithMouse = true
end

function BaseContextMenu.setStorage(baseId, object, containerIndex, category)
    local policy, result = KnoxBaseManager.setStoragePolicy(
        baseId,
        object,
        category,
        containerIndex
    )
    if policy ~= nil then
        KnoxActivityFeed.event("Assigned " .. KnoxBaseStorage.label(policy) .. ". Residents will use this container automatically.")
        if KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
    else
        KnoxActivityFeed.event("Could not set storage: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.removeStorage(baseId, key)
    local success, reason = KnoxPersistence.removeBaseStoragePolicy(baseId, key)
    KnoxActivityFeed.event(success and "Storage assignment removed. Contents stay here."
        or ("Could not remove storage: " .. tostring(reason)))
    if success and KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
end

function BaseContextMenu.selectTerritory(player, baseId)
    KnoxBaseTerritorySelector.start(player, baseId)
end

function BaseContextMenu.selectZone(player, baseId, zoneType, label)
    KnoxBaseZoneSelector.start(player, baseId, zoneType, label)
end

function BaseContextMenu.removeZone(_, baseId, zoneId)
    local removed, result = KnoxPersistence.removeBaseZone(baseId, zoneId)
    if removed then
        if KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
        KnoxActivityFeed.event("Work area removed.")
    else
        KnoxActivityFeed.event("Could not remove work area: " .. tostring(result) .. ".")
    end
end

function BaseContextMenu.openSetup(_, playerNum)
    if KnoxSurvivorNotebook and KnoxSurvivorNotebook.show then
        KnoxSurvivorNotebook.show(playerNum)
    end
end

function BaseContextMenu.dispatchScout(player, base, square)
    local success, result = KnoxSurvivorAutonomy.dispatchBaseScout(player, base.id, square)
    KnoxActivityFeed.event(success and ("Scout departed: " .. tostring(result) .. ".")
        or ("Could not send scout: " .. tostring(result) .. "."))
end

local function addStorageMenu(parent, base, object)
    local storageOptions = {
        { key = "food", label = "Food & Drink" },
        { key = "water", label = "Water" },
        { key = "medical", label = "Medical" },
        { key = "weapons", label = "Weapons" },
        { key = "ammunition", label = "Ammunition" },
        { key = "tools", label = "Tools" },
        { key = "building", label = "Building Materials" },
        { key = "farming", label = "Farming" },
        { key = "clothing", label = "Clothing" },
    }
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
            local reference = KnoxBaseManager.containerReference(object, containerIndex, base.id)
            local policy = reference ~= nil and base.storage ~= nil and base.storage[reference.key] or nil
            if policy ~= nil then
                local status = targetMenu:addOption("Assigned: " .. KnoxBaseStorage.label(policy), nil, nil)
                status.notAvailable = true
            end
            local mainOption = targetMenu:addOption("Use as Main Supplies (" .. tostring(KnoxSettings.toolCupboardCapacity()) .. ")",
                base.id, function(baseId, selected, selectedIndex)
                    local cupboard, reason = KnoxToolCupboard.designate(KnoxBaseManager.get(baseId),
                        selected, selectedIndex, KnoxBaseManager)
                    KnoxActivityFeed.event(cupboard ~= nil and "Base tool cupboard ready. Residents store and take supplies here."
                        or ("Could not assign cupboard: " .. tostring(reason)))
                    if cupboard ~= nil and KnoxBaseHighlights ~= nil then KnoxBaseHighlights.refresh() end
                end, object, containerIndex)
            mainOption.notAvailable = not KnoxToolCupboard.isDryContainerType(container:getType())
            if policy == nil or policy.toolCupboard ~= true then
                if policy ~= nil then
                    targetMenu:addOption("Stop Using for " .. KnoxBaseStorage.label(policy), base.id,
                        BaseContextMenu.removeStorage, policy.key)
                end
                local kind = string.lower(tostring(container:getType() or ""))
                local unusable = kind == "corpse" or kind:find("water", 1, true) ~= nil
                    or kind:find("rain", 1, true) ~= nil
                for _, storageOption in ipairs(storageOptions) do
                    local option = targetMenu:addOption("Use for " .. storageOption.label, base.id,
                        BaseContextMenu.setStorage, object, containerIndex, storageOption.key)
                    option.notAvailable = unusable
                end
            end
        end
    end
end

local function buildingId(square)
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    return definition ~= nil and tostring(definition:getID()) or nil
end

function BaseContextMenu.onFill(playerNum, context, worldobjects, test)
    if not KnoxSettings.enabled() then
        return
    end
    local player = getSpecificPlayer(playerNum)
    local square = firstSquare(worldobjects)
    if player == nil or square == nil then
        return
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = KnoxBaseManager.getForOwner("player", playerId)
    local containers = base ~= nil and containerObjects(worldobjects, base) or {}
    local clickedBuildingId = buildingId(square)
    local canEstablish = base == nil and clickedBuildingId ~= nil
    local canMove = base ~= nil and clickedBuildingId ~= nil
        and (base.home == nil or base.home.buildingId ~= clickedBuildingId)
    -- A resident may mark a work area on open ground, so a base menu must not
    -- depend on the clicked object being a container.
    if base == nil and not canEstablish and #containers == 0 then
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
    elseif canMove then
        menu:addOption("Move Home Base Here", player, BaseContextMenu.requestMove, square)
    end
    if base ~= nil then
        menu:addOption("Open Base Management", BaseContextMenu, BaseContextMenu.openSetup, playerNum)
        menu:addOption("Send Available Resident to Scout Here", player,
            BaseContextMenu.dispatchScout, base, square)
    end
    for _, object in ipairs(containers) do
        addStorageMenu(menu, base, object)
    end
end

Events.OnFillWorldObjectContextMenu.Add(BaseContextMenu.onFill)

return BaseContextMenu
