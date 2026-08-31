require "ISUI/ISContextMenu"
require "ISUI/ISModalDialog"
require "ISUI/ISWorldObjectContextMenu"
require "XpSystem/ISUI/ISHealthPanel"
require "TimedActions/ISMedicalCheckAction"
require "TimedActions/WalkToTimedAction"
require "KS_CompanionService"
require "KS_BaseManager"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"
require "KS_SurvivorCard"
require "KS_CompanionInventory"
require "KS_Settings"
require "KS_TradeUI"

local SurvivorContextMenu = rawget(_G, "KnoxSurvivorContextMenu") or {}
_G.KnoxSurvivorContextMenu = SurvivorContextMenu

local WORLD_PICK_RADIUS = 2.25
local CONVERSATION_DISTANCE = 4

local function refreshHud(playerNum)
    local hud = rawget(_G, "KnoxCompanionHUD")
    if hud ~= nil and hud.refresh ~= nil then
        hud.refresh(playerNum)
    end
end

local function runService(playerNum, callback, survivorId)
    local player = getSpecificPlayer(playerNum)
    if player == nil then
        return false, "player_unavailable"
    end
    local success, result, reason = pcall(callback, player, survivorId)
    if not success then
        print(
            "[KnoxSurvivors][ContextMenu] action failed survivor="
                .. tostring(survivorId) .. " error=" .. tostring(result)
        )
        return false, tostring(result)
    end
    refreshHud(playerNum)
    return result == true, reason
end

