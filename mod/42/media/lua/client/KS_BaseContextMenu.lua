require "ISUI/ISContextMenu"
require "KS_BaseManager"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_ToolCupboard"
require "KS_BaseTerritorySelector"
require "KS_BaseZoneSelector"
require "KS_SurvivorAutonomy"
require "KS_BaseBarricades"
require "KS_BaseTaskBoard"

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
    local seen = {}
    for _, object in ipairs(worldobjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        local count = object ~= nil and object.getContainerCount ~= nil
            and object:getContainerCount()
            or 0
        -- worldobjects often contains the same IsoObject twice (multi-square
        -- crates, object + inventory proxy). Dedupe so crates get one menu.
        if square ~= nil and count > 0 and KnoxBaseManager.containsSquare(base, square)
            and seen[object] == nil then
            seen[object] = true
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

function BaseContextMenu.removeStorage(baseId, key, object, containerIndex)
    -- Restore the world container title before dropping the assignment.
    local base = KnoxBaseManager.get(baseId)
    local policy = base ~= nil and base.storage ~= nil and base.storage[key] or nil
    if policy ~= nil and KnoxBaseStorage ~= nil and KnoxBaseStorage.clearContainerName ~= nil then
        local container = nil
        if object ~= nil and object.getContainerByIndex ~= nil then
            local ok, direct = pcall(function()
                return object:getContainerByIndex(tonumber(containerIndex) or 0)
            end)
            if ok then container = direct end
        end
        if container ~= nil then
            KnoxBaseStorage.clearContainerName(policy, container)
        else
            local resolved, _ = KnoxBaseStorage.resolvePolicy(policy)
            if resolved ~= nil then
                KnoxBaseStorage.clearContainerName(policy, resolved.container)
            end
        end
    end
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

function BaseContextMenu.toggleDoorLock(player, base, door)
    if player == nil or base == nil or door == nil then
        KnoxActivityFeed.event("Could not lock door: missing target.")
        return
    end
    local locked = false
    pcall(function()
        if door.isLockedByKey ~= nil then locked = door:isLockedByKey() == true end
        if not locked and door.isLocked ~= nil then locked = door:isLocked() == true end
    end)
    local ok = pcall(function()
        if door.setLockedByKey ~= nil then
            door:setLockedByKey(not locked)
        end
        if door.setLocked ~= nil then
            door:setLocked(not locked)
        end
        if door.setKeyId ~= nil and not locked then
            door:setKeyId(tostring(base.id))
        end
        if door.transmitCompleteItemToServer ~= nil then
            door:transmitCompleteItemToServer()
        elseif door.transmitModData ~= nil then
            door:transmitModData()
        end
    end)
    if ok then
        -- Persist locked doors so they survive reloads.
        if KnoxPersistence.setBaseDoorLock ~= nil then
            local sq = door.getSquare ~= nil and door:getSquare() or nil
            if sq ~= nil then
                KnoxPersistence.setBaseDoorLock(base.id,
                    sq:getX(), sq:getY(), sq:getZ(), not locked)
            end
        end
        KnoxActivityFeed.event(not locked and "Door locked at base."
            or "Door unlocked at base.")
    else
        KnoxActivityFeed.event("Could not lock door.")
    end
end

-- Direct base orders for specific windows/build sites. Queues the concrete
-- task (if needed) and assigns it to the best available resident. If nobody
-- can take it right now the queued task remains for automatic pickup.
local function bestResidentForTask(player, base, taskType)
    if KnoxPersistence.getBaseResidentIds == nil then return nil end
    local candidates = KnoxPersistence.getBaseResidentIds(base.id) or {}
    local preferred = {}
    local fallback = {}
    for _, survivorId in ipairs(candidates) do
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(survivorId) or {}
        local pref = tostring(duty.jobPreference or "auto")
        if pref == taskType or pref == "woodwork" or pref == "auto" then
            preferred[#preferred + 1] = survivorId
        else
            fallback[#fallback + 1] = survivorId
        end
    end
    for _, list in ipairs({ preferred, fallback }) do
        for _, survivorId in ipairs(list) do
            -- Eligibility (at base, skills, materials) is enforced by claimSpecific.
            return survivorId
        end
    end
    return nil
end

local function assignTaskToBestResident(player, base, task)
    if task == nil then return nil end
    local service = rawget(_G, "KnoxCompanionService")
    if service == nil or service.assignBaseTask == nil then return nil end
    local preference = task.type == "barricade" and "barricade" or "woodwork"
    local survivorId = bestResidentForTask(player, base, preference)
    if survivorId == nil then return nil end
    local assigned = service.assignBaseTask(player, survivorId, base.id, task.id)
    return assigned
end

function BaseContextMenu.orderBarricadeHere(player, base, square)
    if player == nil or base == nil or square == nil then
        KnoxActivityFeed.event("Could not order barricade: missing target.")
        return
    end
    local barricades = rawget(_G, "KnoxBaseBarricades")
    local board = rawget(_G, "KnoxBaseTaskBoard")
    if barricades == nil or board == nil then
        KnoxActivityFeed.event("Could not order barricade: unavailable.")
        return
    end
    -- Board the windows of the clicked building, skipping doors so residents
    -- can still use them. Falls back to the single clicked square outside.
    local targets = {}
    if barricades.findTargetsInBuilding ~= nil then
        targets = barricades.findTargetsInBuilding(base, square, nil, 24) or {}
    end
    if #targets == 0 then
        local tx, ty, tz = square:getX(), square:getY(), square:getZ()
        local single = barricades.findTarget ~= nil and barricades.findTarget(base, nil,
            function(candidate)
                return tonumber(candidate.x) == tx and tonumber(candidate.y) == ty
                    and tonumber(candidate.z) == tz
            end) or nil
        if single ~= nil then targets = { single } end
    end
    if #targets == 0 then
        KnoxActivityFeed.event("Nothing here needs barricading.")
        return
    end
    local hammer = barricades.findHammer ~= nil and barricades.findHammer(nil, base) or nil
    local hammerType = hammer ~= nil and hammer.getFullType ~= nil
        and hammer:getFullType() or "Base.Hammer"
    local queued, assigned = 0, nil
    for _, target in ipairs(targets) do
        -- Reuse existing queued task for the same window when present.
        local task = nil
        for _, existing in pairs(base.tasks or {}) do
            if existing ~= nil and existing.target ~= nil
                and tostring(existing.target.id) == tostring(target.id)
                and (existing.state == "queued" or existing.state == "claimed") then
                task = existing
                break
            end
        end
        if task == nil then
            task = board.queue(base.id, "barricade", target, {
                items = { [hammerType] = 1, ["Base.Plank"] = 1, ["Base.Nails"] = 2 },
            }, 98)
        end
        if task ~= nil then
            queued = queued + 1
            if assigned == nil then
                assigned = assignTaskToBestResident(player, base, task)
            end
        end
    end
    if queued == 0 then
        KnoxActivityFeed.event("Could not queue barricade work.")
        return
    end
    KnoxActivityFeed.event(assigned ~= nil
        and ("Resident ordered to barricade " .. tostring(queued) .. " windows.")
        or ("Barricade work queued (" .. tostring(queued) .. ") — residents will take it."))
end

function BaseContextMenu.burnCorpsesHere(player, base, square)
    -- Retired: the corpse drop area is the burn order point. Full piles
    -- auto-queue burn work (KS_BaseJobs.ensureBurnTask) and the Notebook Work
    -- tab assigns it; a separate here-menu only duplicated that path.
    if player == nil or base == nil or square == nil then
        KnoxActivityFeed.event("Mark a Corpse Drop Area instead: full piles burn automatically.")
        return
    end
    KnoxActivityFeed.event("Mark a Corpse Drop Area instead: full piles burn automatically.")
end

local function addStorageMenu(parent, base, object)
    local storageOptions = {
        { key = "food", label = "Food & Drink" },
        { key = "water", label = "Water" },
        { key = "medical", label = "Medical" },
        { key = "weapons", label = "Weapons" },
        { key = "ammunition", label = "Ammunition" },
        { key = "tools", label = "Tools" },
        { key = "building", label = "Materials" },
        { key = "farming", label = "Farming" },
        { key = "clothing", label = "Clothing" },
        { key = "junk", label = "Junk" },
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
                targetMenu:addOption("Stop Using for " .. KnoxBaseStorage.label(policy), base.id,
                    BaseContextMenu.removeStorage, policy.key, object, containerIndex)
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
        local ordersOption = menu:addOption("Resident Orders", nil, nil)
        local ordersMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(ordersOption, ordersMenu)
        ordersMenu:addOption("Scout Here", player,
            BaseContextMenu.dispatchScout, base, square)
        ordersMenu:addOption("Barricade Building Windows", player,
            BaseContextMenu.orderBarricadeHere, base, square)
        -- Door locks at base/safehouse.
        for _, object in ipairs(worldobjects or {}) do
            local isDoor = false
            if instanceof ~= nil and object ~= nil then
                local ok, result = pcall(function() return instanceof(object, "IsoDoor") end)
                isDoor = ok and result == true
            end
            if isDoor and KnoxBaseManager.containsSquare(base, square) then
                local locked = false
                pcall(function()
                    if object.isLockedByKey ~= nil then locked = object:isLockedByKey() == true end
                end)
                menu:addOption(locked and "Unlock Door at Base" or "Lock Door at Base", player,
                    BaseContextMenu.toggleDoorLock, base, object)
                break
            end
        end
    end
    for _, object in ipairs(containers) do
        addStorageMenu(menu, base, object)
    end
end

Events.OnFillWorldObjectContextMenu.Add(BaseContextMenu.onFill)

return BaseContextMenu
