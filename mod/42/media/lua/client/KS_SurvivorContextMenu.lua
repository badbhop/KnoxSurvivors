require "ISUI/ISContextMenu"
require "ISUI/ISModalDialog"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISHealthPanel"
require "TimedActions/ISMedicalCheckAction"
require "KS_CompanionService"
require "KS_BaseManager"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"
require "KS_SurvivorCard"
require "KS_Settings"

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

local function onViewSurvivor(_, playerNum, survivorId)
    KnoxSurvivorCard.show(playerNum, survivorId)
end

local function onMedicalCheck(_, playerNum, survivorId)
    local player = getSpecificPlayer(playerNum)
    local patient = KnoxSurvivorRuntime.getCharacter(survivorId)
    if player == nil or patient == nil then
        return
    end
    -- This is the same vanilla timed action used to examine another player.  An
    -- IsoPlayer survivor supplies the same patient/BodyDamage surface, while the
    -- real local player stays the doctor and retains normal UI/input ownership.
    if ISHealthPanel.canPerformMedicalCheck(patient, player) then
        ISTimedActionQueue.add(ISMedicalCheckAction:new(player, patient))
    end
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
    local talkLabel = closeEnough and "Talk" or "Talk (too far away)"
    local talk = menu:addOption(talkLabel, SurvivorContextMenu, onTalk, playerNum, survivorId)
    if not closeEnough then
        unavailable(talk)
    end

    if not owned then
        addRecruitOption(menu, player, survivorId, closeEnough)
        return true
    end

    if duty.mode == "companion" then
        local medicalLabel = closeEnough and "Medical Check"
            or "Medical Check (too far away)"
        local medical = menu:addOption(
            medicalLabel,
            SurvivorContextMenu,
            onMedicalCheck,
            playerNum,
            survivorId
        )
        if not closeEnough then
            unavailable(medical)
        end
    end

    if duty.mode == "base" then
        menu:addOption("Follow", SurvivorContextMenu, onFollow, playerNum, survivorId)
        local jobs = menu:addOption("Base Job Preference", nil, nil)
        local jobsMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(jobs, jobsMenu)
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
    elseif duty.mode == "companion" then
        local follow = menu:addOption("Follow", SurvivorContextMenu, onFollow, playerNum, survivorId)
        local hold = menu:addOption("Hold here", SurvivorContextMenu, onHold, playerNum, survivorId)
        menu:setOptionChecked(follow, duty.order == "follow")
        menu:setOptionChecked(hold, duty.order == "hold")
        menu:addOption("Move to Me", SurvivorContextMenu, onMoveToPlayer, playerNum, survivorId)
        menu:addOption("Guard Here", SurvivorContextMenu, onGuardHere, playerNum, survivorId)
        local base = KnoxBaseManager.getForOwner("player", playerId)
        if base ~= nil then
            menu:addOption(
                "Return to Base",
                SurvivorContextMenu,
                onReturnToBase,
                playerNum,
                survivorId
            )
        end
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
