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
assert(KnoxPersistence.updateCompanionOrder("companion", playerId, "relax", 48),
    "Relax is a durable owned-companion order")
duty = KnoxPersistence.getSurvivorDuty("companion")
assert(duty.order == "relax" and duty.directive == nil,
    "Relax replaces temporary directives without changing companion ownership")
assert(KnoxPersistence.updateCompanionOrder("companion", playerId, "hold", 48),
    "Stop Relaxing can restore an ordinary primary order")

assert(KnoxPersistence.setCompanionDirective("companion", playerId, {
    kind = "guard", minX = 12, minY = 22, maxX = 12, maxY = 22, z = 0,
}, 48), "Guard directive persists")
duty = KnoxPersistence.getSurvivorDuty("companion")
assert(duty.order == "hold" and duty.directive.kind == "guard",
    "Guard keeps its underlying Hold duty for interruption resume")

for _, kind in ipairs({ "find_food", "find_water", "find_medical", "find_weapon",
    "find_tools", "clean_inventory", "patrol_area" }) do
    assert(KnoxPersistence.setCompanionDirective("companion", playerId, {
        kind = kind, minX = 12, minY = 22, maxX = 24, maxY = 34, z = 0,
    }, 48), kind .. " mission directive persists")
    duty = KnoxPersistence.getSurvivorDuty("companion")
    assert(duty.order == "hold" and duty.directive.kind == kind,
        kind .. " mission preserves the underlying companion order")
end

assert(not KnoxPersistence.setCompanionDirective("companion", playerId, {
    kind = "find_food", minX = 12, minY = 22, maxX = 24, maxY = 34, z = math.huge,
}, 48), "mission directive rejects non-finite floor")
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

-- A changed automatic preference should release only the routine claim so the
-- scheduler can reconsider it immediately. Explicit Notebook assignments stay
-- owned by the resident until they complete or are cancelled.
local automaticTask = assert(KnoxPersistence.queueBaseTask(
    base.id, "guard", { id = "auto-post", x = 10, y = 20, z = 0 }, {}, 70
))
assert(KnoxPersistence.claimBaseTask(base.id, automaticTask.id, "companion", 48))
assert(KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
    "companion", base.id, "test_preference_change"
) == 1, "automatic base claim should be released on preference change")
assert(automaticTask.state == "queued" and automaticTask.claimedBy == nil,
    "released automatic claim should return to the queue")
assert(automaticTask.offscreenWaitHours == 0 and automaticTask.offscreenLastHours == nil,
    "released automatic claim should clear stale off-screen lease timing")
local manualTask = assert(KnoxPersistence.queueBaseTask(
    base.id, "patrol", { id = "manual-route", x = 12, y = 22, z = 0 }, {}, 70
))
assert(KnoxPersistence.claimBaseTask(base.id, manualTask.id, "companion", 48))
manualTask.manual = true
assert(KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
    "companion", base.id, "test_preference_change"
) == 0, "manual assignment must not be released by preference change")
assert(manualTask.state == "claimed" and manualTask.claimedBy == "companion",
    "manual assignment should remain authoritative")

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

-- The loaded controller must drop a stale automatic pointer immediately after
-- persistence requeues it, while retaining a manual pointer.
local dutyController = setmetatable({
    id = "companion", baseTask = automaticTask, baseTaskStartedAt = 10,
    baseTaskRetryAt = 20, releaseSupply = function() end,
    interruptForDirective = function() end,
}, Controller)
assert(dutyController:onDutyChanged() and dutyController.baseTask == nil,
    "duty notification should clear stale automatic controller task")
dutyController.baseTask = manualTask
assert(KnoxPersistence.setPlayerCompanion("companion", playerId, "follow", 48),
    "manual-preservation check should restore player ownership")
assert(KnoxPersistence.setPlayerBaseResident("companion", playerId, base.id, 48),
    "manual-preservation check should remain a base resident")
manualTask.manual = true
assert(dutyController:onDutyChanged() and dutyController.baseTask == manualTask,
    "duty notification must preserve manual controller task")
KnoxPersistence.setPlayerCompanion("companion", playerId, "follow", 48)
assert(dutyController:onDutyChanged() and dutyController.baseTask == nil,
    "leaving base duty must clear even a formerly manual base task")

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

local serviceSource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_CompanionService.lua", "r"))
local serviceText = serviceSource:read("*a")
serviceSource:close()
assert(string.find(serviceText, "function CompanionService.askNeedsAll", 1, true),
    "party needs checks reuse the existing individual needs report")
assert(string.find(serviceText, "function CompanionService.issueOrder", 1, true),
    "player-facing orders use one catalogue dispatch boundary")
assert(string.find(serviceText, "function CompanionService.issueOrderAll", 1, true),
    "party orders use the same catalogue dispatch boundary")
assert(string.find(serviceText, "order_not_companion_executable", 1, true),
    "unsupported catalogue entries fail closed")
assert(string.find(serviceText, "isBasePreference(normalizedKind)", 1, true),
    "base job preferences share the order dispatcher")
assert(string.find(serviceText, "normalize(kind)", 1, true),
    "legacy order names converge on the canonical dispatcher")
assert(string.find(serviceText, "normalizedPreference", 1, true),
    "base preference aliases persist canonically")
assert(string.find(serviceText, "requeueAutomaticBaseTasksForSurvivor", 1, true),
    "Rest should release routine work without cancelling manual assignments")
local controllerSource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r"))
local controllerText = controllerSource:read("*a")
controllerSource:close()
assert(string.find(controllerText, "resident_requested_rest", 1, true)
    and string.find(controllerText, "requeueAutomaticBaseTasksForSurvivor", 1, true),
    "controller Rest handling must preserve manual Notebook assignments")
assert(string.find(controllerText,
        "self.companionOrder ~= nil and self.companionDirective == nil", 1, true)
    and string.find(controllerText,
        "self.selfCareRetryAt[decision.kind] = ticks + SELF_CARE_RETRY_TICKS", 1, true),
    "an unordered companion need must not replace Follow/Hold with a world search")
local persistenceSource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_Persistence.lua", "r"))
local persistenceText = persistenceSource:read("*a")
persistenceSource:close()
assert(string.find(persistenceText, "survivor.alive == false", 1, true)
    and string.find(persistenceText, "survivor.duty.eventId ~= nil", 1, true),
    "dead and event-bound residents cannot change base preferences")
assert(string.find(persistenceText, "normalizedPreference", 1, true),
    "persistence canonicalizes migrated base preferences")
assert(string.find(serviceText, "I'll keep watch.", 1, true)
    and string.find(serviceText, "KnoxActivityFeed.speak", 1, true),
    "base role changes provide resident acknowledgement")
local partySource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_PartyCommands.lua", "r"))
local partyText = partySource:read("*a")
partySource:close()
assert(string.find(partyText, "issueOrderAll(player(playerNum), \"follow\")", 1, true)
    and string.find(partyText, "directive.kind", 1, true),
    "party UI routes primary and directive orders through the shared dispatcher")
local contextSource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua", "r"))
local contextText = contextSource:read("*a")
contextSource:close()
assert(string.find(contextText, "KnoxOrderCatalog.label(\"follow\")", 1, true)
    and string.find(contextText, "KnoxOrderCatalog.label(\"go_to\")", 1, true),
    "individual companion menu uses canonical order labels")

print("Companion command reliability PASS replacement=true persistence=true dismissal=true")