local function distanceToPlayer(player, survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if player == nil or character == nil then
        return nil
    end
    local success, distance = pcall(function()
        local dx = player:getX() - character:getX()
        local dy = player:getY() - character:getY()
        if player:getZ() ~= character:getZ() then
            return math.huge
        end
        return math.sqrt(dx * dx + dy * dy)
    end)
    return success and distance or nil
end

local function unavailable(option)
    if option ~= nil then
        option.notAvailable = true
    end
    return option
end

local function onTalk(_, playerNum, survivorId)
    runService(playerNum, KnoxCompanionService.talk, survivorId)
end

local function onTrade(_, playerNum, survivorId)
    KnoxTradeUI.show(playerNum, survivorId)
end

local function onViewSurvivor(_, playerNum, survivorId)
    KnoxSurvivorCard.show(playerNum, survivorId)
end

local function medicalMessage(player, survivorId, reason)
    print("[KnoxSurvivors][Medical] survivor=" .. tostring(survivorId) .. " " .. reason)
    if player ~= nil then player:Say(reason) end
    return false, reason
end

local function medicalReach(player, patient)
    if ISHealthPanel.IsCharactersInSameCar(player, patient) then return true end
    local from, to = player:getCurrentSquare(), patient:getCurrentSquare()
    return from ~= nil and to ~= nil and player:getZ() == patient:getZ()
        and math.abs(player:getX() - patient:getX()) <= 2
        and math.abs(player:getY() - patient:getY()) <= 2
        and (from == to or from:canReachTo(to))
end

function SurvivorContextMenu.medicalCheck(playerNum, survivorId)
    local player = getSpecificPlayer(playerNum)
    local patient = KnoxSurvivorRuntime.getCharacter(survivorId)
    if player == nil or patient == nil or player:isDead() or patient:isDead() then
        return medicalMessage(player, survivorId, "That survivor is no longer available.")
    end
    local queue = ISTimedActionQueue.queues[player]
    for _, pending in ipairs(queue ~= nil and queue.queue or {}) do
        if pending.knoxMedicalPatient == patient then return true, "already_queued" end
    end
    local sameCar = ISHealthPanel.IsCharactersInSameCar(player, patient)
    local square = patient:getCurrentSquare()
    if not sameCar and (square == nil or player:getZ() ~= patient:getZ()
        or (distanceToPlayer(player, survivorId) or math.huge) > CONVERSATION_DISTANCE
        or not luautils.walkAdjTest(player, square)) then
        return medicalMessage(player, survivorId, "I need to get closer to check them.")
    end
    -- Keep the existing explicit Hold for owned companions. Never call vanilla
    -- canPerformMedicalCheck here: it queues the PATIENT to walk to the doctor.
    runService(playerNum, function(p, id)
        return KnoxCompanionService.command(p, id, "hold")
    end, survivorId)

    if not sameCar and not luautils.walkAdj(player, square) then
        return medicalMessage(player, survivorId, "I can't reach them from here.")
    end
    local action = ISMedicalCheckAction:new(player, patient)
    action.knoxMedicalPatient = patient
    local nativeValid, nativeStart, nativeStop = action.isValid, action.start, action.stop
    local nativePerform = action.perform
    local function available()
        return KnoxSurvivorRuntime.getCharacter(survivorId) == patient
            and not player:isDead() and not patient:isDead() and medicalReach(player, patient)
    end
    function action:isValid()
        -- Snapshot at action start, not before the doctor has finished walking.
        if not self.knoxMedicalStarted then
            self.otherPlayerX, self.otherPlayerY = patient:getX(), patient:getY()
        end
        local valid = available() and nativeValid(self)
        if not valid and not self.knoxMedicalReported then
            self.knoxMedicalReported = true
            medicalMessage(player, survivorId, "Medical check interrupted. Stay close and try again.")
        end
        return valid
    end
    function action:start()
        self.otherPlayerX, self.otherPlayerY = patient:getX(), patient:getY()
        self.knoxMedicalStarted = true
        nativeStart(self)
    end
    function action:stop()
        if not self.knoxMedicalReported then
            self.knoxMedicalReported = true
            medicalMessage(player, survivorId, "Medical check cancelled.")
        end
        nativeStop(self)
    end
    function action:perform()
        if not self:isValid() then nativeStop(self); return end
        nativePerform(self)
        print("[KnoxSurvivors][Medical] survivor=" .. tostring(survivorId) .. " check_completed")
    end
    ISTimedActionQueue.add(action)
    print("[KnoxSurvivors][Medical] survivor=" .. tostring(survivorId) .. " check_queued")
    return true, "queued"
end

local function onMedicalCheck(_, playerNum, survivorId)
    SurvivorContextMenu.medicalCheck(playerNum, survivorId)
end

local function onManageInventory(_, playerNum, survivorId)
    KnoxCompanionInventory.show(playerNum, survivorId)
end

local function onRecruit(_, playerNum, survivorId)
    runService(playerNum, KnoxCompanionService.recruit, survivorId)
end

local function onFollow(_, playerNum, survivorId)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    local callback = duty.mode == "base"
        and KnoxCompanionService.activateFromBase
        or function(player, id)
            return KnoxCompanionService.command(player, id, "follow")
        end
    runService(playerNum, callback, survivorId)
end

local function onHold(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.command(player, id, "hold")
    end, survivorId)
end

local function onCombatStance(_, playerNum, survivorId, stance)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.setCombatStance(player, id, stance)
    end, survivorId)
end

local function onWeaponPreference(_, playerNum, survivorId, preference)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.setWeaponPreference(player, id, preference)
    end, survivorId)
end

local function onBoardPlayerVehicle(_, playerNum, survivorId)
    runService(playerNum, KnoxCompanionService.boardPlayerVehicle, survivorId)
end

local function onExitVehicle(_, playerNum, survivorId)
    runService(playerNum, KnoxCompanionService.exitVehicle, survivorId)
end

local function pointDirective(kind, square)
    if square == nil then
        return nil
    end
    return {
        kind = kind,
        minX = square:getX(),
        minY = square:getY(),
        maxX = square:getX(),
        maxY = square:getY(),
        z = square:getZ(),
    }
end

local function areaDirective(kind, square, radius)
    if square == nil then return nil end
    local r = math.max(1, tonumber(radius) or 10)
    return {
        kind = kind,
        minX = square:getX() - r,
        minY = square:getY() - r,
        maxX = square:getX() + r,
        maxY = square:getY() + r,
        z = square:getZ(),
    }
end

local function buildingDirective(square)
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil then return nil end
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

local function onLootOrder(_, playerNum, survivorId, directive)
    if directive == nil then return end
    runService(playerNum, function(player, id)
        return KnoxCompanionService.issueDirective(player, id, directive)
    end, survivorId)
end

