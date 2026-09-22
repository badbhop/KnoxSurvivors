local root = arg[1] or "."

require = function() return true end
local controllerPath = root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
assert(loadfile(controllerPath))()
local Controller = assert(KnoxAutonomyController)

local queued = {}
KnoxSurvivorLooting = {
    plan = function()
        return {
            { item = { getFullType = function() return "Base.CannedSoup" end,
                isFavorite = function() return false end } },
            { item = { getFullType = function() return "Base.Bandage" end,
                isFavorite = function() return false end } },
            { item = { getFullType = function() return "Base.Hammer" end,
                isFavorite = function() return false end } },
        }
    end,
}
KnoxInventoryActions = {
    queueTransfer = function(_, item, source, destination)
        queued[#queued + 1] = { item = item, source = source, destination = destination }
        return {}
    end,
}

local victimInventory = {}
local victimCharacter = {
    getInventory = function() return victimInventory end,
    isEquipped = function() return false end,
}
local victim = setmetatable({
    id = "victim",
    character = victimCharacter,
    state = "IDLE",
    resumeAfterGreeting = function(self) self.state, self.activeDecision = "IDLE", nil end,
}, Controller)
local robberInventory = {}
local robberCharacter = {
    getInventory = function() return robberInventory end,
}
local robber = setmetatable({
    id = "robber",
    character = robberCharacter,
    state = "IDLE",
}, Controller)

assert(victim:holdForRobbery(robber, 100)
    and victim.state == "GROUP_WAIT" and victim.activeDecision == "robbery_hold",
    "a victim receives a bounded robbery hold instead of a permanent wait")
assert(robber:beginRobbery(victim, 100) and #queued == 2,
    "robbery queues at most two real item transfers from the victim inventory")
assert(queued[1].source == victimInventory and queued[1].destination == robberInventory
    and queued[2].source == victimInventory,
    "robbery transfers preserve real source and destination ownership")
assert(robber:cancelRobbery(101, "zombie_interrupt")
    and victim.pendingRobberyHold == nil and victim.state == "IDLE",
    "combat interruption releases the victim rather than leaving a stranded hold")

assert(victim:holdForRobbery(robber, 200) and robber:beginRobbery(victim, 200),
    "a second encounter can establish a fresh bounded transfer")
assert(victim:releaseRobberyHold(nil, 201, "combat_interrupt")
    and robber.pendingRobbery == nil,
    "a zombie/combat interruption at the victim also cancels the robber transfer")

assert(robber:registerAllyDefenseThreat("enemy", 300)
    and robber.allyDefenseThreats.enemy == 300,
    "nearby allies receive a bounded defense permission")

local relationshipSource = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_SurvivorRelationships.lua", "r"
)):read("*a")
assert(relationshipSource:find("activateLocalAllyDefense", 1, true)
    and relationshipSource:find("escalateSurvivorConflict", 1, true),
    "encounter hostility must combine local ally defense with durable escalation")
local controllerSource = assert(io.open(controllerPath, "r")):read("*a")
assert(controllerSource:find("self:cancelRobbery(now, \"combat_interrupt\")", 1, true)
    and controllerSource:find("self:releaseRobberyHold(character, now, \"expired\")", 1, true),
    "robbery holds must clean up on danger and expiry")

print("Natural conflict PASS robbery_transfer=true interruption=true ally_defense=true")
