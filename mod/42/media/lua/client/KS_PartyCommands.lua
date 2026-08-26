require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "KS_CompanionService"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_SurvivorNotebook"
require "KS_BaseSetup"

local PartyCommands = rawget(_G, "KnoxPartyCommands") or {}
_G.KnoxPartyCommands = PartyCommands

local function firstSquare(worldObjects)
    for _, object in ipairs(worldObjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        if square ~= nil then
            return square
        end
    end
    return nil
end

local function areaDirective(kind, square, radius)
    return {
        kind = kind,
        minX = square:getX() - radius,
        minY = square:getY() - radius,
        maxX = square:getX() + radius,
        maxY = square:getY() + radius,
        z = square:getZ(),
    }
end

local function pointDirective(kind, square)
    return {
        kind = kind,
        minX = square:getX(),
        minY = square:getY(),
        maxX = square:getX(),
        maxY = square:getY(),
        z = square:getZ(),
    }
end

local function buildingDirective(square)
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil then
        return nil
    end
    return {
        kind = "loot_building",
        buildingId = tostring(definition:getID()),
        minX = definition:getX(),
        minY = definition:getY(),
        maxX = definition:getX() + definition:getW() - 1,
        maxY = definition:getY() + definition:getH() - 1,
        z = square:getZ(),
    }
end

local function player(playerNum)
    return getSpecificPlayer(tonumber(playerNum) or 0)
end

function PartyCommands.followAll(_, playerNum)
    KnoxCompanionService.commandAll(player(playerNum), "follow")
end

function PartyCommands.holdAll(_, playerNum)
    KnoxCompanionService.commandAll(player(playerNum), "hold")
end

function PartyCommands.returnAll(_, playerNum)
    local actor = player(playerNum)
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(actor)) do
        KnoxCompanionService.sendToBase(actor, id)
    end
end

function PartyCommands.climbingAll(_, playerNum, allowed)
    KnoxCompanionService.setClimbingAll(player(playerNum), allowed)
end

function PartyCommands.directiveAll(_, playerNum, directive)
    KnoxCompanionService.issueDirectiveAll(player(playerNum), directive)
end

function PartyCommands.openActivity()
    KnoxActivityFeed.show()
end

function PartyCommands.openNotebook(_, playerNum)
    KnoxSurvivorNotebook.show(playerNum)
end

function PartyCommands.openBaseSetup(_, playerNum)
    KnoxBaseSetup.show(playerNum)
end

local function populate(menu, playerNum, square)
    menu:addOption("Regroup and Follow", PartyCommands, PartyCommands.followAll, playerNum)
    menu:addOption("Hold Position", PartyCommands, PartyCommands.holdAll, playerNum)
    local actor = player(playerNum)
    local playerId = actor ~= nil and KnoxCompanionService.getPlayerId(actor) or nil
    local baseManager = rawget(_G, "KnoxBaseManager")
    local base = baseManager ~= nil and playerId ~= nil
        and baseManager.getForOwner("player", playerId) or nil
    if base ~= nil then
        menu:addOption("Return to Home Base", PartyCommands, PartyCommands.returnAll, playerNum)
    end
    local traversal = menu:addOption("Vaulting and Climbing", nil, nil)
    local traversalMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(traversal, traversalMenu)
    traversalMenu:addOption("Allow", PartyCommands, PartyCommands.climbingAll, playerNum, true)
    traversalMenu:addOption("Disallow", PartyCommands, PartyCommands.climbingAll, playerNum, false)
    if square ~= nil then
        menu:addOption("Move Party Here", PartyCommands, PartyCommands.directiveAll,
            playerNum, pointDirective("go_to", square))
        menu:addOption("Guard This Location", PartyCommands, PartyCommands.directiveAll,
            playerNum, pointDirective("guard", square))
        local loot = menu:addOption("Loot Orders", nil, nil)
        local lootMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(loot, lootMenu)
        lootMenu:addOption("Loot Nearby Area", PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("loot_area", square, 10))
        lootMenu:addOption("Loot Dead Bodies", PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("loot_corpses", square, 15))
        local building = buildingDirective(square)
        local buildingOption = lootMenu:addOption("Loot This Building", PartyCommands,
            PartyCommands.directiveAll, playerNum, building)
        if building == nil then
            buildingOption.notAvailable = true
        end
    end
    menu:addOption("Show Activity Feed", PartyCommands, PartyCommands.openActivity)
    menu:addOption("Open Survivor Notebook", PartyCommands,
        PartyCommands.openNotebook, playerNum)
    if base ~= nil then
        menu:addOption("Open Base Setup", PartyCommands,
            PartyCommands.openBaseSetup, playerNum)
    end
    return menu
end

function PartyCommands.openMenu(playerNum, x, y, square)
    return populate(ISContextMenu.get(playerNum, x, y), playerNum, square)
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not KnoxSettings.enabled() then
        return
    end
    local actor = player(playerNum)
    if actor == nil or #KnoxCompanionService.getCompanionIds(actor) == 0 then
        return
    end
    local square = firstSquare(worldObjects)
    if square == nil then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    local root = context:addOption("Party Orders", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    populate(menu, playerNum, square)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

return PartyCommands
