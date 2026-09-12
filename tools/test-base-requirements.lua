local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_SurvivorCapabilities"] = true
package.loaded["KS_SurvivorRuntime"] = true
package.loaded["KS_BaseStorage"] = true

Events = {
    OnGameStart = { Add = function() end },
}

local square = { x = 10, y = 20, z = 0 }
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end

local counts = {
    ["Base.Hammer"] = 1,
    ["Base.Plank"] = 1,
    ["Base.Nails"] = 1,
}
local inventory = {}
function inventory:getItemCount(fullType, recursive)
    assert(recursive == true)
    return counts[fullType] or 0
end
local character = {}
function character:getCurrentSquare() return square end
function character:getInventory() return inventory end

local base = {
    id = "base-1",
    territory = { minX = 5, minY = 15, maxX = 15, maxY = 25, allFloors = true },
}
KnoxPersistence = {
    getBase = function(id) return id == base.id and base or nil end,
    getSurvivorDuty = function(id)
        return id == "worker" and { mode = "base", baseId = base.id } or nil
    end,
    getSurvivorCapabilities = function(id)
        return id == "worker" and { traits = {}, skills = {} } or nil
    end,
    getBases = function() return { [base.id] = base } end,
    getFactions = function() return {} end,
}
KnoxSurvivorCapabilities = {
    skillLevel = function() return 0 end,
    hasTrait = function() return false end,
}
KnoxSurvivorRuntime = {
    getCharacter = function(id) return id == "worker" and character or nil end,
    activeIds = function() return {} end,
}
KnoxBaseStorage = {
    requirementsAvailable = function(_, worker, requirements)
        for fullType, required in pairs(requirements.items or {}) do
            if worker:getInventory():getItemCount(fullType, true) < required then
                return false, "item=" .. fullType
            end
        end
        return true, "available"
    end,
}

local manager = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseManager.lua")
local task = {
    requirements = {
        items = {
            ["Base.Hammer"] = 1,
            ["Base.Plank"] = 1,
            ["Base.Nails"] = 2,
        },
    },
}
local eligible, reason = manager.canPerformTask("worker", base.id, task)
assert(not eligible and reason == "item=Base.Nails",
    "worker without enough materials must not claim the task")

counts["Base.Nails"] = 2
eligible, reason = manager.canPerformTask("worker", base.id, task)
assert(eligible and reason == "eligible",
    "worker carrying the required materials should be eligible")

print("Base requirements PASS inventory_gate=true recursive=true")

-- The production area predicate must agree with the production eligibility
-- boundary, otherwise every completed outdoor job sends the worker home.
local nativeRequire=require
require=function() return true end
dofile(rootPath.."/mod/42/media/lua/client/KS_BaseJobs.lua")
require=nativeRequire
base.zones={forest={x1=30,x2=35,y1=20,y2=25,z=0,enabled=true}}
square.x,square.y=32,22
assert(manager.canPerformTask("worker",base.id,task),"continue work in an assigned external area")
counts["Base.Nails"]=1
local ok,why=manager.canPerformTask("worker",base.id,task)
assert(not ok and why=="item=Base.Nails","external work does not bypass real supplies")
counts["Base.Nails"]=2
square.z=1;assert(not manager.canPerformTask("worker",base.id,task),"work areas do not cover other floors")
square.z=0;base.zones.forest.enabled=false
assert(not manager.canPerformTask("worker",base.id,task),"released areas no longer authorize continued work")
base.zones.forest.enabled=true;square.x=40
assert(not manager.canPerformTask("worker",base.id,task),"outside a work area still requires a home return")
print("External job eligibility PASS real_area=true supplies=true floors=true released_area=true")
