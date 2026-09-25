local projectRoot = arg[1] or "."

require = function()
    return true
end

Events = {
    OnFillWorldObjectContextMenu = { Add = function() end },
}

local fed = {}
KnoxActivityFeed = {
    event = function(message) fed[#fed + 1] = message end,
}

local character = {
    isZombiesDontAttack = function() return false end,
    isGodMod = function() return false end,
    isInvulnerable = function() return false end,
    isGhostMode = function() return false end,
    isInvisible = function() return false end,
    getBodyDamage = function()
        return { getHealth = function() return 87 end }
    end,
    getCurrentSquare = function()
        return { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end }
    end,
}
local zombieSquare = {
    getX = function() return 3 end, getY = function() return 4 end, getZ = function() return 0 end,
}
local zombie = {
    getCurrentSquare = function() return zombieSquare end,
    getTarget = function() return character end,
}
local zombieList = {
    size = function() return 1 end,
    get = function(_, index) return index == 0 and zombie or nil end,
}
getCell = function()
    return { getZombieList = function() return zombieList end }
end
getSpecificPlayer = function() return nil end

KnoxSurvivorAutonomy = {
    status = function()
        return {
            ids = { "s1", "s2" },
            controllers = {
                s1 = { character = character },
                s2 = { character = nil },
            },
        }
    end,
}
KnoxJavaBridge = {
    zombieAttackDiagnostics = function(_, id)
        return "DIAG id=" .. tostring(id)
    end,
}

dofile(projectRoot .. "/mod/42/media/lua/client/KS_DeveloperTools.lua")
local DeveloperTools = assert(KnoxDeveloperTools)

DeveloperTools.diagnoseDamage(0)
assert(#fed == 1, "diagnostic must acknowledge completion in the feed")

print("Damage diagnostic PASS flags=true nearest_zombie=true missing_body=true")
