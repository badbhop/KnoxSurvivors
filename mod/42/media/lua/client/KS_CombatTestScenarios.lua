require "KS_SurvivorAutonomy"
require "KS_ActivityFeed"
require "KS_FirearmSupport"

local CombatTests = rawget(_G, "KnoxCombatTestScenarios") or {}
_G.KnoxCombatTestScenarios = CombatTests

local TAG = "[KnoxSurvivors][CombatTest]"
local TIMEOUT_TICKS = 2400
local SNAPSHOT_INTERVAL_TICKS = 120

local definitions = {
    duel = { population = "single", zombies = 1, label = "Survivor vs Zombie" },
    crawler_duel = {
        population = "single",
        zombies = 1,
        crawler = true,
        label = "Survivor vs Crawler",
    },
    survivor_horde = { population = "single", zombies = 4, label = "Survivor vs Zombie Group" },
    group_horde = { population = "group", zombies = 5, label = "Travel Group vs Zombies" },
    faction_horde = { population = "faction", zombies = 8, label = "Faction vs Zombies" },
    stress = { population = "faction", zombies = 12, label = "Faction Combat Stress Test" },
    firearm_duel = {
        population = "single",
        zombies = 1,
        firearm = true,
        label = "Survivor Firearm Test",
    },
}

local active = nil
local trackedZombies = {}
local preferredOwners = setmetatable({}, { __mode = "k" })

local function characterHealth(character)
    local success, value = pcall(function()
        return character:getBodyDamage():getHealth()
    end)
    return success and tonumber(value) or tonumber(character:getHealth()) or 100
end

local function removeZombie(zombie)
    if zombie == nil then
        return
    end
    pcall(function()
        zombie:setTarget(nil)
        zombie:setUseless(true)
        zombie:setCanWalk(false)
        zombie:removeFromWorld()
        zombie:removeFromSquare()
    end)
end

function CombatTests.cleanup(silent)
    local removed = 0
    for _, zombie in ipairs(trackedZombies) do
        if zombie ~= nil then
            removeZombie(zombie)
            removed = removed + 1
        end
    end
    trackedZombies = {}
    preferredOwners = setmetatable({}, { __mode = "k" })
    active = nil
    print(TAG .. " cleanup removedScenarioZombies=" .. tostring(removed))
    if silent ~= true then
        KnoxActivityFeed.event("Combat test cleaned up (" .. tostring(removed) .. " zombies).")
    end
end

function CombatTests.preferredNpcId(zombie)
    return preferredOwners[zombie]
end

function CombatTests.status()
    return {
        active = active ~= nil,
        name = active ~= nil and active.name or nil,
        survivors = active ~= nil and #active.ids or 0,
        zombies = active ~= nil and #active.zombies or 0,
        trackedZombies = #trackedZombies,
        finished = active ~= nil and active.finished or false,
    }
end

