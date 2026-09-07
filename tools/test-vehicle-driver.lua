local root = arg[1] or "."
require = function() return true end

local now = 0
getTimestampMs = function() return now end
KnoxSettings = { enableExperimentalNpcDriving = function() return true end }
local origin = {
    getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end, canStand = function() return true end,
    isBlockedTo = function() return false end,
}
local function targetSquare(x, y)
    return {
        getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end, canStand = function() return true end,
        isBlockedTo = function() return false end,
    }
end
getCell = function()
    return { getGridSquare = function(_, x, y)
        return targetSquare(x, y)
    end }
end

ISTimedActionQueue = { queues = {}, add = function(action)
    local queue = ISTimedActionQueue.queues[action.character]
    if queue == nil then queue = { queue = {} }; ISTimedActionQueue.queues[action.character] = queue end
    queue.queue[#queue.queue + 1] = action
end, clear = function(character)
    ISTimedActionQueue.queues[character] = { queue = {} }
end }
ISPathFindAction = { pathToVehicleSeat = function(_, character, _, seat)
    return { character = character, seat = seat }
end }
ISEnterVehicle = { new = function(_, character, _, seat)
    return { character = character, seat = seat }
end }
ISExitVehicle = {}
ISCloseVehicleDoor = nil

local runtime = { idForCharacter = function() return "driver" end,
    prepareVehicle = function() return true end }
KnoxSurvivorRuntime = runtime
local controls = { resetCount = 0, reset = function(self)
    self.resetCount = self.resetCount + 1
    self.forward, self.backward, self.brake, self.steering = false, false, false, 0
end }
local controller = {
    getClientControls = function() return controls end,
    park = function(self) self.parked = true end,
    control_NoControl = function(self) self.released = true end,
}
local character = {
    vehicle = nil,
    getVehicle = function(self) return self.vehicle end,
    getBodyDamage = function() return { getHealth = function() return 100 end } end,
    isDead = function() return false end,
}
local vehicle = {
    x = 0, y = 0, driver = nil,
    isSeatOccupied = function(self) return self.driver ~= nil end,
    isSeatInstalled = function() return true end,
    isEnterBlocked = function() return false end,
    getPassengerDoor = function() return nil end,
    getDriver = function(self) return self.driver end,
    isEngineRunning = function() return true end,
    isDriveable = function() return true end,
    getAngleZ = function() return 0 end,
    getSquare = function() return origin end,
    getX = function(self) return self.x end,
    getY = function(self) return self.y end,
    getController = function() return controller end,
}

local vehicles = dofile(root .. "/mod/42/media/lua/client/KS_CompanionVehicles.lua")
local started, reason = vehicles.driveAhead(character, vehicle)
assert(started and reason == "driving_ahead", "opt-in driver request is accepted")
assert(vehicles.activity(character) == "driving", "driver activity is visible during boarding")
vehicle.driver, character.vehicle = character, vehicle
ISTimedActionQueue.clear(character)
vehicles.tick(1)
vehicles.tick(2)
assert(controls.forward and not controls.backward and not controls.brake,
    "native client controls receive forward drive input")
vehicle.x, vehicle.y = 0, 18
vehicles.tick(3)
assert(not controls.forward and controls.resetCount > 0 and controller.parked
        and controller.released, "driver brakes and releases controls at the bounded target")
assert(vehicles.activity(character) == "riding", "completed drive returns to ordinary riding activity")
KnoxSettings.enableExperimentalNpcDriving = function() return false end
local rejected, rejectedReason = vehicles.driveAhead(character, vehicle)
assert(not rejected and rejectedReason == "npc_driving_disabled",
    "driver slice is disabled when the sandbox experiment is off")
print("Vehicle driver PASS opt_in=true seat_entry=true forward=true bounded_stop=true release=true")
