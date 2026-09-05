local rootPath = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local settings = read(rootPath .. "/mod/42/media/lua/client/KS_Settings.lua")
local sandbox = read(rootPath .. "/mod/42/media/sandbox-options.txt")
local nameplates = read(rootPath .. "/mod/42/media/lua/client/KS_SurvivorNameplates.lua")
local relations = read(rootPath .. "/mod/42/media/lua/client/KS_HumanCombatRelations.lua")
local autonomy = read(rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local activity = read(rootPath .. "/mod/42/media/lua/client/KS_ActivityFeed.lua")
local combat = read(rootPath .. "/java/src/main/java/com/knoxsurvivors/npc/KnoxCombatController.java")
assert(not string.find(combat, '"setFactionPvp"', 1, true)
    and not string.find(combat, '"setCoopPVP"', 1, true),
    "NPC combat must not mutate real-player faction or global PvP settings")

assert(string.find(settings, "WorldPopulation = 48", 1, true)
    and string.find(sandbox, "max = 256, default = 48", 1, true),
    "new worlds must use the balanced survivor population default")
for _, relation in ipairs({ "hostile", "neutral", "friendly", "ally" }) do
    assert(string.find(nameplates, relation .. " =", 1, true),
        "nameplate relationship colour missing: " .. relation)
end
assert(string.find(nameplates, "player:CanSee(character)", 1, true)
    and string.find(nameplates, "character:setShowTag(true)", 1, true),
    "native player-style tags must remain line-of-sight gated")
assert(not string.find(nameplates, "setFactionPvp", 1, true),
    "nameplates must not mutate engine PvP state")
assert(string.find(relations, "Events.OnWeaponHitCharacter", 1, true)
    and string.find(relations, "setSurvivorHostileToPlayer", 1, true),
    "a native player hit must create a durable hostile response")
assert(string.find(autonomy, "areSurvivorsHostile", 1, true)
    and string.find(autonomy, "allowSurvivorPlayerCombat", 1, true)
    and string.find(autonomy, "beginNpcLiveCombat", 1, true),
    "hostile human targets must route into the existing native combat owner")
assert(string.find(activity, "showSurvivorSpeech", 1, true)
    and string.find(activity, "addLineChatElement", 1, true),
    "optional survivor speech must use the native overhead ChatElement")

print("Player-facing survivors PASS population=true names=true human_target_dispatch=true player_safety=true; native human damage requires live verification")
