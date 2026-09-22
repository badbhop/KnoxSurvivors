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
-- Main Supplies retired: no new designations, but legacy capacity handling stays.
local retired, reason = KnoxToolCupboard.designate(base, object, 0, manager)
assert(retired == nil and reason == "main_supplies_retired", "main supplies retired")
assert(base.toolCupboardKey == nil, "no new main marker")
SandboxVars = { KnoxSurvivors = { ToolCupboardCapacity = 200 } }
-- Legacy cupboard capacity application still preserves real contents.
data.KnoxToolCupboard = { key = key, originalCapacity = 40 }
assert(KnoxToolCupboard.apply(object, container, key) and capacity == 100 and #items == 2,
    "capacity changes preserve real contents")
assert(not KnoxToolCupboard.apply(object, container, "wrong-key"), "no capacity change on replacement containers")
assert(KnoxToolCupboard.isDryContainerType("crate") and not KnoxToolCupboard.isDryContainerType("fridge"),
    "dry-type check retained for legacy validation")
print("Tool cupboard PASS retired=true real_inventory=true legacy_capacity=true")
