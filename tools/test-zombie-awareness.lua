dofile((arg[1] or ".") .. "/mod/42/media/lua/client/KS_ThreatClassifier.lua")
require = function() return true end
dofile((arg[1] or ".") .. "/mod/42/media/lua/client/KS_ZombieDiscovery.lua")

-- The engine always provides instanceof; the classifier gates the zombie-only
-- grapple flag on it so human shells can never throw through pcall.
instanceof = function(object, class)
    return class == "IsoZombie" and type(object) == "table" and object.__zombie == true
end

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
npc.getX=function(self) return self.current:getX() end
npc.getY=function(self) return self.current:getY() end
local zombie = {
    __zombie = true,
    visible = true,
    getX=function() return 14 end, getY=function() return 10 end,
    getLookDirectionX=function() return -1 end,getLookDirectionY=function() return 0 end,
    getCurrentSquare = function() return square(14, 10, 0) end,
    isDead = function() return false end,
    getTarget = function(self) return self.target end,
    setTarget = function(self, target) self.target = target end,
    CanSee = function(self) return self.visible end,
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

activePlayer = nil
local memoryZombie = {
    __zombie = true,
    visible = false,
    getX=function(self) return self.current:getX() end, getY=function(self) return self.current:getY() end,
    getLookDirectionX=function() return -1 end,getLookDirectionY=function() return 0 end,
    current = square(14, 10, 0),
    getCurrentSquare = function(self) return self.current end,
    isDead = function() return false end,
    getTarget = function(self) return self.target end,
    setTarget = function(self, target) self.target = target end,
    CanSee = function(self) return self.visible end,
}
list.get = function(_, index) return index == 0 and memoryZombie or nil end
npc.current = square(10, 10, 0)
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 135)
assert(directed == 5, "distance alone does not reveal a survivor through blocked LOS")
memoryZombie.visible = true
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 150)
assert(directed == 6 and memoryZombie.target == npc,
    "nearby upright survivor in front is visually discovered")
memoryZombie.visible = false
memoryZombie.target = nil
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 165)
assert(directed == 7 and memoryZombie.target == npc,
    "recently perceived survivor has bounded target memory")
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 345)
assert(directed == 7 and memoryZombie.target == nil,
    "lost target memory expires and releases the stale off-slot native target")
memoryZombie.visible = true
memoryZombie.current = square(14, 10, 1)
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 360)
assert(directed == 7, "different-floor survivor is not treated as adjacent")

print("Zombie awareness PASS nearest=true los=true memory=true floors=true refreshed=true close_attack=true balanced_switch=true")

memoryZombie.current=square(10.5,10,0)
memoryZombie.isReanimatedForGrappleOnly=function() return true end
memoryZombie.target=npc
local beforeProxy=directed
KnoxZombieAwareness.update({near={character=npc}},{"near"},375)
KnoxZombieAwareness.update({near={character=npc}},{"near"},381)
assert(directed==beforeProxy, "corpse grapple proxies must never be directed to bite the carrier")
memoryZombie.isReanimatedForGrappleOnly=function() return false end
KnoxZombieAwareness.update({near={character=npc}},{"near"},390)
assert(directed>beforeProxy, "real zombies retain native attack discovery")
print("Corpse proxy awareness PASS")

-- Initial discovery must not poison target memory when a crouching NPC only
-- has geometric LOS. Existing pursuit still uses the paced native bridge.
memoryZombie.target=nil
local quietZombie={__zombie=true,current=square(18,10,0),visible=true,
    getCurrentSquare=function(self) return self.current end,isDead=function() return false end,
    getTarget=function(self) return self.target end,setTarget=function(self,target) self.target=target end,
    getX=function(self) return self.current:getX() end,getY=function(self) return self.current:getY() end,
    getLookDirectionX=function() return -1 end,getLookDirectionY=function() return 0 end,
    CanSee=function(self) return self.visible end}
list.get=function(_,index) return index==0 and quietZombie or nil end
npc.isSneaking=function() return true end
npc.getSneakSpotMod=function() return 0.5 end
local initial=directed
KnoxZombieAwareness.update({near={character=npc}},{"near"},420)
assert(quietZombie.target==nil and directed==initial)
quietZombie.visible=false
KnoxZombieAwareness.update({near={character=npc}},{"near"},435)
assert(quietZombie.target==nil and directed==initial, "an unconfirmed sighting must not create pursuit memory")
quietZombie.visible=true
for t=450,540,15 do KnoxZombieAwareness.update({near={character=npc}},{"near"},t) end
assert(quietZombie.target==nil)
KnoxZombieAwareness.update({near={character=npc}},{"near"},555)
assert(quietZombie.target==npc and directed==initial+1, "sustained real exposure acquires a target")
KnoxZombieAwareness.update({near={character=npc}},{"near"},585)
assert(directed==initial+2, "discovery changes must not weaken native pursuit refresh")
print("Stealth awareness integration PASS no_false_memory=true native_pursuit=true")

-- Build 42 off-slot shells must never write LightingJNI visibility bits. Native
-- target selection still continues, but bite completion remains an engine-owned
-- result rather than a synthetic setCouldSee override.
local function bitSquare(x, y, z)
    local bits = {}
    local s = square(x, y, z)
    s.setCouldSee = function(_, index, value) bits[index] = value end
    s.isCouldSee = function(_, index) return bits[index] == true end
    s._bits = bits
    return s
end
npc.getIndex = function() return 7 end
npc.isSneaking = function() return false end
local homeSquare = bitSquare(10, 10, 0)
npc.current = homeSquare
local biter = {
    __zombie = true,
    dead = false,
    current = bitSquare(10.5, 10, 0),
    getCurrentSquare = function(self) return self.current end,
    isDead = function(self) return self.dead end,
    getTarget = function(self) return self.target end,
    setTarget = function(self, target) self.target = target end,
    CanSee = function(self) return true end,
}
list.get = function(_, index) return index == 0 and biter or nil end
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 600)
assert(biter.target == npc, "adjacent shell is acquired")
assert(homeSquare._bits[7] ~= true, "off-slot shell never writes a LightingJNI visibility bit")
local awaySquare = bitSquare(12, 10, 0)
npc.current = awaySquare
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 615)
assert(homeSquare._bits[7] ~= true and awaySquare._bits[7] ~= true,
    "movement cannot leave or move a synthetic visibility bit")
biter.dead = true
KnoxZombieAwareness.update({ near = { character = npc } }, { "near" }, 630)
assert(awaySquare._bits[7] ~= true, "disengage clears the bit")
print("Visibility bit safety PASS no_lightingjni_write=true native_targeting=true")
