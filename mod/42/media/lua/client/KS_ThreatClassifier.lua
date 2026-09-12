local Threats = rawget(_G, "KnoxThreatClassifier") or {}
_G.KnoxThreatClassifier = Threats

-- Build 42 uses an IsoZombie as the physical grapple representation of a
-- carried corpse. It is not alive for AI purposes even when isDead() is false.
-- The engine flag distinguishes that body from actual zombie reanimation.
function Threats.isCorpseProxy(character)
    if character == nil then return false end
    local ok, proxy = pcall(function() return character:isReanimatedForGrappleOnly() end)
    return ok and proxy == true
end
return Threats
