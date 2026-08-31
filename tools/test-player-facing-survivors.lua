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

assert(string.find(settings, "WorldPopulation = 32", 1, true)
    and string.find(sandbox, "max = 256, default = 32", 1, true),
    "new worlds must use the expanded survivor population default")
for _, relation in ipairs({ "hostile", "neutral", "friendly", "ally" }) do
    assert(string.find(nameplates, relation .. " =", 1, true),
        "nameplate relationship colour missing: " .. relation)
end
assert(string.find(nameplates, "player:CanSee(character)", 1, true)
    and string.find(nameplates, "character:setShowTag(true)", 1, true),
    "native player-style tags must remain line-of-sight gated")
assert(string.find(relations, "Events.OnWeaponHitCharacter", 1, true)
    and string.find(relations, "setSurvivorHostileToPlayer", 1, true),
    "a native player hit must create a durable hostile response")
assert(string.find(autonomy, "areSurvivorsHostile", 1, true)
    and string.find(autonomy, "allowSurvivorPlayerCombat", 1, true)
    and string.find(autonomy, "beginNpcLiveCombat", 1, true),
    "hostile human targets must route into the existing native combat owner")

print("Player-facing survivors PASS population=true names=true human_combat=true")
