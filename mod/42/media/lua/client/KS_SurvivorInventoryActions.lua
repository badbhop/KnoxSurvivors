require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTimedActionQueue"

local InventoryActions = rawget(_G, "KnoxInventoryActions") or {}
_G.KnoxInventoryActions = InventoryActions

local KnoxNpcInventoryTransferAction = ISInventoryTransferAction:derive(
    "KnoxNpcInventoryTransferAction"
)

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
