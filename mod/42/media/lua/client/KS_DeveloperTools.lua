require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "KS_Settings"
require "KS_SurvivorAutonomy"
require "KS_ActivityFeed"
require "KS_CombatTestScenarios"
require "KS_KnoxEvents"
require "KS_JobTestSupplies"

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

function DeveloperTools.printFactionReadiness()
    local seen={}
    for _,id in ipairs(KnoxPersistence.getActivatableSurvivorIds()) do
        local group=KnoxPersistence.getTravelGroupFor(id)
        if group~=nil and not seen[group.id] then
            seen[group.id]=true
            local status=KnoxPersistence.getFactionReadiness(group.id,KnoxSettings.npcFactionMinimumMembers())
            print("[KnoxSurvivors][DeveloperTools] group="..group.id
                .." faction="..tostring(status.factionId or "none")
                .." formation="..tostring(status.reason).." enabled="..tostring(KnoxSettings.allowNPCFactions())
                .." members="..status.members.." required="..status.required
                .." shared="..status.sharedMembers.." waitingFor="..table.concat(status.missingShared,","))
        end
    end
    KnoxActivityFeed.event("Faction formation status written to console.txt.")
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
    if KnoxSettings.enableKnoxEvents ~= nil and not KnoxSettings.enableKnoxEvents() then
        KnoxActivityFeed.event("Knox Events are disabled in Sandbox settings.")
        return
    end
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

local function scheduleNamedEntry(worldObjects, policyId, objectiveKind, partySize, label)
    if KnoxSettings.enableKnoxEvents ~= nil and not KnoxSettings.enableKnoxEvents() then
        KnoxActivityFeed.event("Knox Events are disabled in Sandbox settings.")
        return
    end
    if not KnoxSettings.allowDestructiveDeveloperTests() then
        KnoxActivityFeed.event(label .. " entry test requires Allow Destructive Tests.")
        return
    end
    local object = worldObjects ~= nil and worldObjects[1] or nil
    local square = object ~= nil and object:getSquare() or nil
    if square == nil then
        KnoxActivityFeed.event(label .. " entry scheduling failed: no target square.")
        return
    end
    local hours = getGameTime():getWorldAgeHours()
    local event, result = KnoxEvents.scheduleFactionEntry(policyId, objectiveKind, {
        x = square:getX(), y = square:getY(), z = square:getZ(),
    }, partySize, hours, 0)
    KnoxActivityFeed.event(event ~= nil
        and (label .. " Knox Event scheduled: " .. tostring(event.id) .. ".")
        or (label .. " entry scheduling failed: " .. tostring(result) .. "."))
    print("[KnoxSurvivors][DeveloperTools] namedEntry=" .. tostring(policyId)
        .. " event="
        .. tostring(event ~= nil and event.id or "none") .. " result=" .. tostring(result))
end

function DeveloperTools.schedulePoliceEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "police", "secure_area", 3, "Police")
end

function DeveloperTools.scheduleScientistsEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "scientists", "research", 2, "Scientists")
end

function DeveloperTools.scheduleMilitaryEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "military", "secure_area", 3, "Military")
end

function DeveloperTools.scheduleScavengerEntry(playerNum, worldObjects)
    scheduleNamedEntry(worldObjects, "scavengers", "scavenge_world", 3, "Scavengers")
end

function DeveloperTools.stockJobTests(playerNum)
    local actor = getSpecificPlayer(playerNum)
    local manager = rawget(_G, "KnoxBaseManager")
    local service = rawget(_G, "KnoxCompanionService")
    local owner = actor ~= nil and service ~= nil and service.getPlayerId(actor) or nil
    local base = owner ~= nil and manager ~= nil and manager.getForOwner("player", owner) or nil
    local added, result = KnoxJobTestSupplies.ensure(base, actor, true)
    KnoxActivityFeed.event("Job test supplies: " .. tostring(result) .. " (" .. tostring(added) .. " items added).")
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
    local populationOption = menu:addOption("Population Scenarios", nil, nil)
    local populationMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(populationOption, populationMenu)
    for _, definition in ipairs(SCENARIOS) do
        populationMenu:addOption(definition[1], playerNum, DeveloperTools.spawn, definition[2])
    end

    local jobsOption = menu:addOption("Base & Job Tests", nil, nil)
    local jobsMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(jobsOption, jobsMenu)
    local stock = jobsMenu:addOption("Stock Central Cupboard for Job Tests", playerNum, DeveloperTools.stockJobTests)
    stock.notAvailable = not KnoxSettings.developerJobSuppliesEnabled()
    jobsMenu:addOption("Write Job and Survivor Status to Log", nil, DeveloperTools.printStatus)

    local combatOption = menu:addOption("Combat Tests", nil, nil)
    local combatMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(combatOption, combatMenu)
    for _, definition in ipairs(COMBAT_SCENARIOS) do
        combatMenu:addOption(definition[1], playerNum, KnoxCombatTestScenarios.start, definition[2])
    end
    combatMenu:addOption("Write Combat Snapshot to Log", nil, KnoxCombatTestScenarios.writeSnapshot)
    combatMenu:addOption("Cleanup Combat Test", nil, KnoxCombatTestScenarios.cleanup)

    local worldOption = menu:addOption("Faction & World Events", nil, nil)
    local worldMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(worldOption, worldMenu)
    worldMenu:addOption("Write Faction Formation Status to Log", nil, DeveloperTools.printFactionReadiness)
    worldMenu:addOption("Dispatch Loaded Faction Scout Here", playerNum,
        DeveloperTools.dispatchScout, worldObjects)

    if KnoxSettings.allowDestructiveDeveloperTests() then
        local destructiveOption = worldMenu:addOption("Destructive Tests", nil, nil)
        local destructiveMenu = ISContextMenu:getNew(worldMenu)
        worldMenu:addSubMenu(destructiveOption, destructiveMenu)
        destructiveMenu:addOption("Schedule Eligible Faction Raid Now", nil,
            DeveloperTools.scheduleEligibleRaid)
        destructiveMenu:addOption("Schedule Police Entry Here", playerNum,
            DeveloperTools.schedulePoliceEntry, worldObjects)
        destructiveMenu:addOption("Schedule Scientists Entry Here", playerNum,
            DeveloperTools.scheduleScientistsEntry, worldObjects)
        destructiveMenu:addOption("Schedule Military Entry Here", playerNum,
            DeveloperTools.scheduleMilitaryEntry, worldObjects)
        destructiveMenu:addOption("Schedule Scavenger Search Here", playerNum,
            DeveloperTools.scheduleScavengerEntry, worldObjects)
    end

    local diagnosticsOption = menu:addOption("Diagnostics", nil, nil)
    local diagnosticsMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(diagnosticsOption, diagnosticsMenu)
    diagnosticsMenu:addOption("Write Survivor Status to Log", nil, DeveloperTools.printStatus)
end

Events.OnFillWorldObjectContextMenu.Add(onFill)

return DeveloperTools
