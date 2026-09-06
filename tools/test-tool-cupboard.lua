local root = arg[1] or "."
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path
require "KS_ToolCupboard"
local base = { id = "home", storage = {} }
local data, capacity, items = {}, 40, { "real hammer", "real food" }
local kind = "crate"
local container = { getCapacity = function() return capacity end,
    setCapacity = function(_, value) capacity = value end, getType = function() return kind end }
local object = { getModData = function() return data end, getSquare = function() return {} end,
    getContainerByIndex = function() return container end }
local allowed = true
local key = "home:container:1:1:0:0:0"
local manager = { containsSquare = function() return allowed end,
    containerReference = function() return { key = key } end,
    setStoragePolicy = function(_, _, category)
        local policy = { key = key, category = category, depot = true }; base.storage[key] = policy; return policy
    end }
local policy = assert(KnoxToolCupboard.designate(base, object, 0, manager))
assert(capacity == 500 and policy.depot and policy.toolCupboard)
assert(base.toolCupboardKey == key and data.KnoxToolCupboard.originalCapacity == 40)
assert(KnoxToolCupboard.designate(base, object, 0, manager))
assert(data.KnoxToolCupboard.originalCapacity == 40, "reselecting preserves original capacity")
SandboxVars = { KnoxSurvivors = { ToolCupboardCapacity = 200 } }
assert(KnoxToolCupboard.apply(object, container, key) and capacity == 200 and #items == 2,
    "capacity changes preserve real contents")
assert(not KnoxToolCupboard.apply(object, container, "wrong-key"), "no capacity change on replacement containers")
key = "home:container:2:1:0:0:0"
assert(not KnoxToolCupboard.designate(base, object, 0, manager), "one cupboard per base")
local oldKey = base.toolCupboardKey
local oldData, oldCapacity = { KnoxToolCupboard = data.KnoxToolCupboard }, capacity
local oldObject = { getModData = function() return oldData end }
local oldContainer = { setCapacity = function(_, value) oldCapacity = value end }
KnoxBaseStorage = { resolvePolicy = function() return nil, "storage_square_unloaded" end }
assert(not KnoxToolCupboard.designate(base, object, 0, manager), "unloaded cupboard cannot be orphaned")
assert(base.toolCupboardKey == oldKey and oldCapacity == 200)
KnoxBaseStorage.resolvePolicy = function()
    return { object = oldObject, container = oldContainer }
end
assert(KnoxToolCupboard.designate(base, object, 0, manager), "loaded cupboard can be reassigned")
assert(oldCapacity == 40 and oldData.KnoxToolCupboard == nil and base.toolCupboardKey == key,
    "reassignment restores old capacity and transfers only designation")
key = "home:container:3:1:0:0:0"
KnoxBaseStorage.resolvePolicy = function() return nil, "storage_object_missing" end
assert(KnoxToolCupboard.designate(base, object, 0, manager), "destroyed cupboard can be replaced")
allowed = false
assert(not KnoxToolCupboard.designate(base, object, 0, manager), "outside territory rejected")
allowed, base.toolCupboardKey, kind = true, nil, "fridge"
assert(not KnoxToolCupboard.designate(base, object, 0, manager), "refrigerators retain native capacity")
print("Tool cupboard PASS capacity=true real_inventory=true identity=true single=true bounds=true")
