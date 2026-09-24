local root = arg[1] or "."
require = function() return true end
assert(loadfile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"))()
local C = KnoxAutonomyController
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local room, grid = {}, {}
local function square(x, y, inside)
    local s = {getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end, getRoom = function() return inside and room or nil end,
        canStand = function() return true end, isBlockedTo = function() return false end,
        isHoppableTo = function() return false end, getDoorTo = function() return nil end,
        getWindowTo = function() return nil end}
    grid[x .. ":" .. y] = s
    return s
end
for x = 0, 12 do for y = 0, 2 do square(x, y) end end
local inside1, inside2 = square(2, 1, true), square(4, 1, true)
room.getSquares = function() return list({inside1, inside2}) end
getCell = function() return {getGridSquare = function(_, x, y) return grid[x .. ":" .. y] end} end
local function window()
    local w = {open = false, smashed = false, barricaded = false}
    w.IsOpen = function() return w.open end
    w.isSmashed = function() return w.smashed end
    w.isLocked = function() return true end
    w.isPermaLocked = function() return true end
    w.isBarricaded = function() return w.barricaded end
    w.canClimbThrough = function() return w.open or w.smashed end
    return w
end
local first, second = window(), window()
inside1.getWindowTo = function(_, s) return s == grid['2:0'] and first or nil end
inside2.getWindowTo = function(_, s) return s == grid['4:0'] and second or nil end
-- A forceable locked door on this same edge must not make the NPC smash it
-- before trying the available window.
local lockedDoor = {
    IsOpen = function() return false end,
    isLocked = function() return true end,
    isLockedByKey = function() return false end,
    isBarricaded = function() return false end,
}
inside1.getDoorTo = function(_, s) return s == grid['2:0'] and lockedDoor or nil end
local origin, leaderSquare = grid['0:0'], grid['0:0']
local queued, busy, crossed, canceled = {}, false, 0, 0
ISSmashWindow = {new = function(_, actor, w) return {actor = actor, window = w} end}
ISTimedActionQueue = {add = function(a) queued[#queued + 1] = a; busy = true end}
local protected = false
KnoxBaseManager = {canDamageStructure = function() return not protected end}
KnoxSurvivorNeeds = {snapshot = function() return {endurance = 1} end}
local weapon = {IsWeapon = function() return true end,
    isBroken = function() return false end, isRanged = function() return false end}
local actor = {getCurrentSquare = function() return origin end,
    getPrimaryHandItem = function() return weapon end,
    getCharacterActions = function() return {isEmpty = function() return not busy end} end}
local leader = {getCurrentSquare = function() return leaderSquare end, isDead = function() return false end}
local c = setmetatable({id = 'entry-test', character = actor, activeDecision = 'find_food',
    pendingSupply = {container = {getSourceGrid = function() return inside1 end}, approach = inside1},
    bridge = {cancelNpcMove = function() canceled = canceled + 1 end,
        moveNpc = function() return 'MOVE_STARTED' end,
        crossNpc = function() crossed = crossed + 1; return 'CROSS_STARTED' end}}, C)
assert(c:beginWindowDetour(1, 'MOVING_TO_SUPPLY'))
assert(c.entryDetour.object == first and not c.entryDetour.force, 'try first closed window without smashing')
origin = c.entryDetour.outside
assert(c:retryWindowDetour(2, 'FAILED_LOCKED_OR_UNUSABLE_WINDOW'))
assert(c.entryDetour.object == second and not c.entryDetour.force, 'try another window before force')
origin = c.entryDetour.outside
assert(c:retryWindowDetour(3, 'FAILED_LOCKED_OR_UNUSABLE_WINDOW'))
assert(c.entryDetour.force and c.entryDetour.object == second
    and c.entryDetour.object ~= lockedDoor,
    'a forced window still outranks an equally forceable locked door')
assert(c:crossWindowDetour(4) and c.state == 'OPENING_ENTRY_WINDOW')
assert(#queued == 1 and crossed == 0, 'native action owns smash, not movement')
c:updateEntryWindow(5)
assert(crossed == 0, 'wait for real action completion')
second.smashed, busy = true, false
c:updateEntryWindow(6)
assert(crossed == 1 and c.state == 'CROSSING_WINDOW_ENTRY', 'only confirmed smash permits crossing')
assert(c:resumeAfterWindowDetour(7) and c.state == 'MOVING_TO_SUPPLY' and c.entryDetour == nil)
c.pendingSupply.entryAttemptCount = 8
assert(not c:beginWindowDetour(8, 'MOVING_TO_SUPPLY'), 'bounded search ends without recursive retry')
c.entryDetour = {force = true, object = first, inside = inside1}
protected = true
assert(not c:crossWindowDetour(9) and #queued == 1, 'protection rechecked before destructive action')
protected = false
c.pendingSupply.entryAttemptCount = 0
c.pendingSupply.entryAttempts = {[first] = 'closed', [second] = 'attempted'}
c.activeDecision = 'scavenge'
assert(c:beginWindowDetour(10, 'MOVING_TO_EXPLORE') and c.entryDetour.force,
    'armed scavenging can force a previously failed locked window')

-- An automatic need detour is not permission to abandon a leader or hold post.
origin = grid['0:0']
c.companionOrder, c.companionTarget = 'follow', leader
assert(c:allowNeedDetour(grid['3:0'], 50))
assert(not c:allowNeedDetour(grid['5:0'], 50), 'automatic supply range bounded to four tiles')
leaderSquare = grid['10:0']
assert(not c:allowNeedDetour(grid['3:0'], 50), 'leader departure invalidates detour')
leaderSquare = grid['0:0']
c.companionOrder = 'hold'
assert(not c:allowNeedDetour(grid['1:0'], 50), 'Hold never silently authorizes a supply trip')
c.companionOrder = 'follow'
grid['1:0'].isBlockedTo = function() return true end
assert(not c:allowNeedDetour(grid['3:0'], 50), 'nearby item behind blocked route is not convenient')
grid['1:0'].isBlockedTo = function() return false end
local threat = {getCurrentSquare = function() return grid['4:0'] end, isDead = function() return false end}
c.perceivedThreats = {[threat] = {lastSeen = 50}}
assert(not c:allowNeedDetour(grid['3:0'], 50), 'recent perceived danger blocks detour')
assert(c:allowNeedDetour(grid['3:0'], 500), 'expired perception does not block forever')
c.companionOrder, c.companionTarget = nil, nil
c.groupLeaderId, c.groupLeader = 'leader', leader
assert(not c:allowNeedDetour(grid['8:0'], 500), 'independent group follower also stays together')
c.groupLeader = nil
assert(not c:allowNeedDetour(grid['1:0'], 500), 'unloaded leader does not authorize wandering')
c.baseId = 'base'
assert(c:allowNeedDetour(grid['8:0'], 500), 'assigned base logistics are not follower excursions')
print('entry recovery and escorted needs tests passed')
