local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local originalRequire = require
require = function(name)
    if name == "KS_OrderCatalog" then
        return originalRequire(name)
    end
    return true
end
KnoxPersistence = {}
KnoxSurvivorRuntime = { notifyDutyChanged = function() end }
KnoxActivityFeed = {}
KnoxSettings = {}
KnoxCompanionVehicles = {}
getGameTime = function() return { getWorldAgeHours = function() return 1 end } end
KnoxPersistence.ensurePlayerId = function() return "owner" end
KnoxPersistence.getCompanionIds = function() return {} end

assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_CompanionService.lua"))()
require = originalRequire
local service = assert(KnoxCompanionService)
local calls = {}
local originalIssueDirective = service.issueDirective
service.issueDirective = function(_, id, directive)
    calls[#calls + 1] = "directive:" .. id .. ":" .. directive.kind
    return true, directive.kind
end
service.setBaseJobPreference = function(_, id, preference)
    calls[#calls + 1] = "preference:" .. id .. ":" .. preference
    return true, preference
end
local payload = { minX = 10, minY = 20, maxX = 10, maxY = 20, z = 0 }
assert(service.issueOrder({}, "survivor", "guard", payload))
assert(calls[1] == "directive:survivor:guard",
    "targeted guard order must route to the companion directive")
assert(service.issueOrder({}, "resident", "guard"))
assert(calls[2] == "preference:resident:guard",
    "payload-less guard order must remain a base preference")
assert(service.issueOrder({}, "resident", "patrol"))
assert(calls[3] == "preference:resident:patrol",
    "payload-less patrol order must remain a base preference")
assert(service.issueOrder({}, "legacy-resident", "patrol_area"))
assert(calls[4] == "preference:legacy-resident:patrol",
    "legacy patrol-area resident preference must migrate to base patrol")
assert(service.issueOrder({}, "resident", "farm_seed"))
assert(calls[5] == "preference:resident:farming",
    "concrete farming task names must route to the resident preference")
local assignedBaseTask
service.assignBaseTask = function(_, id, baseId, taskId)
    assignedBaseTask = { id = id, baseId = baseId, taskId = taskId }
    calls[#calls + 1] = "assignment:" .. id .. ":" .. baseId .. ":" .. taskId
    return assignedBaseTask, "claimed"
end
local assigned, assignedResult = service.issueOrder({}, "resident", "assign_base_task",
    { baseId = "base-1", taskId = "task-1" })
assert(assigned ~= nil and assignedResult == "claimed"
    and calls[6] == "assignment:resident:base-1:task-1",
    "concrete base task assignments must use the existing task-board boundary")
local missingAssignment, missingAssignmentResult = service.issueOrder({}, "resident", "assign_base_task", {})
assert(not missingAssignment and missingAssignmentResult == "task_target_required",
    "base task assignment must fail closed without an explicit target")
assert(service.issueOrder({}, "patroller", "patrol", payload))
assert(calls[7] == "directive:patroller:patrol_area",
    "payload-bearing patrol must route to the concrete area directive")
KnoxSurvivorRuntime.getCharacter = function(id)
    return { getCurrentSquare = function()
        return { getX = function() return id == "searcher" and 100 or 200 end,
            getY = function() return 50 end, getZ = function() return 0 end }
    end }
end
assert(service.issueOrder({}, "searcher", "find_food"))
assert(calls[8] == "directive:searcher:find_food",
    "payload-less search order must receive a bounded default area")
local persistenceDirective
KnoxPersistence.setCompanionDirective = function(_, _, directive)
    persistenceDirective = directive
    return true
end
service.issueDirective = originalIssueDirective
service.getPlayerId = function() return "owner" end
local directAlias = { kind = "explore", minX = 1, minY = 2, maxX = 3, maxY = 4, z = 0 }
assert(service.issueDirective({}, "direct", directAlias))
assert(persistenceDirective ~= directAlias and persistenceDirective.kind == "loot_area"
    and persistenceDirective.minX == 1,
    "direct directive callers must persist one canonical kind without losing payload")
KnoxPersistence.getBaseResidentIds = function() return { "resident-a", "resident-b" } end
KnoxBaseManager = {
    getForOwner = function(kind, ownerId)
        return kind == "player" and ownerId == "owner" and { id = "base-1" } or nil
    end,
}
local partySuccess, partyChanged = service.issueOrderAll({}, "farm_seed")
assert(partySuccess and partyChanged == 2
    and calls[9] == "preference:resident-a:farming"
    and calls[10] == "preference:resident-b:farming",
    "party concrete work orders must route every resident through one preference owner")
KnoxPersistence.getCompanionIds = function() return { "companion-a", "companion-b" } end
service.issueDirective = function(_, id, directive)
    calls[#calls + 1] = "directive:" .. id .. ":" .. directive.kind
    return true, directive.kind
end
local localSearchSuccess, localSearchChanged = service.issueOrderAll({}, "find_food")
assert(localSearchSuccess and localSearchChanged == 2
    and calls[11] == "directive:companion-a:find_food"
    and calls[12] == "directive:companion-b:find_food",
    "payload-less party search must resolve one local directive per companion")
KnoxPersistence.getCompanionIds = function() return { "companion-a" } end
local companionGuard, companionGuardKind = service.issueOrder({}, "companion-a", "guard")
assert(companionGuard and companionGuardKind == "guard" and calls[13] == "directive:companion-a:guard",
    "payload-less companion guard must create a bounded guard directive")
local companionPatrol, companionPatrolKind = service.issueOrder({}, "companion-a", "patrol")
assert(companionPatrol and companionPatrolKind == "patrol_area" and calls[14] == "directive:companion-a:patrol_area",
    "payload-less companion patrol must create a bounded patrol directive")
local partyGuardSuccess, partyGuardChanged = service.issueOrderAll({}, "guard")
assert(partyGuardSuccess and partyGuardChanged == 1
    and calls[15] == "directive:companion-a:guard",
    "payload-less party guard must reach travelling companions")
local partyPatrolSuccess, partyPatrolChanged = service.issueOrderAll({}, "patrol")
assert(partyPatrolSuccess and partyPatrolChanged == 1
    and calls[16] == "directive:companion-a:patrol_area",
    "payload-less party patrol must reach travelling companions")
service.issueDirectiveAll = function(_, directive)
    calls[#calls + 1] = "party-directive:" .. directive.kind
    return true, 2
end
local patrolSuccess, patrolChanged = service.issueOrderAll({}, "patrol", payload)
assert(patrolSuccess and patrolChanged == 2 and calls[17] == "party-directive:patrol_area",
    "party payload-bearing patrol must route to the area directive")
local menuSource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_PartyCommands.lua", "r")):read("*a")
assert(menuSource:find("basePreferenceAll", 1, true),
    "party menu must expose the shared base-preference dispatcher")
assert(menuSource:find("basePreferenceOrder", 1, true),
    "party base-work menu must use the canonical preference order")
assert(menuSource:find("hasPlayerBaseResidents", 1, true),
    "party menu must remain available for a player who only has base residents")
assert(menuSource:find("sharedPreference", 1, true),
    "party base-work menu must reflect the persisted shared resident preference")
assert(menuSource:find("KnoxOrderCatalog.label(\"follow\")", 1, true),
    "party primary commands must use the canonical order catalogue")
assert(menuSource:find("KnoxOrderCatalog.label(\"enter_vehicle\")", 1, true),
    "party vehicle actions must use the canonical action catalogue")
assert(menuSource:find('issueOrderAll(player(playerNum), "check_needs")', 1, true)
    and menuSource:find('issueOrderAll(player(playerNum), "enter_vehicle")', 1, true)
    and menuSource:find('issueOrderAll(player(playerNum), "exit_vehicle")', 1, true),
    "party needs and vehicle actions must use the shared order dispatcher")
assert(menuSource:find('allowed and "allow_climbing" or "disallow_climbing"', 1, true),
    "party climbing actions must use the shared order dispatcher")
assert(menuSource:find("catalogLabel(\"party_orders\", \"Party Orders\")", 1, true),
    "party root label must use the canonical action catalogue")
local contextSource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua", "r")):read("*a")
assert(contextSource:find('issueOrder(player, id, "check_needs")', 1, true),
    "survivor needs context action must use the shared order dispatcher")
assert(contextSource:find('issueOrder(p, id, "hold")', 1, true),
    "medical check must preserve Hold through the shared order dispatcher")
local notebookSource = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_SurvivorNotebook.lua", "r")):read("*a")
assert(notebookSource:find('KnoxCompanionService.sendToBase', 1, true)
    and notebookSource:find('transferBaseResident', 1, true)
    and notebookSource:find('KnoxPersistence.setPlayerBaseResident', 1, true) == nil,
    "Notebook resident recall must use the shared service boundary, never raw persistence writes")
local catalogFile = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_OrderCatalog.lua", "r"))
local catalogSource = catalogFile:read("*a")
catalogFile:close()
assert(catalogSource:find("Catalog.actions", 1, true),
    "player-facing actions must live beside the canonical order catalogue")
assert(catalogSource:find("normalizeTaskType", 1, true)
    and catalogSource:find("storage_sorting", 1, true),
    "legacy settlement task names must normalize through the shared catalogue")
local serviceFile = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_CompanionService.lua", "r"))
local serviceSource = serviceFile:read("*a")
serviceFile:close()
assert(serviceSource:find('normalizedKind == "recruit"', 1, true)
    and serviceSource:find('return CompanionService.recruit(player, survivorId)', 1, true),
    "recruit action must use the canonical individual service boundary")
assert(serviceSource:find('normalizedKind == "dismiss"', 1, true)
    and serviceSource:find('return CompanionService.dismiss(player, survivorId)', 1, true),
    "dismiss action must use the canonical individual service boundary")
assert(serviceSource:find('normalizedKind == "check_needs"', 1, true)
    and serviceSource:find('return CompanionService.askNeeds(player, survivorId)', 1, true),
    "needs action must use the existing needs owner")
assert(serviceSource:find('return CompanionService.boardPlayerVehicle(player, survivorId)', 1, true)
    and serviceSource:find('return CompanionService.exitVehicle(player, survivorId)', 1, true),
    "vehicle actions must use the existing vehicle owners")
assert(serviceSource:find('return CompanionService.setClimbing(', 1, true)
    and serviceSource:find('CompanionService.setClimbingAll(', 1, true),
    "climbing actions must use the existing policy owners")
assert(serviceSource:find('normalizedKind == "combat_stance"', 1, true)
    and serviceSource:find('return CompanionService.setCombatStance(player, survivorId, stance)', 1, true)
    and serviceSource:find('CompanionService.setCombatStanceAll(player, stance)', 1, true),
    "combat stance actions must use the existing stance owners")
assert(serviceSource:find('normalizedKind == "weapon_preference"', 1, true)
    and serviceSource:find('return CompanionService.setWeaponPreference(player, survivorId, preference)', 1, true)
    and serviceSource:find('CompanionService.setWeaponPreferenceAll(player, preference)', 1, true),
    "weapon preference actions must use the existing equipment owners")
assert(contextSource:find('issueOrder(player, id, "recruit")', 1, true)
    and contextSource:find('issueOrder(player, id, "combat_stance"', 1, true)
    and contextSource:find('issueOrder(player, id, "weapon_preference"', 1, true)
    and contextSource:find('issueOrder(player, id, "dismiss")', 1, true),
    "individual context actions must converge on the shared dispatcher")
assert(menuSource:find('issueOrderAll(player(playerNum), "combat_stance"', 1, true)
    and menuSource:find('issueOrderAll(player(playerNum), "weapon_preference"', 1, true),
    "party stance and weapon actions must converge on the shared dispatcher")
print("Order routing PASS targeted_guard=true resident_guard=true base_catalog=true")
