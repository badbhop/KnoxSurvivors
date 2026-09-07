require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "KS_CompanionService"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_SurvivorNotebook"
require "KS_OrderCatalog"
if rawget(_G, "KnoxOrderCatalog") == nil then
    _G.KnoxOrderCatalog = { label = function(_, fallback) return fallback or "Order" end }
end

local function catalogLabel(kind, fallback)
    local label = KnoxOrderCatalog.label ~= nil
        and KnoxOrderCatalog.label(kind, fallback) or nil
    return label ~= nil and label ~= "" and label or fallback or tostring(kind)
end

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
    KnoxCompanionService.issueOrderAll(player(playerNum), "follow")
end

function PartyCommands.formationAll(_, playerNum, formation, spacing)
    local actor = player(playerNum)
    local changed = 0
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(actor)) do
        if KnoxCompanionService.setFormation(actor, id, formation, spacing) then changed = changed + 1 end
    end
    if KnoxActivityFeed ~= nil then
        KnoxActivityFeed.event("Formation updated for " .. tostring(changed) .. " companions.")
    end
end

function PartyCommands.holdAll(_, playerNum)
    KnoxCompanionService.issueOrderAll(player(playerNum), "hold")
end

function PartyCommands.relaxAll(_, playerNum)
    KnoxCompanionService.issueOrderAll(player(playerNum), "relax")
end

function PartyCommands.askNeedsAll(_, playerNum)
    KnoxCompanionService.issueOrderAll(player(playerNum), "check_needs")
end

function PartyCommands.returnAll(_, playerNum)
    local actor = player(playerNum)
    KnoxCompanionService.issueOrderAll(actor, "return_to_base")
end

function PartyCommands.boardAll(_, playerNum)
    KnoxCompanionService.issueOrderAll(player(playerNum), "enter_vehicle")
end

function PartyCommands.exitAll(_, playerNum)
    KnoxCompanionService.issueOrderAll(player(playerNum), "exit_vehicle")
end

function PartyCommands.climbingAll(_, playerNum, allowed)
    KnoxCompanionService.issueOrderAll(
        player(playerNum),
        allowed and "allow_climbing" or "disallow_climbing"
    )
end

function PartyCommands.combatStanceAll(_, playerNum, stance)
    KnoxCompanionService.issueOrderAll(player(playerNum), "combat_stance", { stance = stance })
end

function PartyCommands.weaponPreferenceAll(_, playerNum, preference)
    KnoxCompanionService.issueOrderAll(player(playerNum), "weapon_preference", { preference = preference })
end

function PartyCommands.directiveAll(_, playerNum, directive)
    if directive ~= nil then
        KnoxCompanionService.issueOrderAll(
            player(playerNum), directive.kind, directive
        )
    end
end

function PartyCommands.basePreferenceAll(_, playerNum, preference)
    local actor = player(playerNum)
    if actor ~= nil and preference ~= nil then
        KnoxCompanionService.issueOrderAll(actor, preference)
    end
end

function PartyCommands.clearDirectiveAll(_, playerNum)
    KnoxCompanionService.issueOrderAll(player(playerNum), "resume_normal_duty")
end

function PartyCommands.openActivity()
    KnoxActivityFeed.show()
end

function PartyCommands.openNotebook(_, playerNum)
    KnoxSurvivorNotebook.show(playerNum)
end

function PartyCommands.openBaseSetup(_, playerNum)
    KnoxSurvivorNotebook.show(playerNum)
end

