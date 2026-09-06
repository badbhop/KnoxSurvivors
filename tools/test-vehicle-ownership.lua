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

-- Native add may return without queueing (e.g. an asleep character), and
-- constructing an action may fail before the controller grants its lease.
local d, dc = npc("d")
local originalAdd = ISTimedActionQueue.add
local originalPath = ISPathFindAction.pathToVehicleSeat
local originalEnter = ISEnterVehicle.new
local originalExit = ISExitVehicle.new
local function rejected(call, message)
    local survived, accepted, why = pcall(call)
    assert(survived and not accepted and why == "vehicle_action_failed", message)
    assert(not vehicles.isBusy(d), "failed request must release its lease")
    local q = ISTimedActionQueue.queues[d]
    assert(q == nil or #q.queue == 0, "failed request must remove partially queued actions")
end

local attempts = 0
ISTimedActionQueue.add = function(a)
    attempts = attempts + 1
    -- Match the native silent refusal, not an exception from the queue.
end
rejected(function() return vehicles.board(d, vehicle) end,
    "silent queue refusal must not report boarding success")
assert(attempts == 1, "entry must not queue after rejected pathing")

for _, failure in ipairs({ "silent", "throw", "throw_after_insert" }) do
    attempts = 0
    ISTimedActionQueue.add = function(a)
        attempts = attempts + 1
        if attempts == 1 then return originalAdd(a) end
        if failure == "throw_after_insert" then originalAdd(a) end
        if failure ~= "silent" then error("entry queue failure") end
    end
    rejected(function() return vehicles.board(d, vehicle) end,
        "partial queue failure must cancel the path and release the seat: " .. failure)
end
ISTimedActionQueue.add = originalAdd

for _, factory in ipairs({ "path", "enter", "exit" }) do
    for _, failure in ipairs({ "nil", "throw" }) do
        local broken = function()
            if failure == "throw" then error("constructor failure") end
            return nil
        end
        ISPathFindAction.pathToVehicleSeat = factory == "path" and broken or originalPath
        ISEnterVehicle.new = factory == "enter" and broken or originalEnter
        ISExitVehicle.new = factory == "exit" and broken or originalExit
        d.vehicle = factory == "exit" and vehicle or nil
        local interrupts = dc.interrupts
        rejected(function()
            if factory == "exit" then return vehicles.exit(d) end
            return vehicles.board(d, vehicle)
        end, "constructor failure must reject the entire request: " .. factory .. "/" .. failure)
        assert(dc.interrupts == interrupts, "construction failure must leave ground AI untouched")
    end
end
ISPathFindAction.pathToVehicleSeat = originalPath
ISEnterVehicle.new = originalEnter
ISExitVehicle.new = originalExit
d.vehicle = nil
assert(vehicles.board(d, vehicle), "failed requests must allow a subsequent normal boarding")
vehicles.cancel(d)
d.vehicle = vehicle
ISTimedActionQueue.add = function() end
rejected(function() return vehicles.exit(d) end, "silent exit refusal must not report success")
ISTimedActionQueue.add = originalAdd
assert(vehicles.exit(d), "failed exit must allow retry")
vehicles.cancel(d)
print("Vehicle failure boundary PASS silent=true partial=true construction=true retry=true")

-- Exercise the installed Build 42 queue itself: its sleep refusal returns
-- normally, whereas the lightweight fixture above injects later queue failures.
local game = arg[2] or "C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid"
ISBaseObject = { derive = function(self)
    local class = {}
    class.__index = class
    return setmetatable(class, { __index = self })
end }
instanceof = function(_, name) return name == "IsoGameCharacter" end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
for _, name in ipairs({ "ClimbThroughWindowState", "ClimbOverFenceState", "ClimbOverWallState",
    "ClimbSheetRopeState", "ClimbDownSheetRopeState", "CloseWindowState", "OpenWindowState" }) do
    local state = {}
    _G[name] = { instance = function() return state end }
end
Events = { OnTick = { Add = function() end } }
dofile(game .. "/media/lua/client/TimedActions/ISTimedActionQueue.lua")
local native, nc = npc("native-queue")
native.isAsleep = function(self) return self.asleep end
native.isFarming = function() return false end
native.StopAllActionQueue = function(self) self.stops = (self.stops or 0) + 1 end
local function nativeAction(character)
    return { character = character,
        begin = function(self) self.begun = true end,
        isStarted = function(self) return self.begun == true end,
        forceCancel = function(self) self.cancelled = true end }
end
ISPathFindAction.pathToVehicleSeat = function(_, character) return nativeAction(character) end
ISEnterVehicle.new = function(_, character) return nativeAction(character) end
ISExitVehicle.new = function(_, character) return nativeAction(character) end
native.asleep = true
ok, reason = vehicles.board(native, vehicle)
assert(not ok and reason == "vehicle_action_failed" and not vehicles.isBusy(native),
    "installed native queue's sleep refusal must reject boarding")
native.asleep = false
assert(vehicles.board(native, vehicle) and vehicles.isBusy(native))
local nativeQueue = ISTimedActionQueue.queues[native]
assert(#nativeQueue.queue == 2 and nativeQueue.queue[1].begun,
    "installed queue starts pathing and retains entry")
local entry = nativeQueue.queue[2]
vehicles.cancel(native)
assert(#nativeQueue.queue == 0 and entry.cancelled and native.stops == 1,
    "cancellation must stop native execution and cancel the queued entry")
native.vehicle = vehicle
native.asleep = true
ok, reason = vehicles.exit(native)
assert(not ok and reason == "vehicle_action_failed" and not vehicles.isBusy(native))
native.asleep = false
assert(vehicles.exit(native) and vehicles.isBusy(native))
vehicles.cancel(native)
print("Installed vehicle queue PASS sleepRefusal=true board=true exit=true cancellation=true")
