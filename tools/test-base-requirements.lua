local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_SurvivorCapabilities"] = true
package.loaded["KS_SurvivorRuntime"] = true

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
