require = function() return true end

local directed = 0
local activePlayer = nil
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
getNumActivePlayers = function() return activePlayer ~= nil and 1 or 0 end
getSpecificPlayer = function(index) return index == 0 and activePlayer or nil end

KnoxJavaBridge = {
    directZombieAtNpc = function(_, id, targetZombie)
        assert(id == "near")
        targetZombie.target = npc
        directed = directed + 1
        return "ZOMBIE_DIRECTED status=acquired"
    end,
}

assert(loadfile("mod/42/media/lua/client/KS_ZombieAwareness.lua"))()
local fartherNpc = {
    getCurrentSquare = function() return square(20, 10, 0) end,
    isDead = function() return false end,
    setZombiesDontAttack = function() end,
}
KnoxZombieAwareness.update(
    { near = { character = npc }, far = { character = fartherNpc } },
    { "far", "near" },
    30
)
assert(npc.protected == false, "NPC remains attackable")
assert(directed == 1, "nearest NPC becomes the stable zombie target")
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 60)
assert(directed == 2, "an assigned NPC target gets its perception edge refreshed")
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 61)
assert(directed == 2, "awareness work is scheduled instead of per-frame")

local player = {
    getCurrentSquare = function() return square(12, 10, 0) end,
    isDead = function() return false end,
}
activePlayer = player
zombie.target = player
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 90)
assert(directed == 2, "a nearer player remains the zombie target")

npc.current = square(13, 10, 0)
zombie.target = player
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 105)
assert(directed == 3 and zombie.target == npc,
    "an adjacent survivor intercepts a zombie targeting the player")
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 106)
assert(directed == 3,
    "an adjacent assigned target is not re-entered every frame")
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 111)
assert(directed == 4,
    "an adjacent assigned target receives a paced perception refresh")

player.getCurrentSquare = function() return square(30, 10, 0) end
zombie.target = player
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 120)
assert(directed == 5 and zombie.target == npc,
    "a substantially nearer survivor competes with the player as a target")

print("Zombie awareness PASS nearest=true refreshed=true close_attack=true balanced_switch=true")
