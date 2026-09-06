local root = arg[1] or "."
require = function() end
Events = { OnFillWorldObjectContextMenu = { Add = function() end },
    OnTick = { Add = function() end, Remove = function() end } }
local actor = { getPlayerNum = function() return 0 end,
    getX = function() return 10 end, getY = function() return 10 end,
    getZ = function() return 0 end, getVehicle = function() return nil end }
getSpecificPlayer = function(index) assert(index == 0); return actor end
local calls = {}
KnoxCompanionService = {
    getPlayerId = function() return "owner" end,
    getCompanionIds = function() return {} end,
    issueOrder = function(player, id, kind)
        assert(player == actor and id == "resident")
        calls[#calls + 1] = kind; return true
    end,
    issueOrderAll = function(player, kind)
        assert(player == actor); calls[#calls + 1] = kind; return true
    end,
}
KnoxPersistence = {
    getSurvivorAffiliation = function() return { kind = "player", ownerId = "owner" } end,
    getSurvivorDuty = function() return { mode = "base", baseId = "base", jobPreference = "auto" } end,
    isSurvivorHostileToPlayer = function() return false end,
    getBaseResidentIds = function() return { "resident" } end,
}
KnoxSurvivorRuntime = { getCharacter = function() return actor end }
KnoxBaseManager = { getForOwner = function() return { id = "base" } end }
KnoxSettings = { enabled = function() return true end }
local function newMenu()
    local menu = { options = {} }
    function menu:addOption(label, target, callback, ...)
        assert(callback == nil or type(callback) == "function", "invalid callback for " .. label)
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
assert(context.populate(menu, 0, "resident"))
local work = menu.options.Orders.sub.options["Base Work Orders"].sub
local barricade = work.options["Woodwork / Barricade Windows"]
assert(barricade and barricade.callback)
barricade.callback(barricade.target, unpack(barricade.args))
assert(calls[#calls] == "woodwork", "resident menu must dispatch the correct player, survivor and order")
local corpses = work.options["Haul Supplies / Move Corpses"]
corpses.callback(corpses.target, unpack(corpses.args))
assert(calls[#calls] == "hauling")

local party = dofile(root .. "/mod/42/media/lua/client/KS_PartyCommands.lua")
local formationCall
KnoxCompanionService.setFormation = function(player, id, shape, spacing)
    assert(player == actor and id == "resident")
    formationCall = { shape = shape, spacing = spacing }; return true
end
KnoxPersistence.getSurvivorDuty = function() return { mode = "companion", order = "follow" } end
KnoxPersistence.getSurvivorPolicies = function() return {} end
actor.getCurrentSquare = function() return nil end
local personal = newMenu()
assert(context.populate(personal, 0, "resident"))
local choice = personal.options.Orders.sub.options.Formation.sub.options["Single File - spacing 3"]
choice.callback(choice.target, unpack(choice.args))
assert(formationCall.shape == "single_file" and formationCall.spacing == 3)
KnoxCompanionService.getCompanionIds = function() return { "resident" } end
KnoxActivityFeed = { event = function() end }
local formationParty = party.openMenu(0, 0, 0, nil)
choice = formationParty.options.Formation.sub.options["Paired - spacing 2"]
choice.callback(choice.target, unpack(choice.args))
assert(formationCall.shape == "paired" and formationCall.spacing == 2,
    "party menu routes formation and spacing to each owned companion")
menu = party.openMenu(0, 0, 0, nil)
local vehicle = menu.options["Vehicle Orders"].sub
assert(vehicle.options["Get In My Vehicle"].notAvailable,
    "boarding needs the leader's vehicle")
local exit = vehicle.options["Get Out of Vehicles"]
assert(exit and not exit.notAvailable, "party exit must remain usable after leader leaves car")
exit.callback(exit.target, unpack(exit.args))
assert(calls[#calls] == "exit_vehicle")

local selection, saved
local cell = { setDrag = function(_, cursor) selection = cursor.selection end }
getCell = function() return cell end
ISSelectCursor = { new = function(_, player, receiver, callback)
    assert(player == actor); return { selection = receiver, callback = callback }
end }
KnoxActivityFeed = { event = function() end }
KnoxBaseHighlights = { setDraft = function() end }
KnoxBaseManager.addZone = function(baseId, kind, bounds, label)
    assert(baseId == "base" and kind == "guard")
    saved = bounds; return { id = "post" }, "created"
end
local selector = dofile(root .. "/mod/42/media/lua/client/KS_BaseZoneSelector.lua")
assert(selector.start(actor, "base", "guard", "Guard Post"))
selection:onSquareSelected(actor)
assert(saved and saved.x1 == 10 and saved.x2 == 10 and saved.y1 == 10 and saved.y2 == 10,
    "one click must save exactly one tile without a second corner or modal")
assert(selection.firstSquare == nil and not selection.pendingConfirm)
print("Order menu callbacks PASS resident_dispatch=true exit_after_leader=true one_click_guard=true")
