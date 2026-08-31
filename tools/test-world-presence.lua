local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = {}
ModData = { getOrCreate = function(key) data[key] = data[key] or {} return data[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 20 end } end
SandboxVars = { KnoxSurvivors = { WorldPopulation = 6 } }
package.preload.SpawnRegions = function() return true end
SpawnRegionMgr = { getSpawnRegions = function()
    return { { name = "Town", points = { unemployed = {
        { posX = 100, posY = 100, posZ = 0 }, { posX = 300, posY = 100, posZ = 0 },
        { posX = 600, posY = 100, posZ = 0 }, { posX = 900, posY = 100, posZ = 0 },
    } } } }
end }
local function list(items)
    return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
end
local function room(x, y, z)
    local rect = { getX = function() return x end, getY = function() return y end,
        getW = function() return 10 end, getH = function() return 8 end }
    return { getZ = function() return z end, getRects = function() return list({ rect }) end }
end
local function building(rooms)
    return { getRooms = function() return list(rooms) end }
end
local scans = 0
getWorld = function() return {
    getMap = function() return "Presence test" end,
    getMetaGrid = function() return { getBuildings = function()
        scans = scans + 1
        return list({ building({ room(400, 100, 0) }), building({ room(410, 110, 0) }),
            building({ room(700, 100, 0) }), building({ room(1200, 100, 1) }),
            building({ room(1500, 100, 0) }), {} })
    end } end,
} end
require "KS_Persistence"
local persistence = KnoxPersistence
local population = require "KS_WorldPopulation"
local simulation = require "KS_UnloadedSurvival"
local catalog = assert(population.spawnCatalog())
assert(catalog.buildingOrigins == 3, "one native ground-floor building per spatial bucket")
assert(catalog.byKey["405,104,0"] and not catalog.byKey["415,114,0"], "uses actual room rectangle")
assert(not catalog.byKey["1205,104,0"], "upper-floor-only building is not a ground spawn")
assert(#catalog.origins == 7, "player starts retained alongside native building metadata")
population.spawnCatalog()
assert(scans == 1, "native world catalog cached instead of rescanned per survivor")
local initial = population.maintain(0)
local sources = {}
for _, id in ipairs(initial.addedIds) do
    local origin = persistence.getSurvivorOrigin(id)
    sources[origin.source] = (sources[origin.source] or 0) + 1
end
assert(sources.player_spawn == 4 and sources.world_building == 2,
    "initial distribution retains player starts and supplements with real buildings")
local id = initial.addedIds[1]
local origin = persistence.getSurvivorOrigin(id)
local start = persistence.getUnloadedSurvivalState(id)
assert(start.pendingMaterialization and start.health == nil and start.hunger == nil,
    "origin ledger must not invent health or food state before real initialization")
assert(not population.advanceOriginTravel(id, 0), "no travel before time advances")
assert(population.advanceOriginTravel(id, 4), "never-seen survivor begins its persisted trip")
local moving = persistence.getUnloadedSurvivalState(id)
assert(moving.virtualX ~= origin.x or moving.virtualY ~= origin.y,
    "unmaterialized identity is no longer pinned forever to its starting house")
assert(persistence.getSurvivorOrigin(id).key == origin.key, "travel does not rewrite birth origin")
assert(persistence.getRecord(id) == nil, "virtual travel does not manufacture an engine body record")
assert(not population.advanceOriginTravel(id, 4), "same game time cannot advance travel twice")
assert(not population.advanceOriginTravel(id, 3), "clock rollback cannot reverse or duplicate travel")
local targetKey = moving.travelTarget.key
population.advanceOriginTravel(id, 4.1)
assert(persistence.getUnloadedSurvivalState(id).travelTarget.key == targetKey,
    "existing route remains stable across population refresh")

-- A save/reload persists the serializable itinerary, not an engine object or local cache.
local persisted = persistence.getUnloadedSurvivalState(id)
population.advanceOriginTravel(id, 12)
local straight = persistence.getUnloadedSurvivalState(id)
persistence.setUnloadedSurvivalState(id, persisted)
package.loaded.KS_WorldPopulation = nil
KnoxWorldPopulation = nil
population = require "KS_WorldPopulation"
for hour = 5, 12 do population.advanceOriginTravel(id, hour) end
local segmented = persistence.getUnloadedSurvivalState(id)
assert(math.abs(straight.virtualX - segmented.virtualX) < 0.000001
    and math.abs(straight.virtualY - segmented.virtualY) < 0.000001
    and straight.currentTravelKey == segmented.currentTravelKey,
    "reload and regular refresh produce the same bounded itinerary")
local sequence = segmented.travelSequence
population.advanceOriginTravel(id, 1000000)
assert(persistence.getUnloadedSurvivalState(id).travelSequence <= sequence + 8,
    "very old save catch-up has bounded decision cost")

-- Materialization uses current virtual position and ordinary hidden-square rules.
persistence.setUnloadedSurvivalState(id, moving)
local x, y = math.floor(moving.virtualX), math.floor(moving.virtualY)
local visible, occupied, burning, loaded = false, false, false, true
local square = { getX = function() return x end, getY = function() return y end,
    getZ = function() return 0 end, canStand = function() return true end,
    isCanSee = function() return visible end, haveFire = function() return burning end,
    getMovingObjects = function() return { size = function() return occupied and 1 or 0 end } end }
getCell = function() return { getGridSquare = function(_, sx, sy, sz)
    if loaded and sx == x and sy == y and sz == 0 then return square end
end } end
local px, py = x + 100, y
local player = { getCurrentSquare = function() return {
    getX = function() return px end, getY = function() return py end } end,
    getPlayerNum = function() return 0 end }
local options = { players = { player }, minimumDistance = 60, maximumDistance = 220 }
local candidate = assert(population.activationCandidate(id, {}, options))
assert(candidate.x == x and candidate.y == y and candidate.origin.key == origin.key,
    "first body appears at progressed location, retaining original identity origin")
visible = true
assert(not population.activationCandidate(id, {}, options), "no visible first materialization")
visible, occupied = false, true
assert(not population.activationCandidate(id, {}, options), "no occupied first materialization")
occupied, burning = false, true
assert(not population.activationCandidate(id, {}, options), "no burning first materialization")
burning, loaded = false, false
assert(not population.activationCandidate(id, {}, options), "no fallback teleport when virtual square unloaded")
loaded, px = true, x + 2
assert(not population.activationCandidate(id, {}, options), "no first spawn beside the player")
px = x + 1000
assert(not population.activationCandidate(id, {}, options), "no distant activation")
assert(persistence.getUnloadedSurvivalState(id).virtualX == moving.virtualX,
    "activation rejection/player travel never moves the identity")
local corrupt = persistence.getUnloadedSurvivalState(id)
corrupt.virtualX = nil
persistence.setUnloadedSurvivalState(id, corrupt)
local invalid, invalidReason = population.activationCandidate(id, {}, options)
assert(not invalid and invalidReason == "virtual_location_unavailable",
    "malformed progressed location cannot silently respawn at the birth origin")
persistence.setUnloadedSurvivalState(id, moving)

local applied, reason = simulation.applyToLoaded(id, {})
assert(not applied and reason == "no_real_survival_snapshot",
    "position-only ledger never writes fake zero health into a new character")
local before = persistence.getUnloadedSurvivalState(id).lastHours
simulation.advanceAll(initial.addedIds, 25)
assert(persistence.getUnloadedSurvivalState(id).lastHours == before, "active identities excluded")
simulation.advanceAll({}, 25)
assert(persistence.getUnloadedSurvivalState(id).lastHours == 25, "normal inactive reconciliation advances origin travel")

-- Real capture takes ownership and discards stale pre-body/offscreen routing.
persistence.setRecord(id, "real-captured-record")
KnoxJavaBridge = { getTestNpcRecordX = function() return 990 end,
    getTestNpcRecordY = function() return 321 end, getTestNpcRecordZ = function() return 1 end }
assert(simulation.captureLoaded(id, { hunger = .2, thirst = .3, health = 83,
    fatigue = .1, endurance = .9, bleedingParts = 1 }, 26))
local captured = persistence.getUnloadedSurvivalState(id)
assert(not captured.pendingMaterialization and captured.travelTarget == nil and captured.health == 83,
    "real capture replaces location-only ledger with authoritative body state")
assert(captured.virtualX == 990 and captured.virtualY == 321 and captured.virtualZ == 1,
    "fresh real body position replaces old virtual location after loaded travel")
assert(not population.advanceOriginTravel(id, 28), "captured survivor cannot reenter origin simulation")
captured.activity = "surviving"
persistence.setUnloadedSurvivalState(id, captured)
local relocationCalls = 0
KnoxJavaBridge.relocateNpcRecord = function()
    relocationCalls = relocationCalls + 1
    return "unexpected-relocation"
end
local distant = population.activationCandidate(id, KnoxJavaBridge,
    { players = { player }, maximumDistance = 1 })
assert(distant == nil and relocationCalls == 0, "distant virtual candidate is not rewritten")
population.activationCandidates(KnoxJavaBridge, {}, 0, options)
assert(relocationCalls == 0, "full activation budget does not mutate waiting records")
local deadId = initial.addedIds[2]
persistence.markSurvivorDead(deadId, 26, "test")
assert(not population.advanceOriginTravel(deadId, 28), "dead identity does not advance or resurrect")

-- An old save without the new ledger starts at its actual origin, not years away.
local legacyId = initial.addedIds[3]
for _, root in pairs(data) do
    if root.survivors and root.survivors[legacyId] then root.survivors[legacyId].unloadedSurvival = nil end
end
population.advanceOriginTravel(legacyId, 500)
assert(persistence.getUnloadedSurvivalState(legacyId).lastHours == 500, "legacy initializer persists its clock")
assert(population.advanceOriginTravel(legacyId, 501), "legacy identity can progress on the next refresh")

-- Stored bodies use the same production itinerary through real persistence,
-- with no invented item or IsoPlayer. Rest survives a module reload mid-trip.
KnoxSurvivorNeeds = { sleepRequired = function() return true end }
KnoxJavaBridge.getTestNpcRecordX = function() return 100 end
KnoxJavaBridge.getTestNpcRecordY = function() return 100 end
KnoxJavaBridge.getTestNpcRecordZ = function() return 0 end
simulation.captureLoaded(id, { hunger = .1, thirst = .1, health = 100,
    fatigue = .1, endurance = .9, bleedingParts = 0 }, 26)
assert(simulation.advanceHibernated(id, 27))
local travelling = persistence.getUnloadedSurvivalState(id)
local travelDistance = math.sqrt((travelling.virtualX - 100)^2 + (travelling.virtualY - 100)^2)
assert(math.abs(travelDistance - 40) < .000001 and travelling.travelTarget,
    "captured independent survivor uses the real nearby-catalog itinerary")
assert(travelling.fatigue > .1 and travelling.endurance < .9,
    "production travel charges awake fatigue and walking endurance")
travelling.fatigue = .8
persistence.setUnloadedSurvivalState(id, travelling)
simulation.advanceHibernated(id, 30)
local resting = persistence.getUnloadedSurvivalState(id)
assert(resting.restMode == "sleep" and resting.travelTarget.key == travelling.travelTarget.key
    and resting.virtualX == travelling.virtualX and resting.virtualY == travelling.virtualY,
    "persisted sleep pauses the actual itinerary")
simulation.advanceHibernated(id, 36)
local uninterrupted = persistence.getUnloadedSurvivalState(id)
persistence.setUnloadedSurvivalState(id, resting)
package.loaded.KS_UnloadedSurvival = nil
KnoxUnloadedSurvival = nil
simulation = require "KS_UnloadedSurvival"
for hour = 31, 36 do simulation.advanceHibernated(id, hour) end
local resumed = persistence.getUnloadedSurvivalState(id)
assert(math.abs(uninterrupted.virtualX - resumed.virtualX) < .000001
    and math.abs(uninterrupted.virtualY - resumed.virtualY) < .000001
    and math.abs(uninterrupted.fatigue - resumed.fatigue) < .000001
    and math.abs(uninterrupted.endurance - resumed.endurance) < .000001,
    "reload and segmented refresh preserve travel/rest progress")
local finalX, finalY = resumed.virtualX, resumed.virtualY
simulation.advanceHibernated(id, 36)
resumed = persistence.getUnloadedSurvivalState(id)
assert(resumed.virtualX == finalX and resumed.virtualY == finalY,
    "same clock cannot move a stored body twice")
-- Rest must not send restoration back to the old captured tile. Every new
-- offscreen phase keeps the hidden-square validation and virtual record handoff.
x, y = math.floor(resumed.virtualX), math.floor(resumed.virtualY)
px, py = x + 100, y
loaded, visible, occupied, burning = true, false, false, false
local handoffs = 0
KnoxJavaBridge.relocateNpcRecord = function(_, record, sx, sy, sz)
    assert(sx == x and sy == y and sz == 0, "restored location is current virtual position")
    handoffs = handoffs + 1
    return record .. ":relocated"
end
for _, phase in ipairs({ "sleeping", "resting", "sheltering", "group_waiting", "group_regrouping" }) do
    resumed.activity = phase
    persistence.setUnloadedSurvivalState(id, resumed)
    local restored = assert(population.activationCandidate(id, KnoxJavaBridge, options))
    assert(restored.x == x and restored.y == y, phase .. " restores progressed position")
    visible = true
    assert(not population.activationCandidate(id, KnoxJavaBridge, options),
        phase .. " cannot bypass hidden-square verification")
    visible = false
end
assert(handoffs == 5, "each resting/group phase uses the native record relocation boundary once")
resumed.restMode, resumed.travelPhase = "sleep", "moving"
persistence.setUnloadedSurvivalState(id, resumed)
simulation.captureLoaded(id, { hunger = .1, thirst = .1, health = 100,
    fatigue = .1, endurance = .9, bleedingParts = 0 }, 37)
local fresh = persistence.getUnloadedSurvivalState(id)
assert(fresh.restMode == nil and fresh.travelPhase == nil and fresh.travelTarget == nil,
    "real capture releases stale virtual rest and travel intent")
print("World presence PASS metadata=true persisted_travel=true bounded=true native_handoff=true hidden_spawn=true")
