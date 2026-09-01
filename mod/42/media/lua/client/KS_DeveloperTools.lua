require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "KS_Settings"
require "KS_SurvivorAutonomy"
require "KS_ActivityFeed"
require "KS_CombatTestScenarios"
require "KS_KnoxEvents"

local DeveloperTools = rawget(_G, "KnoxDeveloperTools") or {}
_G.KnoxDeveloperTools = DeveloperTools

local SCENARIOS = {
    { "Spawn Test Survivor", "single" },
    { "Spawn Test Companion", "companion" },
    { "Spawn Test Travel Group", "group" },
    { "Spawn Test Faction", "faction" },
    { "Spawn Test Faction Seeking a Base", "faction_base" },
}

local COMBAT_SCENARIOS = {
    { "Survivor vs Zombie", "duel" },
    { "Survivor vs Crawler", "crawler_duel" },
    { "Survivor vs Zombie Group", "survivor_horde" },
    { "Travel Group vs Zombies", "group_horde" },
    { "Faction vs Zombies", "faction_horde" },
    { "Faction Combat Stress Test", "stress" },
    { "Survivor Firearm Test", "firearm_duel" },
}

function DeveloperTools.spawn(playerNum, scenario)
    local player = getSpecificPlayer(playerNum)
    local success, result = KnoxSurvivorAutonomy.spawnDeveloperScenario(player, scenario)
    if success then
        KnoxActivityFeed.event("Developer scenario spawned: " .. tostring(scenario) .. ".")
    else
        KnoxActivityFeed.event("Developer spawn failed: " .. tostring(result) .. ".")
    end
    print("[KnoxSurvivors][DeveloperTools] scenario=" .. tostring(scenario)
        .. " success=" .. tostring(success) .. " result=" .. tostring(result))
end

function DeveloperTools.printStatus()
    local status = KnoxSurvivorAutonomy.status()
    print("[KnoxSurvivors][DeveloperTools] running=" .. tostring(status.running)
        .. " ticks=" .. tostring(status.ticks)
        .. " survivors=" .. table.concat(status.ids or {}, ","))
    for _, id in ipairs(status.ids or {}) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        if controller ~= nil then
            print("[KnoxSurvivors][DeveloperTools] " .. controller:status())
        end
    end
    KnoxActivityFeed.event("Developer status written to console.txt.")
end

function DeveloperTools.dispatchScout(playerNum, worldObjects)
    local square = worldObjects ~= nil and worldObjects[1] ~= nil
        and worldObjects[1]:getSquare() or nil
    local player = getSpecificPlayer(playerNum)
    local success, result = KnoxSurvivorAutonomy.dispatchDeveloperScout(player, square)
    KnoxActivityFeed.event(success and ("Faction scout team departed: " .. tostring(result) .. ".")
        or ("Scout dispatch failed: " .. tostring(result) .. "."))
end

function DeveloperTools.scheduleEligibleRaid()
    if not KnoxSettings.allowDestructiveDeveloperTests() then
        KnoxActivityFeed.event("Raid test requires Allow Destructive Tests.")
        return
    end
    local hours = getGameTime():getWorldAgeHours()
    local event, result = KnoxEvents.scheduleAutomaticRaid(hours, true, 0, 1, true)
    KnoxActivityFeed.event(event ~= nil
        and ("Faction raid scheduled: " .. tostring(event.id) .. ".")
        or ("Raid scheduling failed: " .. tostring(result) .. "."))
    print("[KnoxSurvivors][DeveloperTools] raid=" .. tostring(event ~= nil and event.id or "none")
        .. " result=" .. tostring(result))
end

function DeveloperTools.schedulePoliceEntry(playerNum, worldObjects)
    if not KnoxSettings.allowDestructiveDeveloperTests() then
        KnoxActivityFeed.event("Police entry test requires Allow Destructive Tests.")
        return
    end
    local object = worldObjects ~= nil and worldObjects[1] or nil
    local square = object ~= nil and object:getSquare() or nil
    if square == nil then
        KnoxActivityFeed.event("Police entry scheduling failed: no target square.")
        return
    end
    local hours = getGameTime():getWorldAgeHours()
    local event, result = KnoxEvents.scheduleFactionEntry("police", "secure_area", {
        x = square:getX(), y = square:getY(), z = square:getZ(),
    }, 3, hours, 0)
    KnoxActivityFeed.event(event ~= nil
        and ("Police Knox Event scheduled: " .. tostring(event.id) .. ".")
        or ("Police entry scheduling failed: " .. tostring(result) .. "."))
    print("[KnoxSurvivors][DeveloperTools] policeEntry="
        .. tostring(event ~= nil and event.id or "none") .. " result=" .. tostring(result))
end

local function onFill(playerNum, context, worldObjects, test)
    if not KnoxSettings.developerToolsEnabled() then
        return
    end
    if test then
        if ISWorldObjectContextMenu.Test then
            return true
        end
        return ISWorldObjectContextMenu.setTest()
    end
    local rootOption = context:addOption("Knox Survivors - Developer Tools", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, menu)
    local populationOption = menu:addOption("Spawn Survivor Scenarios", nil, nil)
    local populationMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(populationOption, populationMenu)
    for _, definition in ipairs(SCENARIOS) do
        populationMenu:addOption(definition[1], playerNum, DeveloperTools.spawn, definition[2])
    end

    local combatOption = menu:addOption("Run Combat Scenario", nil, nil)
    local combatMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(combatOption, combatMenu)
    for _, definition in ipairs(COMBAT_SCENARIOS) do
        combatMenu:addOption(definition[1], playerNum, KnoxCombatTestScenarios.start, definition[2])
    end

    menu:addOption("Dispatch Loaded Faction Scout Here", playerNum,
        DeveloperTools.dispatchScout, worldObjects)

    if KnoxSettings.allowDestructiveDeveloperTests() then
        menu:addOption("Schedule Eligible Faction Raid Now", nil,
            DeveloperTools.scheduleEligibleRaid)
        menu:addOption("Schedule Police Entry Here", playerNum,
            DeveloperTools.schedulePoliceEntry, worldObjects)
    end

    menu:addOption("Write Survivor Status to Log", nil, DeveloperTools.printStatus)
    menu:addOption("Write Combat Snapshot to Log", nil, KnoxCombatTestScenarios.writeSnapshot)
    menu:addOption("Cleanup Combat Test", nil, KnoxCombatTestScenarios.cleanup)
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

return DeveloperTools
