local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["TimedActions/ISGrabCorpseAction"] = true
package.loaded["TimedActions/ISDropCorpseAction"] = true
package.loaded["TimedActions/ISUnequipAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true

local queued = {}
ISGrabCorpseAction = {
    new = function(_, character, body)
        return { kind = "grab", character = character, body = body }
    end,
}
ISDropCorpseAction = {
    new = function(_, character, square)
        return { kind = "drop", character = character, square = square }
    end,
}
ISUnequipAction = {
    new = function(_, character, item)
        return { kind = "unequip", character = character, item = item }
    end,
}
ISTimedActionQueue = {
    add = function(action) queued[#queued + 1] = action end,
}

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local squares = {}
local function square(x, y, z)
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    if squares[key] == nil then
        local value = { x = x, y = y, z = z, bodies = {} }
        function value:getX() return self.x end
        function value:getY() return self.y end
        function value:getZ() return self.z end
        function value:canStand() return true end
        function value:getStaticMovingObjects() return list(self.bodies) end
        squares[key] = value
    end
    return squares[key]
end

local bodySquare = square(10, 10, 0)
local approach = square(9, 10, 0)
local corpseItem = { id = 7001 }
function corpseItem:getID() return self.id end
local body = { _class = "IsoDeadBody", index = 3, animal = false }
function body:getStaticMovingObjectIndex() return self.index end
function body:isAnimal() return self.animal end
function body:getSquare() return bodySquare end
function body:getItem() return corpseItem end
bodySquare.bodies = { body }

local animalBody = { _class = "IsoDeadBody", index = 4, animal = true }
function animalBody:getStaticMovingObjectIndex() return self.index end
function animalBody:isAnimal() return self.animal end
bodySquare.bodies[#bodySquare.bodies + 1] = animalBody

instanceof = function(object, className)
    return object ~= nil and object._class == className
end
AdjacentFreeTileFinder = {
    Find = function(targetSquare)
        return targetSquare == bodySquare and approach or nil
    end,
}
getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return square(x, y, z) end,
    }
end

local primary = { name = "Base.Axe" }
local secondary = { name = "Base.Torch" }
local character = {
    dragging = false,
    grappling = false,
    pickupRequests = 0,
    dropRequests = 0,
}
function character:getCurrentSquare() return approach end
function character:getPrimaryHandItem() return primary end
function character:getSecondaryHandItem() return secondary end
function character:isDraggingCorpse() return self.dragging end
function character:isGrappling() return self.grappling end
function character:isPerformingAnyGrappleAnimation() return self.grappling end
function character:pickUpCorpse(targetBody, style)
    assert(targetBody == body and style == "BwdDrag")
    self.pickupRequests = self.pickupRequests + 1
    self.grappling = true
end
function character:setDoGrappleLetGo()
    self.dropRequests = self.dropRequests + 1
    self.grappling = true
end

local base = {
    id = "base-corpses",
    zones = {
        cleanup = {
            id = "cleanup",
            type = "corpse",
            x1 = 12, y1 = 12, x2 = 14, y2 = 14, z = 0,
            enabled = true,
        },
    },
    territory = { minX = 10, minY = 10, maxX = 14, maxY = 14 },
}

local handling = dofile(
    rootPath .. "/mod/42/media/lua/client/KS_BaseCorpseHandling.lua"
)
local target, result = handling.findTask(base, character)
assert(target ~= nil and result == "found", "human corpse should create work")
assert(target.action == "haul_corpse" and target.corpseIndex == 3)
assert(target.corpseItemId == "7001" and target.approach == nil,
    "persistent target should retain only stable corpse identity")
assert(target.dropX == 13 and target.dropY == 13, "zone center should be drop target")

body.index = 8
local resolved, resolvedResult = handling.resolveTarget(base, target, character)
assert(resolved ~= nil and resolvedResult == "resolved")
assert(resolved.body == body and resolved.approach == approach,
    "stable item identity should survive a shifted static-object index")

local grab, grabResult = handling.queueGrab(character, resolved)
assert(grab ~= nil and grabResult == "queued")
assert(#queued == 3 and queued[1].kind == "unequip"
    and queued[2].kind == "unequip" and queued[3] == grab,
    "held items should be unequipped before the vanilla grab action")

local step, transition, deadline = handling.nextGrabStep(character, false, nil, 100)
assert(step == "wait" and transition == "idle" and deadline == 130,
    "queue completion allows the asynchronous native grapple to settle")
step, transition, deadline = handling.nextGrabStep(character, false, deadline, 130)
assert(step == "retry" and transition == "idle" and deadline == 220,
    "an idle handoff requests at most one bounded native retry")
local requested, retryResult = handling.requestGrabRetry(character, resolved)
assert(requested and retryResult == "native_retry_requested"
        and character.pickupRequests == 1 and character.grappling,
    "fallback invokes the real Build 42 corpse pickup without synchronous failure")
step, transition, deadline = handling.nextGrabStep(character, true, deadline, 160)
assert(step == "wait" and transition == "transitioning",
    "an active grapple handshake is not cancelled before attachment")
character.grappling = false
character.dragging = true
step, transition = handling.nextGrabStep(character, true, deadline, 170)
assert(step == "ready" and transition == "dragging",
    "native dragging state releases the pickup phase into movement")

local drop, dropResult = handling.queueDrop(character, resolved)
assert(drop ~= nil and dropResult == "queued" and queued[#queued] == drop)
assert(handling.isDragging(character), "dragging state should be observable")
step, transition, deadline = handling.nextDropStep(character, false, nil, 300)
assert(step == "wait" and transition == "dragging" and deadline == 390,
    "drop completion allows the native grapple release to settle")
step, transition, deadline = handling.nextDropStep(character, false, deadline, 390)
assert(step == "retry" and deadline == 480,
    "an attached corpse receives one bounded native release retry")
requested, retryResult = handling.requestDropRetry(character)
assert(requested and retryResult == "native_release_requested"
        and character.dropRequests == 1,
    "drop fallback reuses the native grapple let-go request")
character.dragging = false
character.grappling = false
step, transition = handling.nextDropStep(character, true, deadline, 410)
assert(step == "ready" and transition == "released",
    "native grapple release completes the corpse job")

body.index = -1
bodySquare.bodies = { animalBody }
local missing = handling.resolveTarget(base, target, character)
assert(missing == nil, "moved corpse must not resolve by stale coordinates")

print("Base corpse handling PASS discovery=true animal_filter=true identity=true async_grab_drop=true")
