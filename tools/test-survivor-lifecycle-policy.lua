local rootPath = arg[1] or "."
local policy = dofile(rootPath
    .. "/mod/42/media/lua/client/KS_SurvivorLifecyclePolicy.lua")

local should, reason = policy.detachedDecision(nil, 100, 1, 3)
assert(should and reason == "hibernate-no-finite")

should, reason = policy.detachedDecision(25, 100, 1, 3)
assert(not should and reason == "preserve-grace")
should, reason = policy.detachedDecision(25, 100, 2, 3)
assert(not should and reason == "preserve-grace")
should, reason = policy.detachedDecision(25, 100, 3, 3)
assert(not should and reason == "preserve-near-detached",
    "a near native traversal shell must not hibernate after the grace window")

should, reason = policy.detachedDecision(101, 100, 1, 3)
assert(should and reason == "hibernate-far")

assert(policy.distanceEligible(true, "autonomous", 101, 100))
assert(not policy.distanceEligible(true, "companion", 101, 100))
assert(not policy.distanceEligible(false, "autonomous", 101, 100))
assert(not policy.distanceEligible(true, "autonomous", 99, 100))

local autonomyPath = rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua"
local autonomy = assert(io.open(autonomyPath, "r")):read("*a")
assert(autonomy:find("DEAD_REMOVE_PENDING", 1, true),
    "dead bodies must remain registered until engine teardown succeeds")
assert(autonomy:find("bridge:retireNpcAsCorpse(id)", 1, true),
    "dead survivor lifecycle must create a world corpse before shell teardown")
local mainMenuStart = assert(autonomy:find("local function onMainMenuEnter()", 1, true))
local mainMenu = autonomy:sub(mainMenuStart)
assert(mainMenu:find("retireDeadControllers(bridge)", 1, true),
    "save/quit must retire dead shells before capture")
assert(autonomy:find("KnoxPersistence.isSurvivorAlive(id)", 1, true),
    "dead identity persistence must be marked once before cleanup retries")
assert(autonomy:find("return nil, \"dead_identity\"", 1, true),
    "dead identities must not be restored into a living runtime shell")
assert(autonomy:find("character:getVehicle() ~= nil", 1, true)
    and autonomy:find("Passenger shells are owned by the live vehicle", 1, true),
    "occupied vehicle seats must not be hibernated as detached shells")
assert(autonomy:find("preserve-companion-detached", 1, true),
    "detached companions must never hibernate on transient nil squares")

local registryPath = rootPath .. "/java/src/main/java/com/knoxsurvivors/npc/KnoxNpcRegistry.java"
local registry = assert(io.open(registryPath, "r")):read("*a")
assert(registry:find("CORPSE_PENDING_CLEANUP", 1, true),
    "a corpse created before shell cleanup must retain a bounded cleanup retry")
assert(registry:find("runtime.corpseRetirement().corpseCreated()", 1, true),
    "cleanup retry must not construct a second native corpse")

assert(not KnoxSurvivorLifecyclePolicy.restoreAfterDetach(100, 400, 90 * 90), "streaming edge does not rebuild immediately")
assert(KnoxSurvivorLifecyclePolicy.restoreAfterDetach(100, 400, 60 * 60), "closer player releases edge cooldown")
assert(KnoxSurvivorLifecyclePolicy.restoreAfterDetach(100, 1000, 90 * 90), "streaming cooldown is bounded")
assert(KnoxSurvivorLifecyclePolicy.restoreAfterDetach(100, 1, 90 * 90), "clock reset cannot strand a survivor")
print("Survivor lifecycle policy PASS detached_bounded=true companion_distance_safe=true world_distance=true vehicle_safe=true dead_teardown=true corpse_handoff=true cleanup_retry=true save_boundary=true")
