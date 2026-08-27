require "ISUI/LootWindow/ISLootWindowContainerControls"
require "ISUI/LootWindow/ISLootWindowObjectControlHandler"

KS_LootWindowHandler_Done = ISLootWindowObjectControlHandler:derive("KS_LootWindowHandler_Done")
local Handler = KS_LootWindowHandler_Done

function Handler:shouldBeVisible()
    local companion = rawget(_G, "KnoxCompanionInventory")
    if companion == nil or companion._active == nil then return false end
    local survivorId = companion._active[self.playerNum]
    if type(survivorId) ~= "string" or survivorId == "" then return false end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime == nil then return false end
    local character = runtime.getCharacter(survivorId)
    if character == nil then return false end
    local inv = character:getInventory()
    return inv ~= nil and self.container == inv
end

function Handler:getControl()
    self.control = self:getButtonControl("Done")
    return self.control
end

function Handler:perform()
    if isGamePaused() then return end
    local companion = rawget(_G, "KnoxCompanionInventory")
    if companion ~= nil and companion.finish ~= nil then
        companion.finish(self.playerNum)
    end
end

function Handler:new()
    local o = ISLootWindowObjectControlHandler.new(self)
    return o
end

ISLootWindowContainerControls.AddHandler(KS_LootWindowHandler_Done)
