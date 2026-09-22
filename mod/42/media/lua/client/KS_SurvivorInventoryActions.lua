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

function KnoxNpcInventoryTransferAction:isValid()
    local events = rawget(_G, "KnoxEventRuntime")
    if self.knoxEventContext ~= nil and (events == nil or not events.lootTransferAllowed(
        self.knoxEventContext, self.character, self.srcContainer, self.destContainer)) then return false end
    -- Assigned base storage has infinite weight: bypass vanilla capacity while
    -- keeping all other native validity (existence, item allowed, etc).
    local cupboard = rawget(_G, "KnoxToolCupboard")
    if cupboard ~= nil and cupboard.isInfiniteContainer ~= nil and self.destContainer ~= nil then
        local ok, infinite = pcall(function()
            return cupboard.isInfiniteContainer(self.destContainer)
        end)
        if ok and infinite == true then
            if self.item == nil or self.srcContainer == nil then return false end
            local okSrc, inSrc = pcall(function() return self.srcContainer:contains(self.item) end)
            if not okSrc or inSrc ~= true then
                -- Item may already be moved; let native decide.
                return ISInventoryTransferAction.isValid(self)
            end
            if self.destContainer.isItemAllowed ~= nil then
                local okAllowed, allowed = pcall(function()
                    return self.destContainer:isItemAllowed(self.item)
                end)
                if okAllowed and allowed ~= true then return false end
            end
            if self.destContainer.isExistYet ~= nil then
                local okExist, exists = pcall(function() return self.destContainer:isExistYet() end)
                if okExist and exists ~= true then return false end
            end
            return true
        end
    end
    return ISInventoryTransferAction.isValid(self)
end

function KnoxNpcInventoryTransferAction:canMergeAction(action)
    if action == nil then return false end
    local first, other = self.knoxEventContext, action.knoxEventContext
    if (first == nil) ~= (other == nil) then return false end
    if first ~= nil and (first.eventId ~= other.eventId or first.memberId ~= other.memberId
        or first.x ~= other.x or first.y ~= other.y or first.z ~= other.z) then return false end
    return ISInventoryTransferAction.canMergeAction(self, action)
end

function KnoxNpcInventoryTransferAction:transferItem(item)
    local events, context = rawget(_G, "KnoxEventRuntime"), self.knoxEventContext
    if context ~= nil and (events == nil or not events.lootTransferAllowed(
        context, self.character, self.srcContainer, self.destContainer)) then return end
    local wasPresent = context ~= nil and self.srcContainer:contains(item)
    -- Exact 42.20.3 SP perform() calls this once per actual batched item. Native
    -- transfer can replace self.item or put it on the floor when capacity changes.
    ISInventoryTransferAction.transferItem(self, item)
    if context ~= nil then
        events.observeLootTransfer(context, self.character, self.srcContainer, self.destContainer,
            item, self.item, wasPresent)
    end
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
    local events = rawget(_G, "KnoxEventRuntime")
    if events ~= nil then action.knoxEventContext = events.captureLootContext(character, source, destination) end
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
