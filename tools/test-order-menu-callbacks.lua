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
assert(menu.options.Follow ~= nil and menu.options.Recruit == nil,
    "owned base residents must offer Follow, never first-time Recruit")
local work = menu.options.Orders.sub.options["Base Work Orders"].sub
local woodwork = work.options["Woodwork"]
assert(woodwork and woodwork.callback)
woodwork.callback(woodwork.target, unpack(woodwork.args))
assert(calls[#calls] == "woodwork", "resident menu must dispatch the correct player, survivor and order")
local barricade = work.options["Barricade Windows"]
assert(barricade and barricade.callback)
barricade.callback(barricade.target, unpack(barricade.args))
assert(calls[#calls] == "barricade", "barricade duty must be orderable")
assert(work.options["Build Defenses"] == nil, "construction retired from resident menu")
local corpses = work.options["Move Corpses"]
corpses.callback(corpses.target, unpack(corpses.args))
assert(calls[#calls] == "hauling")

local lootRuns = menu.options.Orders.sub.options["Loot Runs"].sub
assert(lootRuns.options["Allow Loot Runs"] and lootRuns.options["Stay Home"],
    "resident loot runs must be an explicit per-resident order")
KnoxCompanionService.setResidentLootRuns = function(player, id, allowed)
    assert(player == actor and id == "resident")
    calls[#calls + 1] = allowed and "loot_runs_allowed" or "loot_runs_stay_home"
    return true
end
local allow = lootRuns.options["Allow Loot Runs"]
allow.callback(allow.target, unpack(allow.args))
assert(calls[#calls] == "loot_runs_allowed", "allowing loot runs must dispatch")
local stay = lootRuns.options["Stay Home"]
stay.callback(stay.target, unpack(stay.args))
assert(calls[#calls] == "loot_runs_stay_home", "staying home must dispatch")

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
local choice = personal.options.Orders.sub.options["Tactics & Behavior"].sub
    .options.Formation.sub.options["Single File - spacing 3"]
choice.callback(choice.target, unpack(choice.args))
assert(formationCall.shape == "single_file" and formationCall.spacing == 3)
KnoxCompanionService.getCompanionIds = function() return { "resident" } end
KnoxActivityFeed = { event = function() end }
local formationParty = party.openMenu(0, 0, 0, nil)
choice = formationParty.options["Tactics & Behavior"].sub
    .options.Formation.sub.options["Paired - spacing 2"]
choice.callback(choice.target, unpack(choice.args))
assert(formationCall.shape == "paired" and formationCall.spacing == 2,
    "party menu routes formation and spacing to each owned companion")
menu = party.openMenu(0, 0, 0, nil)
local vehicle = menu.options["Vehicle Orders"].sub
assert(vehicle.options["Take Passenger Seat"].notAvailable,
    "boarding needs the leader's vehicle")
local exit = vehicle.options["Exit Vehicle"]
assert(exit and not exit.notAvailable, "party exit must remain usable after leader leaves car")
exit.callback(exit.target, unpack(exit.args))
assert(calls[#calls] == "exit_vehicle")

local selection, saved
local cell = { setDrag = function(_, cursor) selection = cursor.selection end }getCell = function() return cell end
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

local partyFed = {}
KnoxActivityFeed = { event = function(message) partyFed[#partyFed + 1] = message end }
KnoxCompanionService.issueOrderAll = function() return false, 0 end
party.directiveAll(nil, 0, { kind = "loot_area" })
assert(partyFed[#partyFed] ~= nil
    and string.find(partyFed[#partyFed], "no companion could take it", 1, true) ~= nil,
    "a party order nobody takes must say so")
print("Order menu callbacks PASS resident_dispatch=true exit_after_leader=true one_click_guard=true party_feedback=true")
