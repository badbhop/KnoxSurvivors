require = function() return true end

KnoxActivityFeed = { event = function() end }
Events = { OnTick = { Add = function() end } }

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return true end,
        isBlockedTo = function() return false end,
    }
end

local removed = 0
local function zombie()
    return {
        health = 1,
        isDead = function() return false end,
        getHealth = function(self) return self.health end,
        setTarget = function() end,
        setUseless = function() end,
        setCanWalk = function() end,
        removeFromWorld = function() removed = removed + 1 end,
        removeFromSquare = function() end,
    }
end

local character = {
    getCurrentSquare = function() return square(10, 10, 0) end,
    getBodyDamage = function()
        return { getHealth = function() return 100 end }
    end,
    setZombiesDontAttack = function() end,
}

local controllers = {}
KnoxSurvivorAutonomy = {
    spawnDeveloperScenario = function(_, population)
        local count = population == "single" and 1 or (population == "group" and 2 or 3)
        local ids = {}
        controllers = {}
        for index = 1, count do
            local id = population .. "-" .. tostring(index)
            ids[#ids + 1] = id
            controllers[id] = { character = character, status = function() return "ok" end }
        end
        return true, table.concat(ids, ",") .. " configured"
    end,
    status = function() return { controllers = controllers } end,
}

KnoxJavaBridge = {
    directZombieAtNpc = function() return "ZOMBIE_DIRECTED status=acquired" end,
}
getSpecificPlayer = function()
    return { getCurrentSquare = function() return square(10, 10, 0) end }
end
getCell = function()
    return { getGridSquare = function(_, x, y, z) return square(x, y, z) end }
end
addZombiesInOutfit = function()
    local value = zombie()
    return {
        size = function() return 1 end,
        get = function(_, index) return index == 0 and value or nil end,
    }
end

assert(loadfile("mod/42/media/lua/client/KS_CombatTestScenarios.lua"))()

local expected = {
    duel = { 1, 1 },
    survivor_horde = { 1, 4 },
    group_horde = { 2, 5 },
    faction_horde = { 3, 8 },
    stress = { 3, 12 },
}
for scenario, counts in pairs(expected) do
    assert(KnoxCombatTestScenarios.start(0, scenario), scenario .. " starts")
    local status = KnoxCombatTestScenarios.status()
    assert(status.name == scenario, scenario .. " remains active")
    assert(status.survivors == counts[1], scenario .. " survivor count")
    assert(status.zombies == counts[2], scenario .. " zombie count")
    assert(KnoxCombatTestScenarios.preferredNpcId ~= nil,
        "scenario zombies expose deterministic owners")
end
KnoxCombatTestScenarios.cleanup(true)
assert(KnoxCombatTestScenarios.status().active == false, "cleanup clears active test")
assert(removed == 1 + 4 + 5 + 8 + 12, "only scenario zombies are cleaned")

print("Combat scenarios PASS presets=true cleanup=true")
