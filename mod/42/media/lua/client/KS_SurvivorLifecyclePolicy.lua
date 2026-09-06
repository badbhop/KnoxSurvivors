local LifecyclePolicy = rawget(_G, "KnoxSurvivorLifecyclePolicy") or {}
_G.KnoxSurvivorLifecyclePolicy = LifecyclePolicy

function LifecyclePolicy.detachedDecision(
    finiteDistanceSquared,
    activeDistanceSquared,
    grace,
    graceLimit
)
    grace = math.max(1, math.floor(tonumber(grace) or 1))
    graceLimit = math.max(1, math.floor(tonumber(graceLimit) or 1))
    if finiteDistanceSquared == nil then
        return true, "hibernate-no-finite"
    end
    if finiteDistanceSquared > activeDistanceSquared then
        return true, "hibernate-far"
    end
    local shouldHibernate = grace >= graceLimit
    return shouldHibernate,
        shouldHibernate and "hibernate-grace-expired" or "preserve-grace"
end

function LifecyclePolicy.distanceEligible(
    isWorldSurvivor,
    dutyMode,
    distanceSquared,
    activeDistanceSquared
)
    return isWorldSurvivor == true
        and dutyMode ~= "companion"
        and distanceSquared ~= nil
        and distanceSquared > activeDistanceSquared
end

-- A just-streamed-out square can briefly resolve again at the cell edge.
-- Wait for a closer player or a bounded retry instead of rebuilding repeatedly.
function LifecyclePolicy.restoreAfterDetach(detachedAt, ticks, distanceSquared)
    return detachedAt == nil or ticks < detachedAt or ticks - detachedAt >= 900
        or (distanceSquared ~= nil and distanceSquared <= 64 * 64)
end

return LifecyclePolicy