local function onMoveToPlayer(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        local directive = pointDirective("go_to", player:getCurrentSquare())
        return directive ~= nil and KnoxCompanionService.issueDirective(player, id, directive)
    end, survivorId)
end

local function onGuardHere(_, playerNum, survivorId)
    runService(playerNum, function(player, id)
        local character = KnoxSurvivorRuntime.getCharacter(id)
        local directive = pointDirective("guard",
            character ~= nil and character:getCurrentSquare() or nil)
        return directive ~= nil and KnoxCompanionService.issueDirective(player, id, directive)
    end, survivorId)
end

local function onReturnToBase(_, playerNum, survivorId)
    runService(playerNum, KnoxCompanionService.sendToBase, survivorId)
end

local function onFinishInventory(_, playerNum, survivorId)
    if KnoxCompanionInventory ~= nil and KnoxCompanionInventory.finish ~= nil then
        KnoxCompanionInventory.finish(playerNum)
    elseif KnoxCompanionInventory ~= nil and KnoxCompanionInventory.clear ~= nil then
        KnoxCompanionInventory.clear(playerNum)
        if ISInventoryPage ~= nil and ISInventoryPage.dirtyUI ~= nil then ISInventoryPage.dirtyUI() end
    end
end

local function onBaseJobPreference(_, playerNum, survivorId, preference)
    runService(playerNum, function(player, id)
        return KnoxCompanionService.setBaseJobPreference(player, id, preference)
    end, survivorId)
end

local function onDismissConfirmed(_, button, playerNum, survivorId)
    if button == nil or button.internal ~= "YES" then
        return
    end
    runService(playerNum, KnoxCompanionService.dismiss, survivorId)
end

local function onDismiss(_, playerNum, survivorId)
    local snapshot = KnoxSurvivorViewModel.getSurvivor(survivorId, playerNum)
    local name = snapshot ~= nil and snapshot.displayName or "this survivor"
    local width = 320
    local height = 120
    local x = getPlayerScreenLeft(playerNum)
        + (getPlayerScreenWidth(playerNum) - width) / 2
    local y = getPlayerScreenTop(playerNum)
        + (getPlayerScreenHeight(playerNum) - height) / 2
    local modal = ISModalDialog:new(
        x,
        y,
        width,
        height,
        "Tell " .. name .. " to leave your group?",
        true,
        SurvivorContextMenu,
        onDismissConfirmed,
        playerNum,
        playerNum,
        survivorId
    )
    modal:initialise()
    modal:setRenderThisPlayerOnly(playerNum)
    modal:addToUIManager()
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, modal)
    end
end

local function addRecruitOption(menu, player, survivorId, closeEnough)
    local success, ready, reason = pcall(
        KnoxCompanionService.canRecruit,
        player,
        survivorId
    )
    if not success then
        ready = false
        reason = "unavailable"
    end
    if ready and closeEnough then
        return menu:addOption("Recruit", SurvivorContextMenu, onRecruit, player:getPlayerNum(), survivorId)
    end

    local label = "Recruit"
    if not closeEnough then
        label = "Recruit (too far away)"
    elseif reason == "hostile" then
        label = "Recruit (hostile)"
    elseif reason == "needs_trust" then
        label = "Recruit (not ready)"
    elseif reason == "already_with_group" then
        label = "Recruit (already with a group)"
    else
        label = "Recruit (not available)"
    end
    return unavailable(menu:addOption(label, nil, nil))
end

