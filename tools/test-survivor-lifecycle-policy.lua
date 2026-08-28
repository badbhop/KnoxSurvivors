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
assert(should and reason == "hibernate-grace-expired")

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
assert(autonomy:find("bridge:removeNpc(id)", 1, true),
    "dead survivor lifecycle must request engine-shell removal")
assert(autonomy:find("character:getVehicle() ~= nil", 1, true)
    and autonomy:find("Passenger shells are owned by the live vehicle", 1, true),
    "occupied vehicle seats must not be hibernated as detached shells")

print("Survivor lifecycle policy PASS detached_bounded=true companion_distance_safe=true world_distance=true vehicle_safe=true dead_teardown=true corpse_handoff=true")
