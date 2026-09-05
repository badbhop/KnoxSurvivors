local root = arg[1] or "."
require = function() end
local callbacks = {}
Events = {}
for _, event in ipairs({"OnWeaponSwing", "OnWeaponSwingHitPoint", "OnWeaponHitCharacter", "OnZombieDead"}) do
    Events[event] = { Add = function(fn) callbacks[event] = fn end }
end
local player, npc = {}, {}
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return player end
local enabled, pvp, hostile, trust = true, true, false, 0
local affiliation = {kind = "independent"}
local faction, factionRelation
KnoxSettings = {enabled = function() return enabled end, allowSurvivorPlayerCombat = function() return pvp end}
KnoxPersistence = {
    ensurePlayerId = function() return "p" end,
    getSurvivorAffiliation = function() return affiliation end,
    isSurvivorHostileToPlayer = function() return hostile end,
    getPlayerFaction = function() return faction end,
    getFactionRelationship = function() return factionRelation end,
    getPlayerRelationshipSnapshot = function() return {trust = trust} end,
}
KnoxSurvivorRuntime = {activeIds = function() return {"npc"} end}
KnoxActivityFeed = {}
local starts, permissions = 0, {}
KnoxJavaBridge = {
    beginPlayerHumanAttack = function(_, actor) assert(actor == player); starts = starts + 1; permissions = {}; return true end,
    setPlayerHumanAttackTarget = function(_, actor, id, allowed) assert(actor == player); permissions[id] = allowed end,
}
local human = dofile(root .. "/mod/42/media/lua/client/KS_HumanCombatRelations.lua")
assert(callbacks.OnWeaponSwing == human.onWeaponSwing and callbacks.OnWeaponSwingHitPoint == human.onWeaponSwing)
callbacks.OnWeaponSwing(player)
assert(permissions.npc == true and not hostile, "neutral attack eligibility must not invent hostility")
affiliation = {kind = "player", ownerId = "p"}
callbacks.OnWeaponSwingHitPoint(player)
assert(permissions.npc == false, "recruitment during windup protects companion before collision")
affiliation = {kind = "independent"}
trust = 30
assert(not human.canPlayerAttack("p", "npc"), "friendly trust protects survivor")
hostile = true
assert(human.canPlayerAttack("p", "npc"), "actual hostility overrides old personal trust")
affiliation = {kind = "player", ownerId = "other-player"}
assert(not human.canPlayerAttack("p", "npc"), "owned settlers/companions are protected")
hostile, trust = false, 0
affiliation, faction = {kind = "faction", factionId = "f"}, {id = "f"}
assert(not human.canPlayerAttack("p", "npc"), "same faction protected")
faction.id, factionRelation = "g", {disposition = "allied"}
assert(not human.canPlayerAttack("p", "npc"), "allied faction protected")
factionRelation = nil
assert(human.canPlayerAttack("p", "npc"), "neutral faction can be attacked")
pvp = false
assert(not human.canPlayerAttack("p", "npc"), "sandbox off denies attack")
pvp, enabled = true, false
assert(not human.canPlayerAttack("p", "npc"), "disabled mod denies attack")
local before = starts
callbacks.OnWeaponSwing(npc)
assert(starts == before, "NPC swing does not become player aggression")
KnoxJavaBridge = {}
assert(pcall(callbacks.OnWeaponSwing, player), "older bridge fails safely")
print("Player human attack PASS native_events=true neutral=true friendly=true recruitment=true sandbox=true")
