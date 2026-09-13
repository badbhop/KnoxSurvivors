local root = arg[1] or "."
local duty = dofile(root .. "/mod/42/media/lua/client/KS_BaseDutySimulation.lua")

local guard = { type = "guard", state = "claimed" }
local complete, hours = duty.advance(guard, 1.5)
assert(complete == false and hours == 1.5, "watch shift should accumulate work")
complete, hours = duty.advance(guard, 2.5)
assert(complete == true and hours == 4 and guard.offscreenWorkHours == 0,
    "watch shift should complete once per four hours")
assert(guard.offscreenShiftsCompleted == 1 and guard.guardReliefCount == nil,
    "elapsed watch time must not invent replacement guards")

local longGuard = { type = "guard", state = "claimed" }
complete, hours = duty.advance(longGuard, 10.5)
assert(complete == true and hours == 8 and longGuard.offscreenShiftsCompleted == 2
    and longGuard.guardReliefCount == nil and longGuard.offscreenWorkHours == 2.5,
    "long unloaded intervals should preserve every completed guard shift and remainder")

KnoxCompanionPatrol = {
    waypoints = function()
        return { { x = 1, y = 1, z = 0 }, { x = 2, y = 2, z = 0 },
            { x = 3, y = 3, z = 0 } }
    end,
}
local patrol = { type = "patrol", state = "claimed", patrolStep = 0,
    patrolStopsCompleted = 1 }
complete = duty.advance(patrol, 12.5)
assert(complete == true and patrol.offscreenShiftsCompleted == 3
    and patrol.patrolStep == 0 and patrol.patrolStopsCompleted == 1,
    "unloaded time leaves physical patrol evidence unchanged")
KnoxCompanionPatrol.waypoints = function()
    return { { x = 1, y = 1, z = 0 }, { x = 2, y = 2, z = 0 },
        { x = 3, y = 3, z = 0 }, { x = 4, y = 4, z = 0 } }
end
local fourPointPatrol = { type = "patrol", state = "claimed", patrolStep = 1,
    patrolStopsCompleted = 1 }
assert(duty.advance(fourPointPatrol, 12.5) == true
    and fourPointPatrol.patrolStep == 1
    and fourPointPatrol.patrolStopsCompleted == 1,
    "streaming must not invent waypoint arrivals or erase actual route progress")

local physical = { type = "farm_seed", state = "claimed" }
complete = duty.advance(physical, 20)
assert(complete == false and physical.offscreenWorkHours == nil,
    "physical jobs must remain for native loaded execution")

local queued = { type = "guard", state = "queued" }
complete = duty.advance(queued, 20)
assert(complete == false, "queued work must not advance")
local legacyStorage = { type = "storage_sorting", state = "claimed" }
assert(not duty.canAdvanceOffscreen(legacyStorage),
    "legacy storage tasks must remain physical loaded-world work")

local persistenceSource = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_Persistence.lua", "r"
)):read("*a")
assert(persistenceSource:find("offscreenShiftsCompleted", 1, true)
    and persistenceSource:find("guardReliefCount", 1, true),
    "task migration must preserve bounded unloaded security counters")
assert(persistenceSource:find("hard%-coded", 1, false)
    and persistenceSource:find("runtime", 1, true)
    and not persistenceSource:find(") % 4", 1, true),
    "patrol migration must defer route geometry to the runtime waypoint owner")
print("base duty simulation tests passed")