local function populate(menu, playerNum, square)
    local follow = menu:addOption(KnoxOrderCatalog.label("follow"), PartyCommands, PartyCommands.followAll, playerNum)
    local hold = menu:addOption(KnoxOrderCatalog.label("hold"), PartyCommands, PartyCommands.holdAll, playerNum)
    local relax = menu:addOption(KnoxOrderCatalog.label("relax"), PartyCommands, PartyCommands.relaxAll, playerNum)
    menu:addOption(KnoxOrderCatalog.label("check_needs"), PartyCommands, PartyCommands.askNeedsAll, playerNum)
    local actor = player(playerNum)
    local common = {}
    for index, id in ipairs(KnoxCompanionService.getCompanionIds(actor)) do
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        local policies = KnoxPersistence.getSurvivorPolicies(id) or {}
        local values = { order = duty.order or "follow", stance = duty.combatStance or "defensive",
            climbing = policies.allowClimbing ~= false, weapon = policies.weaponPreference or "auto" }
        for key, value in pairs(values) do
            if index == 1 then common[key] = value
            elseif common[key] ~= value then common[key] = nil end
        end
    end
    menu:setOptionChecked(follow, common.order == "follow")
    menu:setOptionChecked(hold, common.order == "hold")
    menu:setOptionChecked(relax, common.order == "relax")
    local resume = menu:addOption(KnoxOrderCatalog.label("resume_normal_duty"), PartyCommands,
        PartyCommands.clearDirectiveAll, playerNum)
    local hasDirective = false
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(actor)) do
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        if duty.directive ~= nil then hasDirective = true break end
    end
    resume.notAvailable = not hasDirective
    local playerId = actor ~= nil and KnoxCompanionService.getPlayerId(actor) or nil
    local baseManager = rawget(_G, "KnoxBaseManager")
    local base = baseManager ~= nil and playerId ~= nil
        and baseManager.getForOwner("player", playerId) or nil
    if base ~= nil then
        menu:addOption(KnoxOrderCatalog.label("return_to_base"), PartyCommands, PartyCommands.returnAll, playerNum)
        -- Keep settlement duty choices on the same canonical order catalogue
        -- used by the Notebook and resident scheduler. This is a player-facing
        -- convenience only; issueOrderAll remains the sole dispatch boundary.
        local baseOrders = menu:addOption(catalogLabel("base_work_orders", "Base Work Orders"), nil, nil)
        local baseOrderMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(baseOrders, baseOrderMenu)
        local sharedPreference = nil
        local sharedPreferenceSet = false
        if KnoxPersistence.getBaseResidentIds ~= nil
            and KnoxPersistence.getSurvivorDuty ~= nil then
            for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
                local duty = KnoxPersistence.getSurvivorDuty(residentId) or {}
                local preference = KnoxOrderCatalog.normalizeBasePreference ~= nil
                    and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference or "auto")
                    or KnoxOrderCatalog.normalize(duty.jobPreference or "auto")
                    or "auto"
                if not sharedPreferenceSet then
                    sharedPreference, sharedPreferenceSet = preference, true
                elseif sharedPreference ~= preference then
                    sharedPreference = nil
                    break
                end
            end
        end
        for _, preference in ipairs(KnoxOrderCatalog.basePreferenceOrder or {}) do
            local entry = KnoxOrderCatalog.basePreferences[preference]
            if entry ~= nil then
                local label = preference == "woodwork" and "Woodwork / Barricade Windows"
                    or preference == "hauling" and "Move Corpses"
                    or entry.label
                local option = baseOrderMenu:addOption(label, PartyCommands,
                    PartyCommands.basePreferenceAll, playerNum, preference)
                baseOrderMenu:setOptionChecked(option, sharedPreference == preference)
            end
        end
    end
    -- Keep Exit reachable after the player has already stepped out. Vehicle
    -- actions validate each companion and seat at the existing service boundary.
    if actor ~= nil then
        local vehicleRoot = menu:addOption(catalogLabel("vehicle_orders", "Vehicle Orders"), nil, nil)
        local vehicleMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(vehicleRoot, vehicleMenu)
        local board = vehicleMenu:addOption(KnoxOrderCatalog.label("enter_vehicle"), PartyCommands, PartyCommands.boardAll, playerNum)
        board.notAvailable = actor.getVehicle == nil or actor:getVehicle() == nil
        vehicleMenu:addOption(KnoxOrderCatalog.label("exit_vehicle"), PartyCommands, PartyCommands.exitAll, playerNum)
    end
    local traversal = menu:addOption(catalogLabel("traversal_orders", "Vaulting and Climbing"), nil, nil)
    local traversalMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(traversal, traversalMenu)
    local allow = traversalMenu:addOption(KnoxOrderCatalog.label("allow_climbing"), PartyCommands, PartyCommands.climbingAll, playerNum, true)
    local disallow = traversalMenu:addOption(KnoxOrderCatalog.label("disallow_climbing"), PartyCommands, PartyCommands.climbingAll, playerNum, false)
    traversalMenu:setOptionChecked(allow, common.climbing == true)
    traversalMenu:setOptionChecked(disallow, common.climbing == false)
    local formation = menu:addOption("Formation", nil, nil)
    local formationMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(formation, formationMenu)
    for _, shape in ipairs({ { "Paired", "paired" }, { "Single File", "single_file" } }) do
        for spacing = 1, 3 do
            formationMenu:addOption(shape[1] .. " - spacing " .. tostring(spacing), PartyCommands,
                PartyCommands.formationAll, playerNum, shape[2], spacing)
        end
    end
    local combat = menu:addOption(catalogLabel("combat_stance", "Combat Stance"), nil, nil)
    local combatMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(combat, combatMenu)
    for _, choice in ipairs({ { "Passive - stay close", "passive" },
        { "Defensive - protect us", "defensive" }, { "Aggressive - clear threats", "aggressive" } }) do
        local option = combatMenu:addOption(choice[1], PartyCommands,
            PartyCommands.combatStanceAll, playerNum, choice[2])
        combatMenu:setOptionChecked(option, common.stance == choice[2])
    end
    local weapon = menu:addOption(catalogLabel("weapon_preference", "Weapon Preference"), nil, nil)
    local weaponMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(weapon, weaponMenu)
    for _, choice in ipairs({ { "Prefer Melee", "melee" }, { "Prefer Ranged", "ranged" },
        { "Survivor Choice", "auto" } }) do
        local option = weaponMenu:addOption(choice[1], PartyCommands,
            PartyCommands.weaponPreferenceAll, playerNum, choice[2])
        weaponMenu:setOptionChecked(option, common.weapon == choice[2])
    end
    if square ~= nil then
        menu:addOption(catalogLabel("move_party", "Move Party Here"), PartyCommands, PartyCommands.directiveAll,
            playerNum, pointDirective("go_to", square))
        menu:addOption(catalogLabel("guard_location", "Guard This Location"), PartyCommands, PartyCommands.directiveAll,
            playerNum, pointDirective("guard", square))
        menu:addOption(catalogLabel("patrol_location", "Patrol This Area"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("patrol_area", square, 10))
        local loot = menu:addOption(catalogLabel("loot_orders", "Loot Orders"), nil, nil)
        local lootMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(loot, lootMenu)
        lootMenu:addOption(KnoxOrderCatalog.label("loot_area"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("loot_area", square, 10))
        lootMenu:addOption(KnoxOrderCatalog.label("loot_corpses"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("loot_corpses", square, 15))
        local building = buildingDirective(square)
        local buildingOption = lootMenu:addOption(KnoxOrderCatalog.label("loot_building"), PartyCommands,
            PartyCommands.directiveAll, playerNum, building)
        if building == nil then
            buildingOption.notAvailable = true
        end
        local survival = menu:addOption(catalogLabel("survival_orders", "Survival Orders"), nil, nil)
        local survivalMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(survival, survivalMenu)
        survivalMenu:addOption(KnoxOrderCatalog.label("find_food"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("find_food", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_water"), PartyCommands, PartyCommands.directiveAll,
            playerNum, areaDirective("find_water", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_medical"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("find_medical", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_weapon"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("find_weapon", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("find_tools"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("find_tools", square, 12))
        survivalMenu:addOption(KnoxOrderCatalog.label("clean_inventory"), PartyCommands,
            PartyCommands.directiveAll, playerNum, areaDirective("clean_inventory", square, 12))
    end
    menu:addOption("Show Activity Feed", PartyCommands, PartyCommands.openActivity)
        menu:addOption(KnoxOrderCatalog.label("open_notebook"), PartyCommands,
        PartyCommands.openNotebook, playerNum)
    if base ~= nil then
        menu:addOption(KnoxOrderCatalog.label("open_base"), PartyCommands,
            PartyCommands.openBaseSetup, playerNum)
    end
    return menu
end

local function hasPlayerBaseResidents(actor)
    if actor == nil or KnoxPersistence == nil
        or KnoxPersistence.getBaseResidentIds == nil then
        return false
    end
    local playerId = KnoxCompanionService.getPlayerId(actor)
    local manager = rawget(_G, "KnoxBaseManager")
    local base = manager ~= nil and playerId ~= nil
        and manager.getForOwner("player", playerId) or nil
    return base ~= nil and #KnoxPersistence.getBaseResidentIds(base.id) > 0
end

function PartyCommands.openMenu(playerNum, x, y, square)
    return populate(ISContextMenu.get(playerNum, x, y), playerNum, square)
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not KnoxSettings.enabled() then
        return
    end
    local actor = player(playerNum)
    if actor == nil
        or (#KnoxCompanionService.getCompanionIds(actor) == 0
            and not hasPlayerBaseResidents(actor)) then
        return
    end
    local square = firstSquare(worldObjects)
    if square == nil then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    local root = context:addOption(catalogLabel("party_orders", "Party Orders"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)
    populate(menu, playerNum, square)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

return PartyCommands