function SurvivorContextMenu.populate(menu, playerNum, survivorId)
    local player = getSpecificPlayer(playerNum)
    if menu == nil or player == nil or type(survivorId) ~= "string" then
        return false
    end

    local playerId = KnoxCompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId) or {}
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    local owned = affiliation.kind == "player" and affiliation.ownerId == playerId
    if owned and duty.mode == "companion" then
        menu:addOption(
            "View Survivor",
            SurvivorContextMenu,
            onViewSurvivor,
            playerNum,
            survivorId
        )
    end

    local distance = distanceToPlayer(player, survivorId)
    local closeEnough = distance ~= nil and distance <= CONVERSATION_DISTANCE
    local hostile = playerId ~= nil and KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId)
    local talkLabel = hostile and "Talk (hostile)" or (closeEnough and "Talk" or "Talk (too far away)")
    local talk = menu:addOption(talkLabel, SurvivorContextMenu, onTalk, playerNum, survivorId)
    if not closeEnough or hostile then
        unavailable(talk)
    end

    if not owned then
        if affiliation.kind ~= "player" then
            local enabled = closeEnough and not hostile and not isClient() and not isServer()
            local label = hostile and "Trade (hostile)" or (closeEnough and "Trade" or "Trade (too far away)")
            if isClient() or isServer() then label = "Trade (single-player only)" end
            local trade = menu:addOption(label, SurvivorContextMenu, onTrade, playerNum, survivorId)
            if not enabled then unavailable(trade) end
        end
        addRecruitOption(menu, player, survivorId, closeEnough)
        return true
    end

    if duty.mode == "companion" then
        local inventoryLabel = closeEnough and "Manage Inventory"
            or "Manage Inventory (too far away)"
        local inventory = menu:addOption(
            inventoryLabel,
            SurvivorContextMenu,
            onManageInventory,
            playerNum,
            survivorId
        )
        if not closeEnough then
            unavailable(inventory)
        end
        -- Medical Check lives inside Orders to reduce top-level clutter;
        -- still reachable via Survivor Name -> Orders -> Medical Check.
    end

    if duty.mode == "base" then
        -- Keep quick Follow at top for base residents, but group job prefs under Orders
        menu:addOption("Follow", SurvivorContextMenu, onFollow, playerNum, survivorId)
        local orders = menu:addOption("Orders", nil, nil)
        local ordersMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(orders, ordersMenu)
        local jobs = ordersMenu:addOption("Base Job Preference", nil, nil)
        local jobsMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(jobs, jobsMenu)
        local choices = {
            { "Automatic", "auto" }, { "Guard", "guard" }, { "Patrol", "patrol" },
            { "Farming", "farming" }, { "Woodwork & Defense", "woodwork" },
            { "Hauling & Sorting", "hauling" }, { "Animal Care", "animal_care" },
            { "Repair", "repair" },
        }
        for _, choice in ipairs(choices) do
            local option = jobsMenu:addOption(choice[1], SurvivorContextMenu,
                onBaseJobPreference, playerNum, survivorId, choice[2])
            jobsMenu:setOptionChecked(option, duty.jobPreference == choice[2]
                or (duty.jobPreference == nil and choice[2] == "auto"))
        end
        ordersMenu:addOption("Done", SurvivorContextMenu, onFinishInventory, playerNum, survivorId)
    elseif duty.mode == "companion" then
        local orders = menu:addOption("Orders", nil, nil)
        local ordersMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(orders, ordersMenu)
        local follow = ordersMenu:addOption("Follow", SurvivorContextMenu, onFollow, playerNum, survivorId)
        local hold = ordersMenu:addOption("Hold here", SurvivorContextMenu, onHold, playerNum, survivorId)
        ordersMenu:setOptionChecked(follow, duty.order == "follow")
        ordersMenu:setOptionChecked(hold, duty.order == "hold")
        ordersMenu:addOption("Move to Me", SurvivorContextMenu, onMoveToPlayer, playerNum, survivorId)
        ordersMenu:addOption("Guard Here", SurvivorContextMenu, onGuardHere, playerNum, survivorId)
        local companion = KnoxSurvivorRuntime.getCharacter(survivorId)
        if companion ~= nil and companion:getVehicle() ~= nil then
            ordersMenu:addOption("Exit Vehicle", SurvivorContextMenu,
                onExitVehicle, playerNum, survivorId)
        elseif player:getVehicle() ~= nil then
            ordersMenu:addOption("Enter My Vehicle", SurvivorContextMenu,
                onBoardPlayerVehicle, playerNum, survivorId)
        end
        local stanceRoot = ordersMenu:addOption("Combat Stance", nil, nil)
        local stanceMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(stanceRoot, stanceMenu)
        local stance = duty.combatStance or "defensive"
        for _, choice in ipairs({
            { "Passive — stay close", "passive" },
            { "Defensive — protect us", "defensive" },
            { "Aggressive — clear threats", "aggressive" },
        }) do
            local option = stanceMenu:addOption(choice[1], SurvivorContextMenu,
                onCombatStance, playerNum, survivorId, choice[2])
            stanceMenu:setOptionChecked(option, stance == choice[2])
        end
        local weaponRoot = ordersMenu:addOption("Weapon Preference", nil, nil)
        local weaponMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(weaponRoot, weaponMenu)
        local weaponPolicies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
        for _, choice in ipairs({ { "Prefer Melee", "melee" }, { "Prefer Ranged", "ranged" },
            { "Survivor Choice", "auto" } }) do
            local option = weaponMenu:addOption(choice[1], SurvivorContextMenu,
                onWeaponPreference, playerNum, survivorId, choice[2])
            weaponMenu:setOptionChecked(option, (weaponPolicies.weaponPreference or "auto") == choice[2])
        end
        local medicalLabel = closeEnough and "Medical Check" or "Medical Check (too far away)"
        local medical = ordersMenu:addOption(medicalLabel, SurvivorContextMenu, onMedicalCheck, playerNum, survivorId)
        if not closeEnough then unavailable(medical) end
        local lootRoot = ordersMenu:addOption("Loot Orders", nil, nil)
        local lootMenu = ISContextMenu:getNew(ordersMenu)
        ordersMenu:addSubMenu(lootRoot, lootMenu)
        local lootChar = KnoxSurvivorRuntime.getCharacter(survivorId)
        local lootSquare = lootChar ~= nil and lootChar:getCurrentSquare() or player:getCurrentSquare()
        local area = areaDirective("loot_area", lootSquare, 10)
        local corpses = areaDirective("loot_corpses", lootSquare, 15)
        local building = buildingDirective(lootSquare)
        local lootArea = lootMenu:addOption("Loot Nearby Area", SurvivorContextMenu, onLootOrder, playerNum, survivorId, area)
        local lootCorpses = lootMenu:addOption("Loot Dead Bodies", SurvivorContextMenu, onLootOrder, playerNum, survivorId, corpses)
        local lootBuilding = lootMenu:addOption("Loot This Building", SurvivorContextMenu, onLootOrder, playerNum, survivorId, building)
        if area == nil then lootArea.notAvailable = true end
        if corpses == nil then lootCorpses.notAvailable = true end
        if building == nil then lootBuilding.notAvailable = true end
        local base = KnoxBaseManager.getForOwner("player", playerId)
        if base ~= nil then
            ordersMenu:addOption(
                "Return to Base",
                SurvivorContextMenu,
                onReturnToBase,
                playerNum,
                survivorId
            )
        end
        ordersMenu:addOption("Done", SurvivorContextMenu, onFinishInventory, playerNum, survivorId)
    end
    menu:addOption("Dismiss", SurvivorContextMenu, onDismiss, playerNum, survivorId)
    return true
