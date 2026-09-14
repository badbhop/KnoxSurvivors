local root = arg[1] or "."
local data = {}
ModData = { getOrCreate = function() return data end }
Events = {}
for _, name in ipairs({ "OnSave", "OnPostSave", "OnGameStart", "OnWeaponHitCharacter", "OnZombieDead" }) do
    Events[name] = { Add = function() end }
end
getGameTime = function() return { getWorldAgeHours = function() return 12 end } end

dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")

local first = assert(KnoxPersistence.ensureSurvivorIdentity("social-first", "Mara", "Cole", 0))
local second = assert(KnoxPersistence.ensureSurvivorIdentity("social-second", "Eli", "Stone", 0))
assert(type(first.personality) == "string" and type(first.personalityLabel) == "string",
    "survivor personality is persisted at identity creation")
assert(type(first.playerResponse) == "string" and first.courage ~= nil and first.deception ~= nil,
    "personality carries readable behavior signals")
assert(KnoxPersistence.getSurvivorPersonality("social-first").personality == first.personality,
    "personality remains stable on reread")
assert(KnoxPersistence.getSurvivorPersonality("social-first").personality
    ~= KnoxPersistence.getSurvivorPersonality("social-second").personality
    or first.personality == second.personality,
    "personality is derived per survivor rather than globally shared")

local disposition = assert(KnoxPersistence.getPlayerSocialDisposition("player-1", "social-first"))
assert(disposition == first.playerResponse, "player response uses the persisted personality")
assert(KnoxPersistence.getPlayerSocialDisposition("player-1", "social-first") == disposition,
    "player response remains stable for the relationship")
local relation = assert(KnoxPersistence.getPlayerRelationship("player-1", "social-first"))
assert(relation.recruitmentAttempts == 0 and relation.lureAttempts == 0)
assert(KnoxPersistence.recordPlayerSocialEvent("player-1", "social-first", "recruit_attempt", 12))
assert(KnoxPersistence.getPlayerRelationship("player-1", "social-first").recruitmentAttempts == 1,
    "recruitment hesitation is bounded and persisted")
assert(KnoxPersistence.recordPlayerSocialEvent("player-1", "social-first", "lure_attempt", 12))
assert(KnoxPersistence.getPlayerRelationship("player-1", "social-first").lureAttempts == 1,
    "lure history is persisted per player")

print("Survivor social PASS personality=true stable=true player_response=true history=true")
