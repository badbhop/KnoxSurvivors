local root = arg[1] or "."
require = function() end
Events = { OnFillWorldObjectContextMenu = { Add = function() end },
    OnTick = { Add = function() end, Remove = function() end } }
local square = {
    getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end,
    getBuilding = function() return nil end,
}
local actor = { getPlayerNum = function() return 0 end,
    getX = function() return 10 end, getY = function() return 10 end,
    getZ = function() return 0 end, getVehicle = function() return nil end,
    getCurrentSquare = function() return square end }
getSpecificPlayer = function(index) assert(index == 0); return actor end
local calls = {}
local fed = {}
KnoxCompanionService = {
    getPlayerId = function() return "owner" end,
    getCompanionIds = function() return {} end,
    issueOrder = function(player, id, kind)
        calls[#calls + 1] = kind
        if kind == "loot_area" then return false, "not_your_companion" end
        return true
    end,
}
KnoxPersistence = {
    getSurvivorAffiliation = function() return { kind = "player", ownerId = "owner" } end,
    getSurvivorDuty = function() return { mode = "companion", order = "follow" } end,
    isSurvivorHostileToPlayer = function() return false end,
    getSurvivorPolicies = function() return { allowClimbing = true } end,
}
KnoxSurvivorRuntime = { getCharacter = function() return actor end }
KnoxBaseManager = { getForOwner = function() return { id = "base" } end }
KnoxSettings = { enabled = function() return true end }
KnoxActivityFeed = { event = function(message) fed[#fed + 1] = message end }
local function newMenu()
    local menu = { options = {} }
    function menu:addOption(label, target, callback, ...)
        local option = { label = label, target = target, callback = callback, args = { ... } }
        self.options[label] = option
        return option
    end
    function menu:addSubMenu(option, sub) option.sub = sub end
    function menu:setOptionChecked(option, value) option.checked = value end
    return menu
end
ISContextMenu = { getNew = function() return newMenu() end, get = function() return newMenu() end }
dofile(root .. "/mod/42/media/lua/client/KS_OrderCatalog.lua")
local context = dofile(root .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua")

local menu = newMenu()
assert(context.populate(menu, 0, "companion"))
local climb = menu.options.Orders.sub.options["Tactics & Behavior"].sub
    .options["Vaulting and Climbing"].sub
assert(climb.options["Allow Vaulting and Climbing"].checked == true,
    "current climbing permission must show checked")
assert(climb.options["Disallow Vaulting and Climbing"].checked == false)
local allow = climb.options["Allow Vaulting and Climbing"]
allow.callback(allow.target, unpack(allow.args))
assert(calls[#calls] == "allow_climbing", "per-survivor allow must dispatch")
local deny = climb.options["Disallow Vaulting and Climbing"]
deny.callback(deny.target, unpack(deny.args))
assert(calls[#calls] == "disallow_climbing", "per-survivor disallow must dispatch")

-- Failed orders must explain themselves instead of silently doing nothing.
local loot = menu.options.Orders.sub.options["Loot Orders"].sub.options["Explore and Search"]
assert(loot ~= nil, "companion loot orders must be offered")
loot.callback(loot.target, unpack(loot.args))
assert(fed[#fed] ~= nil and string.find(fed[#fed], "not_your_companion", 1, true) ~= nil,
    "a rejected loot order must report its reason, got: " .. tostring(fed[#fed]))

print("Companion climb menu PASS toggle=true checked=true feedback=true")
