local root = arg[1] or "."
require = function() return true end
local now, failAdd = 0, false
getTimestampMs = function() return now end
ISTimedActionQueue = { queues = {},
    add = function(action)
        if failAdd then error("queue rejected") end
        local q = ISTimedActionQueue.queues[action.character]
        if q == nil then q = {queue = {}}; ISTimedActionQueue.queues[action.character] = q end
        q.queue[#q.queue + 1] = action
    end,
    clear = function(character) ISTimedActionQueue.queues[character] = {queue = {}} end,
}
local function action(character) return {character = character} end
ISPathFindAction = {pathToVehicleSeat = function(self, character) return action(character) end}
ISEnterVehicle = {new = function(self, character) return action(character) end}
ISExitVehicle = {new = function(self, character) return action(character) end}
local runtime = dofile(root .. "/mod/42/media/lua/client/KS_SurvivorRuntime.lua")
local vehicles = dofile(root .. "/mod/42/media/lua/client/KS_CompanionVehicles.lua")
local function npc(id)
    local character = { getVehicle = function(self) return self.vehicle end }
    local controller = {character = character, interrupts = 0,
        interruptForDirective = function(self) self.interrupts = self.interrupts + 1; return true end}
    runtime.register(id, controller)
    return character, controller
end
local vehicle = {getMaxPassengers = function() return 3 end,
    isSeatOccupied = function() return false end,
    getPassengerDoor = function() return nil end}
local a, ac = npc("a")
local b, bc = npc("b")
local c = npc("c")
assert(vehicles.board(a, vehicle))
assert(ac.interrupts == 1 and vehicles.isBusy(a))
local ok, reason = vehicles.board(a, vehicle)
assert(not ok and reason == "vehicle_action_pending" and #ISTimedActionQueue.queues[a].queue == 2)
ok, reason = vehicles.board(b, vehicle)
assert(ok and reason == "boarding_seat=2", "same-tick party boarding must reserve distinct seats")
ok, reason = vehicles.board(c, vehicle)
assert(not ok and reason == "no_free_passenger_seat")
ISTimedActionQueue.clear(a)
ok, reason = vehicles.board(c, vehicle)
assert(ok and reason == "boarding_seat=1", "failed path must release the reservation")
now = 45001
assert(not vehicles.isBusy(b) and #ISTimedActionQueue.queues[b].queue == 0, "timeout must release native action ownership")
vehicles.cancel(c)
failAdd = true
assert(not vehicles.board(a, vehicle) and not vehicles.isBusy(a), "queue failure must not leak a reservation")
failAdd = false
ISTimedActionQueue.add(action(a))
ok, reason = vehicles.board(a, vehicle)
assert(not ok and reason == "survivor_busy", "boarding must preserve an existing timed action")
ISTimedActionQueue.clear(a)
a.vehicle = vehicle
assert(vehicles.exit(a))
assert(not vehicles.exit(a), "repeated exit must not duplicate actions")
ISTimedActionQueue.clear(a); assert(not vehicles.isBusy(a))
-- Real controller must leave native passenger actions and seated occupants alone.
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local guard = setmetatable({character = a, state = "IDLE"}, {__index = KnoxAutonomyController})
guard:tick(1) -- no square/AI methods: reaching them would fail this check
a.vehicle = nil
assert(vehicles.board(a, vehicle))
guard:tick(2)
vehicles.cancel(a)
local hp = 100
a.getBodyDamage = function() return {getHealth = function() return hp end} end
assert(vehicles.board(a, vehicle))
hp = 99
local busy, result = vehicles.isBusy(a)
assert(not busy and result == "interrupted" and #ISTimedActionQueue.queues[a].queue == 0,
    "real injury must interrupt boarding for normal threat reevaluation")
assert(vehicles.board(a, vehicle))
runtime.unregister("a")
assert(not vehicles.isBusy(a) and #ISTimedActionQueue.queues[a].queue == 0,
    "retiring the body must release pending boarding and its seat")
assert(vehicles.board(b, vehicle))
runtime.clear()
assert(not vehicles.isBusy(b), "world reset must release transient vehicle references")
print("Vehicle ownership PASS seats=true duplicates=true timeout=true queueFailure=true busy=true seated=true")
