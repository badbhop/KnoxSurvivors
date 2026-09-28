local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local data = {}
ModData = { getOrCreate = function(key) data[key] = data[key] or {}; return data[key] end }
Events = { OnSave = { Add = function() end }, OnPostSave = { Add = function() end },
    OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 50 end } end

local originalRequire = require
require = function() return true end
assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_Persistence.lua"))()
assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_SurvivorRuntime.lua"))()
assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_OrderCatalog.lua"))()
KnoxActivityFeed = { speak = function() end, event = function() end }
KnoxSettings = { enabled = function() return true end }
KnoxCompanionVehicles = { cancel = function() end }
KnoxOrderSignals = { order = function() return true end }
assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_CompanionService.lua"))()
require = originalRequire

local playerId = "player-detached"
local player = {}
KnoxCompanionService.getPlayerId = function() return playerId end
assert(KnoxPersistence.setRecord("companion-detached", "record-before-detach"))
assert(KnoxPersistence.ensureSurvivorIdentity(
    "companion-detached", "Casey", "Morgan", 50))
assert(KnoxPersistence.setPlayerCompanion(
    "companion-detached", playerId, "follow", 50))

local body = { getCurrentSquare = function() return nil end }
local controller = { character = body, dutyChanges = 0,
    onDutyChanged = function(self) self.dutyChanges = self.dutyChanges + 1 end }
assert(KnoxSurvivorRuntime.register("companion-detached", controller))
assert(KnoxSurvivorRuntime.setLifecycleState("companion-detached", "detached_grace"))
assert(KnoxSurvivorRuntime.activeIds()[1] == "companion-detached",
    "detached grace remains intentionally registered, not silently off-screen simulated")

local accepted, reason = KnoxCompanionService.command(
    player, "companion-detached", "hold")
assert(not accepted and reason == "companion_detached")
local duty = KnoxPersistence.getSurvivorDuty("companion-detached")
assert(duty.mode == "companion" and duty.order == "follow",
    "rejected detached order preserves the prior persisted order")
accepted, reason = KnoxCompanionService.issueOrder(
    player, "companion-detached", "relax")
assert(not accepted and reason == "companion_detached"
    and KnoxPersistence.getSurvivorDuty("companion-detached").order == "follow")

assert(KnoxSurvivorRuntime.setLifecycleState("companion-detached", "active"))
accepted, reason = KnoxCompanionService.command(player, "companion-detached", "hold")
assert(accepted and reason == "hold"
    and KnoxPersistence.getSurvivorDuty("companion-detached").order == "hold",
    "a recovered shell accepts orders through the same identity")

assert(KnoxSurvivorRuntime.setLifecycleState("companion-detached", "detached_stale"))
accepted, reason = KnoxCompanionService.issueOrder(
    player, "companion-detached", "dismiss")
assert(accepted and reason == "dismissed",
    "dismissal remains a safe persistence ownership change while detached")
assert(KnoxPersistence.getSurvivorDuty("companion-detached").mode == "autonomous")
assert(KnoxPersistence.getRecord("companion-detached") == "record-before-detach"
    and KnoxPersistence.getSurvivorIdentity("companion-detached").forename == "Casey",
    "detachment and dismissal preserve record-backed identity")

assert(KnoxSurvivorRuntime.unregister("companion-detached", controller))
assert(#KnoxSurvivorRuntime.activeIds() == 0,
    "transaction completion removes the survivor from the active simulation owner")
local replacement = { character = { getCurrentSquare = function() return {} end } }
assert(KnoxSurvivorRuntime.register("companion-detached", replacement))
assert(#KnoxSurvivorRuntime.activeIds() == 1
    and KnoxSurvivorRuntime.getCharacter("companion-detached") == replacement.character,
    "the same stable identity can be registered once after materialization")

print("Detached companion lifecycle PASS classification=true order_gate=true persistence=true unregister=true rematerialize=true no_duplicate=true")