end

function SurvivorContextMenu.open(playerNum, survivorId, x, y)
    local menu = ISContextMenu.get(playerNum, x, y)
    SurvivorContextMenu.populate(menu, playerNum, survivorId)
    return menu
end

local function nearestSurvivor(worldObjects)
    local bestId = nil
    local bestDistance = math.huge
    for _, object in ipairs(worldObjects or {}) do
        local square = object ~= nil and object:getSquare() or nil
        if square ~= nil then
            local id, distance = KnoxSurvivorRuntime.nearestToSquare(square, WORLD_PICK_RADIUS)
            if id ~= nil and distance ~= nil and distance < bestDistance then
                bestId = id
                bestDistance = distance
            end
        end
    end
    return bestId
end

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if not KnoxSettings.enabled() then
        return
    end
    if test and ISWorldObjectContextMenu.Test then
        return true
    end
    local survivorId = nearestSurvivor(worldObjects)
    if survivorId == nil then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end

    local snapshot = KnoxSurvivorViewModel.getSurvivor(survivorId, playerNum)
    local name = snapshot ~= nil and snapshot.displayName or "Survivor"
    local rootOption = context:addOptionOnTop(name, nil, nil)
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, subMenu)
    SurvivorContextMenu.populate(subMenu, playerNum, survivorId)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

return SurvivorContextMenu
