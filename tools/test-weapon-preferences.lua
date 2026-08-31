local root = arg[1] or "."
isClient = function() return false end
isServer = function() return false end
local data = {}
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnPostSave = { Add = function() end },
    OnGameStart = { Add = function() end }, OnFillWorldObjectContextMenu = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 48 end } end
dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
for _, id in ipairs({ "a", "b" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
    assert(KnoxPersistence.setPlayerCompanion(id, "owner", "hold", 48))
end
assert(KnoxPersistence.getSurvivorPolicies("a").weaponPreference == "auto", "legacy default migrates")
assert(not KnoxPersistence.setSurvivorWeaponPreference("missing", "ranged") and data.survivors.missing == nil,
    "policy setter cannot create a phantom identity")
assert(KnoxPersistence.setCompanionDirective("a", "owner", { kind = "guard", minX = 1, minY = 2, z = 0 }, 48))
assert(not KnoxPersistence.setCompanionWeaponPreference("a", "stranger", "ranged", 49))
assert(not KnoxPersistence.setCompanionWeaponPreference("a", "owner", "invalid", 49))
assert(KnoxPersistence.setCompanionWeaponPreference("a", "owner", "ranged", 49))
local duty = KnoxPersistence.getSurvivorDuty("a")
assert(duty.order == "hold" and duty.directive.kind == "guard", "weapon policy does not replace orders")
assert(KnoxPersistence.setCompanionWeaponPreference("a", "owner", "ranged", 50))
assert(KnoxPersistence.getSurvivorDuty("a").revision == duty.revision, "same preference does not churn revision")
dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
assert(KnoxPersistence.getSurvivorPolicies("a").weaponPreference == "ranged", "reload preserves real persisted policy")

require = function() return true end
local notices = 0
KnoxSurvivorRuntime = { notifyDutyChanged = function() notices = notices + 1 end }
KnoxActivityFeed = { event = function() end }
local service = dofile(root .. "/mod/42/media/lua/client/KS_CompanionService.lua")
service.getPlayerId = function() return "owner" end
assert(service.setWeaponPreference({}, "a", "melee") and notices == 1)
assert(service.setWeaponPreferenceAll({}, "ranged") and notices == 3)
assert(KnoxPersistence.getSurvivorPolicies("b").weaponPreference == "ranged")

dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local reset, released, cancelled = 0, 0, 0
KnoxFirearmSupport = { cancelPreparation = function() cancelled = cancelled + 1 return false end }
local controller = setmetatable({ state = "COMBAT", character = {}, companionOrder = "hold",
    companionDirective = { kind = "guard" }, bridge = { resetNpcCombat = function() reset = reset + 1 end },
    releaseCombat = function() released = released + 1 end }, KnoxAutonomyController)
controller:setWeaponPreference("melee")
assert(controller.state == "IDLE" and reset == 1 and released == 1 and controller.companionOrder == "hold"
    and controller.companionDirective.kind == "guard", "policy change clears combat but not persistent command")
controller:setWeaponPreference("melee")
assert(reset == 1 and cancelled == 1, "controller sync is idempotent")
local movementCancelled, jobReleased = 0, 0
controller.state = "ROAMING"
controller.bridge.cancelNpcMove = function() movementCancelled = movementCancelled + 1 end
controller.abandonBaseTask = function() jobReleased = jobReleased + 1 end
controller.releaseSupply = function() end
KnoxFirearmSupport.cancelPreparation = function() return true end
controller:setWeaponPreference("ranged")
assert(controller.state == "IDLE" and movementCancelled == 1 and jobReleased == 1
    and controller.companionDirective.kind == "guard", "reload interruption releases temporary route/job but retains guard")

local square = { getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end, getBuilding = function() return nil end }
local actor = { getCurrentSquare = function() return square end, getVehicle = function() return nil end,
    getX = square.getX, getY = square.getY, getZ = square.getZ }
getSpecificPlayer = function() return actor end
KnoxSurvivorRuntime.getCharacter = function() return actor end
KnoxBaseManager = { getForOwner = function() return nil end }
local function menu()
    local result = { options = {} }
    function result:addOption(name, target, callback, ...)
        local option = { name = name, target = target, callback = callback, args = { ... } }
        self.options[name] = option return option
    end
    function result:addSubMenu(option, child) option.child = child end
    function result:setOptionChecked(option, checked) option.checkMark = checked end
    return result
end
ISContextMenu = { get = menu, getNew = menu }
local party = dofile(root .. "/mod/42/media/lua/client/KS_PartyCommands.lua")
local partyMenu = party.openMenu(0, 0, 0, nil)
local weapons = partyMenu.options["Weapon Preference"].child.options
assert(weapons["Prefer Ranged"].checkMark and not weapons["Prefer Melee"].checkMark
    and not weapons["Survivor Choice"].checkMark, "party preference has exactly one native check")
assert(service.setWeaponPreference({}, "a", "melee"))
partyMenu = party.openMenu(0, 0, 0, nil)
for _, option in pairs(partyMenu.options["Weapon Preference"].child.options) do
    assert(not option.checkMark, "mixed party preference has no misleading active check")
end
weapons = partyMenu.options["Weapon Preference"].child.options
local selected = weapons["Survivor Choice"]
selected.callback(selected.target, unpack(selected.args))
assert(KnoxPersistence.getSurvivorPolicies("a").weaponPreference == "auto"
    and KnoxPersistence.getSurvivorPolicies("b").weaponPreference == "auto", "party callback updates both real records")
local individual = dofile(root .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua")
local individualMenu = menu()
assert(individual.populate(individualMenu, 0, "a"))
weapons = individualMenu.options.Orders.child.options["Weapon Preference"].child.options
assert(weapons["Survivor Choice"].checkMark and not weapons["Prefer Ranged"].checkMark)
selected = weapons["Prefer Melee"]
selected.callback(selected.target, unpack(selected.args))
assert(KnoxPersistence.getSurvivorPolicies("a").weaponPreference == "melee", "individual callback persists policy")
assert(KnoxPersistence.setSurvivorIndependent("a", "dismissed", 48))
KnoxPersistence.setSurvivorHostileToPlayer("a", "owner", true)
KnoxSettings = { enabled = function() return true end, companionLimit = function() return 4 end }
local hostileMenu = menu()
individual.populate(hostileMenu, 0, "a")
assert(hostileMenu.options["Talk (hostile)"].notAvailable and hostileMenu.options["Recruit (hostile)"].notAvailable,
    "hostile social choices explain why they are unavailable")
print("Weapon preferences PASS persistence=true ownership=true command=true service=true menus=true mixed_party=true")
