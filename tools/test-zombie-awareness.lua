require = function() return true end

local spotted = 0
local directed = 0
local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
    }
end

local npc = {
    dead = false,
    current = square(10, 10, 0),
    getCurrentSquare = function(self) return self.current end,
    isDead = function(self) return self.dead end,
    setZombiesDontAttack = function(self, value) self.protected = value end,
    TestZombieSpotPlayer = function(self, zombie)
        assert(zombie ~= nil)
        spotted = spotted + 1
    end,
}
local zombie = {
    getCurrentSquare = function() return square(14, 10, 0) end,
    isDead = function() return false end,
    getTarget = function(self) return self.target end,
}
local list = {
    isEmpty = function() return false end,
    size = function() return 1 end,
    get = function(_, index) return index == 0 and zombie or nil end,
}
getCell = function()
    return { getZombieList = function() return list end }
end

KnoxJavaBridge = {
    directZombieAtNpc = function(_, id, targetZombie)
        assert(id == "near")
        targetZombie.target = npc
        directed = directed + 1
        return "ZOMBIE_DIRECTED"
    end,
}

assert(loadfile("mod/42/media/lua/client/KS_ZombieAwareness.lua"))()
local fartherNpc = {
    getCurrentSquare = function() return square(20, 10, 0) end,
    isDead = function() return false end,
    setZombiesDontAttack = function() end,
    TestZombieSpotPlayer = function() error("farther NPC must not be selected") end,
}
KnoxZombieAwareness.update(
    { near = { character = npc }, far = { character = fartherNpc } },
    { "far", "near" },
    30
)
assert(spotted == 1, "nearby zombie introduced through vanilla spotting edge")
assert(npc.protected == false, "NPC remains attackable")
assert(directed == 1, "nearest NPC becomes the stable zombie target")
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 60)
assert(spotted == 1, "valid vanilla target is preserved instead of reassigned")
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 61)
assert(spotted == 1, "awareness work is scheduled instead of per-frame")

print("Zombie awareness PASS nearest=true stable=true scheduled=true")