local function parseIds(result)
    local encoded = tostring(result or ""):match("^([^ ]+)") or ""
    local ids = {}
    for id in string.gmatch(encoded, "[^,]+") do
        ids[#ids + 1] = id
    end
    return ids
end

local function findSpawnSquare(origin, ordinal)
    local cell = getCell()
    if cell == nil or origin == nil then
        return nil
    end
    local directions = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
    }
    for step = 0, #directions - 1 do
        local direction = directions[((ordinal + step - 1) % #directions) + 1]
        local previous = origin
        local valid = true
        local destination = nil
        for distance = 1, 3 do
            destination = cell:getGridSquare(
                origin:getX() + direction[1] * distance,
                origin:getY() + direction[2] * distance,
                origin:getZ()
            )
            if destination == nil or not destination:canStand()
                or previous:isBlockedTo(destination) then
                valid = false
                break
            end
            previous = destination
        end
        if valid then
            return destination
        end
    end
    return nil
end

local function report(status, reason)
    if active == nil then
        return
    end
    print(TAG .. " RESULT scenario=combat_" .. tostring(active.name)
        .. " status=" .. tostring(status)
        .. " reason=" .. tostring(reason)
        .. " survivorHits=" .. tostring(active.survivorHits)
        .. " zombieDamage=" .. tostring(active.zombieDamage)
        .. " attackActionSeen=" .. tostring(active.attackActionSeen)
        .. " attackDidDamageSeen=" .. tostring(active.attackDidDamageSeen)
        .. " zombiesKilled=" .. tostring(active.zombiesKilled))
    KnoxActivityFeed.event("Combat test " .. tostring(active.definition.label) .. ": "
        .. tostring(status) .. " (details written to console.txt).")
    active.finished = true
end

local function zombieAction(zombie)
    local success, action = pcall(function()
        return tostring(zombie:getCurrentActionContextStateName())
    end)
    return success and action or "unavailable"
end

local function variableBoolean(character, name)
    local success, value = pcall(function()
        return character:getVariableBoolean(name)
    end)
    return success and value == true
end

local function firearmAmmo(character)
    if character == nil then
        return "missing"
    end
    local success, result = pcall(function()
        local weapon = character:getPrimaryHandItem()
        if weapon == nil or not weapon:isRanged() then
            return "not_ranged"
        end
        return tostring(weapon:getFullType())
            .. " rounds=" .. tostring(weapon:getCurrentAmmoCount())
            .. " chambered=" .. tostring(weapon:isRoundChambered())
    end)
    return success and result or "unavailable"
end

function CombatTests.writeSnapshot()
    if active == nil then
        print(TAG .. " snapshot active=false trackedZombies=" .. tostring(#trackedZombies))
        KnoxActivityFeed.event("No combat test is currently running.")
        return
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    local status = KnoxSurvivorAutonomy.status()
    print(TAG .. " snapshot scenario=" .. tostring(active.name)
        .. " elapsed=" .. tostring(active.elapsed)
        .. " finished=" .. tostring(active.finished))
    for _, id in ipairs(active.ids) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        local character = controller ~= nil and controller.character or nil
        print(TAG .. " survivor id=" .. tostring(id)
            .. " health=" .. tostring(character ~= nil and characterHealth(character) or "missing")
            .. " firearm=" .. tostring(firearmAmmo(character))
            .. " controller=" .. tostring(controller ~= nil and controller:status() or "missing"))
        if bridge ~= nil and bridge.getNpcCombatDiagnostics ~= nil then
            print(TAG .. " survivor-java id=" .. tostring(id)
                .. " " .. tostring(bridge:getNpcCombatDiagnostics(id)))
        end
    end
    for index, zombie in ipairs(active.zombies) do
        local ownerId = active.zombieOwners[index]
        local dead = zombie == nil or zombie:isDead()
        print(TAG .. " zombie index=" .. tostring(index)
            .. " owner=" .. tostring(ownerId)
            .. " dead=" .. tostring(dead)
            .. " health=" .. tostring(not dead and zombie:getHealth() or 0)
            .. " action=" .. tostring(not dead and zombieAction(zombie) or "dead")
            .. " attackDidDamage="
            .. tostring(not dead and variableBoolean(zombie, "AttackDidDamage") or false))
        if not dead and bridge ~= nil and bridge.getZombieAttackDiagnostics ~= nil then
            print(TAG .. " zombie-java index=" .. tostring(index) .. " "
                .. tostring(bridge:getZombieAttackDiagnostics(ownerId, zombie)))
        end
    end
    KnoxActivityFeed.event("Combat snapshot written to console.txt.")
end

function CombatTests.start(playerNum, scenario)
    local definition = definitions[scenario]
    local player = getSpecificPlayer(playerNum)
    if definition == nil or player == nil or getCell() == nil then
        KnoxActivityFeed.event("Combat test could not start here.")
        return false
    end
    CombatTests.cleanup(true)
    local success, result = KnoxSurvivorAutonomy.spawnDeveloperScenario(
        player, definition.population
    )
    if not success then
        print(TAG .. " start-failed scenario=" .. tostring(scenario)
            .. " reason=" .. tostring(result))
        KnoxActivityFeed.event("Combat test survivor spawn failed: " .. tostring(result) .. ".")
        return false
    end
    local ids = parseIds(result)
    local status = KnoxSurvivorAutonomy.status()
    local bridge = rawget(_G, "KnoxJavaBridge")
    active = {
        name = scenario,
        definition = definition,
        ids = ids,
        zombies = {},
        zombieOwners = {},
        survivorHealth = {},
        zombieHealth = {},
        elapsed = 0,
        survivorHits = 0,
        zombieDamage = 0,
        zombiesKilled = 0,
        attackActionSeen = false,
        attackDidDamageSeen = false,
        crawlerConfigured = definition.crawler ~= true,
        finished = false,
    }
    for _, id in ipairs(ids) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        if controller ~= nil and controller.character ~= nil then
            active.survivorHealth[id] = characterHealth(controller.character)
            controller.character:setZombiesDontAttack(false)
        end
        if definition.firearm == true and bridge ~= nil
            and bridge.seedNpcFirearmTestKit ~= nil then
            local kit = tostring(bridge:seedNpcFirearmTestKit(id))
            print(TAG .. " firearm-kit id=" .. tostring(id) .. " result=" .. kit)
            if string.find(kit, "FIREARM_KIT_ADDED", 1, true) ~= 1 then
                CombatTests.cleanup(true)
                KnoxActivityFeed.event("Firearm test kit failed: " .. kit)
                return false
            end
        end
    end
    for index = 1, definition.zombies do
        local ownerId = ids[((index - 1) % math.max(1, #ids)) + 1]
        local controller = status.controllers ~= nil and status.controllers[ownerId] or nil
        local origin = controller ~= nil and controller.character:getCurrentSquare()
            or player:getCurrentSquare()
        local square = findSpawnSquare(origin, index)
        if square ~= nil then
            local spawned = addZombiesInOutfit(
                square:getX(), square:getY(), square:getZ(), 1, nil, nil
            )
            local zombie = spawned ~= nil and spawned:size() > 0 and spawned:get(0) or nil
            if zombie ~= nil then
                if definition.crawler == true then
                    local crawlerSuccess = pcall(function()
                        zombie:setCrawler(true)
                    end)
                    active.crawlerConfigured = crawlerSuccess
                end
                active.zombies[#active.zombies + 1] = zombie
                active.zombieOwners[#active.zombieOwners + 1] = ownerId
                preferredOwners[zombie] = ownerId
                active.zombieHealth[zombie] = zombie:getHealth()
                trackedZombies[#trackedZombies + 1] = zombie
                if bridge ~= nil and bridge.directZombieAtNpc ~= nil then
                    bridge:directZombieAtNpc(ownerId, zombie)
                end
            end
        end
    end
    if #active.zombies == 0 then
        report("BLOCKED", "no_standable_zombie_spawn_square")
        return false
    end
    print(TAG .. " START scenario=combat_" .. tostring(scenario)
        .. " survivors=" .. table.concat(ids, ",")
        .. " zombies=" .. tostring(#active.zombies)
        .. " crawler=" .. tostring(definition.crawler == true)
        .. " crawlerConfigured=" .. tostring(active.crawlerConfigured)
        .. " timeoutTicks=" .. tostring(TIMEOUT_TICKS))
    KnoxActivityFeed.event("Started " .. definition.label
        .. ". The test reports itself; use Cleanup Combat Test when finished.")
    return true
end

local function update()
    if active == nil or active.finished then
        return
    end
    active.elapsed = active.elapsed + 1
    local status = KnoxSurvivorAutonomy.status()
    for _, id in ipairs(active.ids) do
        local controller = status.controllers ~= nil and status.controllers[id] or nil
        local character = controller ~= nil and controller.character or nil
        if character ~= nil then
            local previous = active.survivorHealth[id] or characterHealth(character)
            local current = characterHealth(character)
            if current < previous - 0.01 then
                active.zombieDamage = active.zombieDamage + (previous - current)
            end
            active.survivorHealth[id] = current
        end
    end
    active.zombiesKilled = 0
    for _, zombie in ipairs(active.zombies) do
        if zombie == nil or zombie:isDead() then
            active.zombiesKilled = active.zombiesKilled + 1
        else
            local previous = active.zombieHealth[zombie] or zombie:getHealth()
            local current = zombie:getHealth()
            if current < previous - 0.001 then
                active.survivorHits = active.survivorHits + 1
            end
            active.zombieHealth[zombie] = current
            active.attackActionSeen = active.attackActionSeen
                or string.lower(zombieAction(zombie)) == "attack"
            active.attackDidDamageSeen = active.attackDidDamageSeen
                or variableBoolean(zombie, "AttackDidDamage")
        end
    end
    if active.survivorHits > 0
        and (active.zombieDamage > 0 or active.attackDidDamageSeen) then
        report("PASS", "two_way_combat_observed")
        CombatTests.writeSnapshot()
        return
    end
    if active.elapsed % SNAPSHOT_INTERVAL_TICKS == 0 then
        CombatTests.writeSnapshot()
    end
    if active.elapsed >= TIMEOUT_TICKS or active.zombiesKilled == #active.zombies then
        local reason = active.survivorHits > 0 and "survivor_damage_only"
            or (active.attackActionSeen and "zombie_attack_animation_without_damage"
                or "no_two_way_combat")
        report(active.survivorHits > 0 and "PARTIAL" or "FAIL", reason)
        CombatTests.writeSnapshot()
    end
end

Events.OnTick.Add(update)

return CombatTests
