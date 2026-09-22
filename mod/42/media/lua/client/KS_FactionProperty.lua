require "TimedActions/ISInventoryTransferAction"
require "KS_Persistence"
require "KS_ActivityFeed"

local Property = rawget(_G, "KnoxFactionProperty") or {}
_G.KnoxFactionProperty = Property

local function worldAge()
    local time = getGameTime ~= nil and getGameTime() or nil
    return time ~= nil and time:getWorldAgeHours() or 0
end

local function localPlayerId(character)
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, (tonumber(count) or 1) - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and player == character then
            return KnoxPersistence.ensurePlayerId(player)
        end
    end
    return nil
end

local function theftContext(action)
    if action == nil or action.character == nil or action.srcContainer == nil
        or action.destContainer == nil then return nil end
    local playerId = localPlayerId(action.character)
    if playerId == nil or action.destContainer.isInCharacterInventory == nil
        or not action.destContainer:isInCharacterInventory(action.character) then
        return nil
    end
    local parent = action.srcContainer.getParent ~= nil and action.srcContainer:getParent() or nil
    local square = nil
    if parent ~= nil and parent.getSquare ~= nil then
        local ok, result = pcall(function() return parent:getSquare() end)
        square = ok and result or nil
    end
    if square == nil then return nil end
    local base = KnoxPersistence.getBaseAtSquare(
        square:getX(), square:getY(), square:getZ(), "faction"
    )
    return base ~= nil and { playerId = playerId, baseId = base.id } or nil
end

-- Build 42 performs authoritative inventory transfers locally in singleplayer.
-- Multiplayer completion is server-owned, so do not create a client-only
-- diplomacy change from a packet that may still be rejected by the server.
if ISInventoryTransferAction ~= nil and ISInventoryTransferAction.transferItem ~= nil then
    local nativeTransferItem = ISInventoryTransferAction.transferItem
    function ISInventoryTransferAction:transferItem(item)
        local context = not (isClient ~= nil and isClient()) and theftContext(self) or nil
        local result = nativeTransferItem(self, item)
        -- A failed transfer leaves the item in its source. Escalate only after
        -- the stock action really completed, including batched transfers.
        if context ~= nil and item ~= nil and self.srcContainer ~= nil
            and not self.srcContainer:contains(item) then
            local relation, status = KnoxPersistence.recordPlayerFactionTheft(
                context.playerId, context.baseId, worldAge()
            )
            if relation ~= nil and status == "hostile" then
                KnoxActivityFeed.event("You took supplies from an NPC faction base. They are now hostile.")
            end
        end
        return result
    end
end

return Property
