local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(string.find(source, 'require "TimedActions/ISMedicalCheckAction"', 1, true),
    "companion treatment must use the native medical check action")
assert(not string.find(source, 'ISHealthPanel.canPerformMedicalCheck(', 1, true),
    "the vanilla helper queues patient movement and is not a read-only eligibility check")
assert(string.find(source, 'ISMedicalCheckAction:new(player, patient)', 1, true),
    "the real local player must be the doctor and the companion the patient")
assert(string.find(source, '"Medical Check"', 1, true),
    "companion context menu must expose medical treatment")

require = function() end
Events = { OnFillWorldObjectContextMenu = { Add = function() end } }
local blocked, reachable, sameCar = false, true, false
local square = { canReachTo = function() return not blocked end }
local function actor(x)
    return { x = x, dead = false, messages = {},
        getX = function(self) return self.x end, getY = function() return 0 end,
        getZ = function() return 0 end, getCurrentSquare = function(self) return self.square or square end,
        isDead = function(self) return self.dead end,
        Say = function(self, message) self.messages[#self.messages + 1] = message end }
end
local player, patient = actor(0), actor(3)
patient.square = {}
local currentPatient = patient
getSpecificPlayer = function(n) assert(n == 0); return player end
KnoxSurvivorRuntime = { getCharacter = function() return currentPatient end }
local holds, walks, completed, starts = 0, 0, 0, 0
KnoxCompanionService = { command = function(p, id, order)
    assert(p == player and id == "patient" and order == "hold")
    holds = holds + 1
    return true
end }
ISHealthPanel = {
    canPerformMedicalCheck = function() error("must not queue movement on patient") end,
    IsCharactersInSameCar = function() return sameCar end,
}
ISTimedActionQueue = { queues = {} }
ISTimedActionQueue.add = function(action)
    local queue = ISTimedActionQueue.queues[action.character] or { queue = {} }
    ISTimedActionQueue.queues[action.character] = queue
    queue.queue[#queue.queue + 1] = action
end
luautils = {
    walkAdjTest = function(p) assert(p == player); return reachable end,
    walkAdj = function(p) assert(p == player); walks = walks + 1; return reachable end,
}
ISMedicalCheckAction = {}
function ISMedicalCheckAction:new(doctor, other)
    assert(doctor == player and other == patient)
    return { character = doctor, otherPlayer = other,
        otherPlayerX = other:getX(), otherPlayerY = other:getY(),
        isValid = function(self)
            return sameCar or (self.otherPlayerX == other:getX() and self.otherPlayerY == other:getY())
        end,
        start = function() starts = starts + 1 end,
        stop = function() end,
        perform = function() completed = completed + 1 end,
    }
end
assert(loadfile(path))()
local menu = KnoxSurvivorContextMenu
assert(menu.medicalCheck(0, "patient") and holds == 1 and walks == 1,
    "doctor approaches patient using native walking, after companion Hold")
local action = ISTimedActionQueue.queues[player].queue[1]
assert(menu.medicalCheck(0, "patient") and #ISTimedActionQueue.queues[player].queue == 1,
    "repeated clicks do not duplicate the check or walking")
player.x, patient.x = 2, 3.1
assert(action:isValid(), "patient settling before doctor arrival does not invalidate the queued check")
action:start()
action:perform()
assert(starts == 1 and completed == 1, "native medical animation and panel completion remain in use")
blocked = true
assert(not action:isValid(), "wall-separated patient cannot be treated through an obstruction")
blocked = false
patient.x = 3.5
assert(not action:isValid(), "movement after check starts still interrupts through native validity")
assert(#player.messages > 0, "cancellation is visible rather than silently doing nothing")
currentPatient = actor(3.5)
assert(not action:isValid(), "reconstructed patient cannot inherit an old body's check")
currentPatient = patient
ISTimedActionQueue.queues[player] = nil
reachable = false
assert(not menu.medicalCheck(0, "patient") and holds == 1 and walks == 1,
    "unreachable patient fails before changing orders or queuing actions")
reachable, player.x = true, -10
assert(not menu.medicalCheck(0, "patient"), "distant patient produces feedback")
player.x = 2
patient.dead = true
assert(not menu.medicalCheck(0, "patient"), "dead patient is rejected")
patient.dead, sameCar = false, true
assert(menu.medicalCheck(0, "patient") and walks == 1,
    "same-car check does not queue a walk out of the vehicle")
print("Companion medical menu PASS native_action=true local_doctor=true deferred_position=true feedback=true")
