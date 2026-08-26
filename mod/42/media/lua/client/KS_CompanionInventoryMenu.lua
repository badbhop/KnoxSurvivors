require "ISUI/ISContextMenu"
require "ISUI/ISInventoryPane"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "KS_CompanionService"
require "KS_SurvivorRuntime"
require "KS_ActivityFeed"

local InventoryMenu = rawget(_G, "KnoxCompanionInventoryMenu") or {}
_G.KnoxCompanionInventoryMenu = InventoryMenu

local GIVE_DISTANCE_SQUARED = 16

local function nearbyCompanions(player)
    local result = {}
    if player == nil or player:getCurrentSquare() == nil then return result end
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(player) or {}) do
        local character = KnoxSurvivorRuntime.getCharacter(id)
        local square = character ~= nil and character:getCurrentSquare() or nil
        if square ~= nil and square:getZ() == player:getZ() then
            local dx, dy = character:getX() - player:getX(), character:getY() - player:getY()
            if dx * dx + dy * dy <= GIVE_DISTANCE_SQUARED then
                result[#result + 1] = { id = id, character = character }
            end
        end
    end
    return result
end

local function displayName(id)
    local persistence = rawget(_G, "KnoxPersistence")
    local identity = persistence ~= nil and persistence.getSurvivorIdentity ~= nil
        and persistence.getSurvivorIdentity(id) or nil
    if identity ~= nil then
        local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
        if name ~= " " then return name end
    end
    return tostring(id)
end

function InventoryMenu.give(_, player, target, survivorId, items)
    if player == nil or target == nil or target:getCurrentSquare() == nil then return end
    local destination = target:getInventory()
    local moved = 0
    for _, item in ipairs(ISInventoryPane.getActualItems(items) or {}) do
        local source = item ~= nil and item:getContainer() or nil
        if source ~= nil and source:contains(item) then
            local action = ISInventoryTransferUtil.newInventoryTransferAction(
                player, item, source, destination
            )
            if action ~= nil then
                ISTimedActionQueue.add(action)
                moved = moved + 1
            end
        end
    end
    if moved > 0 then
        KnoxActivityFeed.event("Giving " .. tostring(moved) .. " item(s) to "
            .. displayName(survivorId) .. ".")
    end
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local companions = nearbyCompanions(player)
    if player == nil or #companions == 0
        or #(ISInventoryPane.getActualItems(items) or {}) == 0 then
        return
    end
    local root = context:addOption("Give to Companion", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    for _, entry in ipairs(companions) do
        menu:addOption(displayName(entry.id), InventoryMenu, InventoryMenu.give,
            player, entry.character, entry.id, items)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

return InventoryMenu
