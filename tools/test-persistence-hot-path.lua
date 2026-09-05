local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local modData = {}
ModData = {
    getOrCreate = function(key)
        modData[key] = modData[key] or {}
        return modData[key]
    end,
}
Events = {
    OnSave = { Add = function() end },
    OnGameStart = { Add = function() end },
}

require "KS_Persistence"

-- Establish the normalized graph once, just as OnGameStart does in game.
assert(KnoxPersistence.getPopulationState() ~= nil)
local data = assert(modData["KnoxSurvivors_IsoPlayer"])
local observedBases = data.bases
local realPairs = pairs
local baseScans = 0
pairs = function(value)
    if value == observedBases then baseScans = baseScans + 1 end
    return realPairs(value)
end

-- Hot accessors must not turn into whole-world migration scans.
for _ = 1, 500 do
    KnoxPersistence.getPopulationState()
    KnoxPersistence.getSurvivorIds()
end
assert(baseScans == 0, "cached persistence reads do not rescan every base")

-- Replacing an authoritative domain table invalidates the graph and performs
-- one repair pass, protecting load/migration and test restore boundaries.
data.bases = {}
observedBases = data.bases
KnoxPersistence.getPopulationState()
assert(baseScans == 1, "authoritative graph replacement triggers one normalization")
KnoxPersistence.getPopulationState()
assert(baseScans == 1, "replacement graph is cached after normalization")
pairs = realPairs

print("Persistence hot path PASS cached=true graph_invalidation=true")
