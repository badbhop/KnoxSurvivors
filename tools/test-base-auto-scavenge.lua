local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local actorSquare = {}
local actor = { getCurrentSquare = function() return actorSquare end }
local worldHours = 10
getGameTime = function() return { getWorldAgeHours = function() return worldHours end } end
KnoxBaseStorage = { summarize = function() return { totals = { food = 0 } } end }
local duties = {
    worker = { mode = "base", baseId = "base-1", eventId = nil,
        jobPreference = "auto", allowLootRuns = true },
}
KnoxPersistence = {
    getBaseResidentIds = function() return { "worker" } end,
    getSurvivorDuty = function(id) return duties[id] end,
    isSurvivorAlive = function() return true end,
    isSurvivorPresent = function() return true end,
    getAwayTeamForSurvivor = function() return nil end,
    getClaimedBaseTaskForSurvivor = function() return nil end,
}
KnoxBaseSupplyPlanner = {
    -- Real shortage logic is covered by its own tests; the election boundary
    -- is what matters here.
    chooseAvailableShortage = function(totals, residents, claims, selfId)
        if (tonumber(totals.food) or 0) < residents * 2 then return "find_food" end
        return nil
    end,
    chooseWorker = function(candidates, goal)
        for _, candidate in ipairs(candidates or {}) do
            if candidate.willing == true and candidate.ready == true then
                return candidate.id
            end
        end
        return nil
    end,
}
KnoxSurvivorRuntime = {
    getCharacter = function() return actor end,
    snapshot = function() return { loaded = true, state = "IDLE" } end,
}
KnoxBaseManager = { containsSquare = function() return true end }

local function controller(id)
    return setmetatable({
        id = id or "worker",
        character = actor,
        base = {},
        baseId = "base-1",
        nextBaseSupplySearch = 0,
    }, Controller)
end

-- An allowed idle resident answers a real storage shortage with an elected trip.
local c = controller()
assert(c:baseSupplyNeed(1000) == "find_food")
assert(c.baseSupplyTrip == true and c.baseSupplyKind == "find_food")
assert(c.nextBaseSupplySearch == 2800, "a claimed trip rechecks on a long cadence")

-- Cooldown holds: no repeated elections every think.
assert(c:baseSupplyNeed(1001) == nil)

-- Another resident's live lease blocks a second claimant.
duties.helper = { mode = "base", baseId = "base-1", eventId = nil,
    jobPreference = "auto", allowLootRuns = true }
KnoxPersistence.getBaseResidentIds = function() return { "worker", "helper" } end
local c2 = controller("helper")
assert(c2:baseSupplyNeed(2000) == nil, "one claimant per shortage kind")

-- Residents without the order stay home even during a shortage.
worldHours = 12
duties.worker.allowLootRuns = false
duties.helper.allowLootRuns = false
c.nextBaseSupplySearch = 0
assert(c:baseSupplyNeed(3000) == nil, "no order means no draft")
duties.worker.allowLootRuns = true
duties.helper.allowLootRuns = true

-- A worker who leaves for an event must release its short-lived supply claim so
-- the next resident can answer the shortage. This mirrors the persistence
-- handoff and prevents a stale lease from making the base look understaffed.
KnoxBaseStorage.summarize = function() return { totals = { food = 0 } } end
KnoxPersistence.isSurvivorPresent = function(id) return id ~= "worker" end
duties.worker.eventId = "event-1"
c.nextBaseSupplySearch = 0
c.baseSupplyTrip = nil
c.baseSupplyKind = nil
assert(c:baseSupplyNeed(5000) == nil,
    "departing claimant must release its stale lease")
local helperAfterHandoff = controller("helper")
assert(helperAfterHandoff:baseSupplyNeed(5001) == "find_food",
    "next resident must take over after supply claimant departs")
duties.worker.eventId = nil

-- A stale departed roster entry can still have base duty data while its body
-- snapshot remains loaded. Presence must be part of election readiness too.
helperAfterHandoff:releaseBaseSupplyClaim("find_food")
KnoxPersistence.isSurvivorPresent = function(id) return id ~= "worker" end
c.nextBaseSupplySearch = 0
c.baseSupplyTrip = nil
c.baseSupplyKind = nil
assert(c:baseSupplyNeed(6000) == nil,
    "departed resident must not be elected from a stale base roster")
local helperAfterDeparture = controller("helper")
assert(helperAfterDeparture:baseSupplyNeed(6001) == "find_food",
    "present resident must take over from a departed roster entry")
KnoxPersistence.isSurvivorPresent = function() return true end

-- Away-team membership is a second durable absence signal even if an older
-- save has not rewritten the resident's duty mode yet.
helperAfterDeparture:releaseBaseSupplyClaim("find_food")
KnoxPersistence.getAwayTeamForSurvivor = function(id)
    return id == "worker" and { id = "away-1" } or nil
end
c.nextBaseSupplySearch = 0
c.baseSupplyTrip = nil
c.baseSupplyKind = nil
assert(c:baseSupplyNeed(7000) == nil,
    "away-team resident must not be elected from stale base duty")
local helperAfterAway = controller("helper")
assert(helperAfterAway:baseSupplyNeed(7001) == "find_food",
    "present resident must take over from an away-team resident")
KnoxPersistence.getAwayTeamForSurvivor = function() return nil end

-- Healthy stores clear the worker's own stale claims and stay home.
KnoxBaseStorage.summarize = function() return { totals = { food = 99 } } end
c.nextBaseSupplySearch = 0
assert(c:baseSupplyNeed(4000) == nil)

-- The decision loop must consult shortages before ordinary work.
local source = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r")):read("*a")
local needPos = string.find(source, "self:baseSupplyNeed(ticks)", 1, true)
local taskPos = needPos ~= nil
    and string.find(source, "if self:beginBaseTask(ticks) then", needPos, true) or nil
assert(needPos ~= nil and taskPos ~= nil and needPos < taskPos,
    "idle residents must answer shortages before accepting ordinary work")

print("Base auto-scavenge PASS election=true lease=true cooldown=true wiring=true permission=true")
