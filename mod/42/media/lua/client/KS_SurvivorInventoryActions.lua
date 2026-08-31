require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"

local InventoryActions = rawget(_G, "KnoxInventoryActions") or {}
_G.KnoxInventoryActions = InventoryActions

local KnoxNpcInventoryTransferAction = ISInventoryTransferAction:derive(
    "KnoxNpcInventoryTransferAction"
)

local KnoxNpcSearchContainerAction = ISBaseTimedAction:derive(
    "KnoxNpcSearchContainerAction"
)

function KnoxNpcSearchContainerAction:isValid()
    return self.container ~= nil and self.container:isExistYet()
end

function KnoxNpcSearchContainerAction:waitToStart()
    local parent = self.container:getParent()
    if parent ~= nil then
        self.character:faceThisObject(parent)
    end
    return self.character:shouldBeTurning()
end

function KnoxNpcSearchContainerAction:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function KnoxNpcSearchContainerAction:start()
    self:setActionAnim("Loot")
    self:setAnimVariable("LootPosition", "")
    if self.container:getContainerPosition() then
        self:setAnimVariable("LootPosition", self.container:getContainerPosition())
    end
    self:setOverrideHandModels(nil, nil)
    self.character:reportEvent("EventLootItem")
    self.knoxSearchAnimationRequested = true
end

function KnoxNpcSearchContainerAction:perform()
    ISBaseTimedAction.perform(self)
end

function KnoxNpcSearchContainerAction:new(character, container, duration)
    local action = ISBaseTimedAction.new(self, character)
    action.container = container
    action.maxTime = duration or 90
    action.stopOnWalk = true
    action.stopOnRun = true
    return action
end

-- The stock action drives the selected local player's loot panel. An off-slot
-- IsoPlayer has no panel, so preserve inventory rules, animation, and sound
-- while omitting only that UI reference.
function KnoxNpcInventoryTransferAction:startActionAnim()
    ISInventoryTransferAction.startActionAnim(self)
    self.knoxLootAnimationRequested = true
    self.selectedContainer = nil
end

function KnoxNpcInventoryTransferAction:start()
    ISInventoryTransferAction.start(self)
    self.knoxRummageSoundStarted = self.loopSound ~= nil
end

function KnoxNpcInventoryTransferAction:new(character, item, source, destination, duration)
    return ISInventoryTransferAction.new(
        self,
        character,
        item,
        source,
        destination,
        duration
    )
end

function InventoryActions.queueTransfer(character, item, source, destination, duration)
    if character == nil or item == nil or source == nil or destination == nil then
        return nil, "missing_transfer_input"
    end
    local action = KnoxNpcInventoryTransferAction:new(
        character,
        item,
        source,
        destination,
        duration
    )
    ISTimedActionQueue.add(action)
    return action, "queued"
end

function InventoryActions.queueSearch(character, container, duration)
    if character == nil or container == nil then
        return nil, "missing_search_input"
    end
    local action = KnoxNpcSearchContainerAction:new(character, container, duration)
    ISTimedActionQueue.add(action)
    return action, "queued_search"
end

function InventoryActions.queueDrop(character, item)
    if character == nil or item == nil or character:getCurrentSquare() == nil
        or character:getVehicle() ~= nil then return nil, "drop_unavailable" end
    -- Match ISInventoryPage.GetFloorContainer without borrowing a local player's
    -- indexed UI container. Native transfer places the actual item in the world.
    local floor = ItemContainer.new("floor", nil, nil)
    floor:setExplored(true)
    return InventoryActions.queueTransfer(character, item, item:getContainer(), floor, nil)
end
