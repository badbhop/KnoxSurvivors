local root = arg[1] or "."
require = function() return true end
local threats = dofile(root .. "/mod/42/media/lua/client/KS_ThreatClassifier.lua")

-- A hostile faction fighter is a human shell: no grapple-only method at all.
-- Classifying it used to throw a Java exception through pcall and kill the
-- whole threat scan every tick the faction was near.
instanceof = function(object, class)
    return object.__zombie == true and class == "IsoZombie"
end
local fighter = { __zombie = false }
local ok, result = pcall(function() return threats.isCorpseProxy(fighter) end)
assert(ok and result == false, "human shells must classify cleanly as non-proxies")

-- Real zombies keep their classification, including grapple bodies.
local zombie = { __zombie = true,
    isReanimatedForGrappleOnly = function() return false end }
assert(threats.isCorpseProxy(zombie) == false)
local grapple = { __zombie = true,
    isReanimatedForGrappleOnly = function() return true end }
assert(threats.isCorpseProxy(grapple) == true)
assert(threats.isCorpseProxy(nil) == false)

print("Threat classifier PASS human_safe=true zombie_proxy=true")
