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

print("Survivor lifecycle policy PASS detached_bounded=true companion_distance_safe=true world_distance=true")
