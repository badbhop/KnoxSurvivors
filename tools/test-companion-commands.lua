local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local key = "KnoxSurvivors_IsoPlayer"
local modData = { [key] = {} }
ModData = {
    getOrCreate = function(name)
        modData[name] = modData[name] or {}
        return modData[name]
    end,
}
Events = {
    OnSave = { Add = function() end },
    OnPostSave = { Add = function() end },
    OnGameStart = { Add = function() end },
}
getGameTime = function()
    return { getWorldAgeHours = function() return 48 end }
end

require "KS_Persistence"

local playerId = "player-command-test"
assert(KnoxPersistence.setRecord("companion", "record-companion"))
assert(KnoxPersistence.setPlayerCompanion("companion", playerId, "follow", 48))

assert(KnoxPersistence.setCompanionDirective("companion", playerId, {
    kind = "go_to", minX = 10, minY = 20, z = 0,
}, 48), "Move directive persists")
assert(KnoxPersistence.updateCompanionOrder("companion", playerId, "hold", 48),
    "Hold replacement persists")
local duty = KnoxPersistence.getSurvivorDuty("companion")
assert(duty.order == "hold" and duty.directive == nil,
    "new primary order replaces active temporary directive")

assert(KnoxPersistence.setCompanionDirective("companion", playerId, {
    kind = "guard", minX = 12, minY = 22, maxX = 12, maxY = 22, z = 0,
}, 48), "Guard directive persists")
duty = KnoxPersistence.getSurvivorDuty("companion")
assert(duty.order == "hold" and duty.directive.kind == "guard",
    "Guard keeps its underlying Hold duty for interruption resume")
assert(not KnoxPersistence.setCompanionDirective("companion", playerId, {
    kind = "go_to", minX = math.huge, minY = 1, z = 0,
}, 48), "non-finite command target rejected")
assert(not KnoxPersistence.setCompanionDirective("companion", playerId, {
    kind = "go_to", minX = 9, minY = 1, maxX = 8, maxY = 1, z = 0,
}, 48), "reversed command bounds rejected")

local base = assert(KnoxPersistence.createBase("player", playerId, {
    buildingId = "command-home", x = 10, y = 20, z = 0,
    minX = 8, minY = 18, width = 8, height = 8,
}, 48))
assert(KnoxPersistence.setPlayerBaseResident("companion", playerId, base.id, 48),
    "Return to Base persists as base duty")
duty = KnoxPersistence.getSurvivorDuty("companion")
assert(duty.mode == "base" and duty.baseId == base.id and duty.directive == nil,
    "Return to Base replaces companion command state")

assert(KnoxPersistence.setPlayerCompanion("companion", playerId, "follow", 48),
    "base resident can return to companion duty")
assert(KnoxPersistence.setSurvivorIndependent("companion", "dismissed", 48),
    "Dismiss persists")
duty = KnoxPersistence.getSurvivorDuty("companion")
assert(duty.mode == "autonomous" and duty.order == "survive"
        and KnoxPersistence.isIndependentSurvivor("companion"),
    "Dismiss clears ownership and leaves a valid independent survivor")

-- Load just the controller API with minimal engine stubs. This verifies that a
-- loaded shell cannot retain a runtime-only directive after its persisted duty
-- has changed away from companion ownership.
local oldRequire = require
require = function() return true end
assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"))()
require = oldRequire
local Controller = assert(KnoxAutonomyController)
local interrupted = 0
local controller = setmetatable({
    id = "companion",
    companionOwnerId = playerId,
    companionOrder = "follow",
    companionDirective = { kind = "guard", minX = 1, minY = 1, z = 0 },
    interruptForDirective = function()
        interrupted = interrupted + 1
        return true
    end,
}, Controller)
controller:clearCompanionOrder()
assert(interrupted == 1 and controller.companionOrder == nil
        and controller.companionDirective == nil,
    "loaded duty transition clears runtime directive exactly once")

assert(KnoxPersistence.setPlayerCompanion("companion", playerId, "follow", 48))
modData[key].survivors.companion.duty.directive = {
    kind = "go_to", minX = math.huge, minY = 1, z = 0,
}
controller.companionOwnerId = playerId
controller.companionOrder = "follow"
controller:setCompanionDirective(modData[key].survivors.companion.duty.directive)
assert(controller.companionDirective == nil
        and KnoxPersistence.getSurvivorDuty("companion").directive == nil,
    "malformed restored directive is cleared once and cannot strand the command")

print("Companion command reliability PASS replacement=true persistence=true dismissal=true")
