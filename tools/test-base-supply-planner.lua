local root = arg[1] or "."
local planner = dofile(root .. "/mod/42/media/lua/client/KS_BaseSupplyPlanner.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "assertion failed") .. " (expected " .. tostring(expected)
            .. ", got " .. tostring(actual) .. ")")
    end
end

local function item(fullType)
    return { getFullType = function() return fullType end }
end

local requirements = { items = {
    ["Base.Hammer"] = 1,
    ["Base.Plank"] = 2,
} }

assertEqual(planner.matchesRequirement(item("Base.Hammer"), requirements), true,
    "required item should match")
assertEqual(planner.matchesRequirement(item("Base.Nails"), requirements), false,
    "unlisted item should not match")
assertEqual(planner.matchesRequirement(item("Base.Hammer"), { items = { ["Base.Hammer"] = 0 } }), false,
    "zero-count requirement should not match")
assertEqual(planner.matchesRequirement(nil, requirements), false,
    "nil item should fail safely")
assertEqual(planner.matchesRequirement(item("Base.Hammer"), nil), false,
    "missing requirements should fail safely")

local inventoryCounts = { ["Base.Hammer"] = 1, ["Base.Plank"] = 1 }
local inventory = {
    getItemCount = function(_, fullType)
        return inventoryCounts[fullType] or 0
    end,
}
local missing = planner.missingRequirements(requirements, inventory)
assertEqual(missing["Base.Hammer"], nil,
    "already satisfied tools must not remain world-search targets")
assertEqual(missing["Base.Plank"], 1,
    "partially held materials must retain only their outstanding count")
assertEqual(planner.matchesMissingRequirement(item("Base.Hammer"), requirements, inventory), false,
    "world search must not fetch another satisfied tool")
assertEqual(planner.matchesMissingRequirement(item("Base.Plank"), requirements, inventory), true,
    "world search must accept the material the job still needs")
assertEqual(planner.matchesMissingRequirement(item("Base.Nails"), requirements, inventory), false,
    "world search must reject unrelated items")
local unsafeInventory = { getItemCount = function() error("unsupported inventory") end }
assertEqual(planner.matchesMissingRequirement(item("Base.Hammer"), requirements, unsafeInventory), true,
    "inventory inspection failures must fail safely as an outstanding requirement")

local types = planner.requirementTypes(requirements)
assertEqual(#types, 2, "positive requirement types should be returned")
assertEqual(types[1], "Base.Hammer", "requirement types should be sorted")
assertEqual(types[2], "Base.Plank", "requirement types should be sorted")

assertEqual(planner.chooseShortage({ food = 0, water = 20, medical = 2 }, 3), "find_food",
    "food shortage should be selected first")
assertEqual(planner.chooseShortage({ food = 8, water = 0, medical = 2 }, 3), "find_water",
    "water shortage should be selected after food is covered")
assertEqual(planner.chooseShortage({ food = 8, water = 8, medical = 0 }, 3), "find_medical",
    "medical shortage should be selected after food and water")
assertEqual(planner.chooseShortage({ food = 8, water = 8, medical = 2, weapons = 0 }, 3), "find_weapon",
    "weapon shortage should be selected before tools")
assertEqual(planner.chooseShortage({ food = 8, water = 8, medical = 2, weapons = 1, tools = 1 }, 3), nil,
    "healthy stores should not create a supply trip")
local reserves = planner.reserveStatus({
    food = 3, water = 6, medical = 1, weapons = 0, tools = 2,
}, 3)
assertEqual(reserves[1].kind, "find_food", "reserve order must match supply priority")
assertEqual(reserves[1].target, 6, "food reserve target must scale with residents")
assertEqual(reserves[1].missing, 3, "reserve projection must expose exact shortage")
assertEqual(reserves[2].missing, 0, "covered reserve must report no shortage")
assertEqual(reserves[4].category, "weapons", "weapon reserve must use storage category")
assertEqual(reserves[4].missing, 1, "missing weapon reserve must remain visible")
local shortages = planner.shortages({
    food = 0, water = 0, medical = 0, weapons = 1, tools = 1,
}, 3)
assertEqual(#shortages, 3, "all meaningful concurrent shortages should be exposed")
assertEqual(shortages[1], "find_food", "shortage order must remain deterministic")
assertEqual(shortages[2], "find_water", "water follows food in shortage priority")
assertEqual(shortages[3], "find_medical", "medical follows critical provisions")
assertEqual(planner.chooseAvailableShortage({
    food = 0, water = 0, medical = 0, weapons = 1, tools = 1,
}, 3, { find_food = { survivorId = "worker-a" } }, "worker-b"), "find_water",
    "a claimed food run must not prevent another resident covering water")
assertEqual(planner.chooseAvailableShortage({
    food = 0, water = 0, medical = 0, weapons = 1, tools = 1,
}, 3, { find_food = { survivorId = "worker-a" } }, "worker-a"), "find_food",
    "a resident must retain its own highest-priority shortage claim")
assertEqual(planner.chooseAvailableShortage({
    food = 0, water = 0, medical = 2, weapons = 1, tools = 1,
}, 3, { find_water = { survivorId = "worker-b" } }, "worker-b"), "find_water",
    "an in-flight lower-priority claim must survive a higher shortage becoming available")
assertEqual(planner.chooseAvailableShortage({
    food = 0, water = 0, medical = 2, weapons = 1, tools = 1,
}, 3, {
    find_food = { survivorId = "worker-a" },
    find_water = { survivorId = "worker-b" },
}, "worker-c"), nil, "fully claimed shortages must not duplicate workers")

local workers = {
    { id = "recent", ready = true, lastSupplyRunAtHours = 20 },
    { id = "old", ready = true, lastSupplyRunAtHours = 5 },
    { id = "busy", ready = true, hasTask = true, lastSupplyRunAtHours = 0 },
    { id = "resting", ready = true, resting = true, lastSupplyRunAtHours = 0 },
    { id = "ordered", ready = true, explicitOrder = true, lastSupplyRunAtHours = 0 },
}
assertEqual(planner.chooseWorker(workers, "find_food"), "old",
    "oldest eligible supply worker should receive the next automatic run")
assertEqual(planner.chooseWorker({
    { id = "repeat", ready = true, lastSupplyRunAtHours = 10,
        lastSupplyKind = "find_food" },
    { id = "different", ready = true, lastSupplyRunAtHours = 10,
        lastSupplyKind = "find_water" },
}, "find_food"), "different",
    "equal-age rotation should avoid repeating the same shortage kind")
assertEqual(planner.chooseWorker({
    { id = "b", ready = true },
    { id = "a", ready = true },
}, "find_food"), "a", "fresh workers should use a stable id tie-break")
assertEqual(planner.chooseWorker({
    { id = "busy", ready = true, hasTask = true },
    { id = "away", ready = false },
}, "find_food"), nil, "no eligible worker should produce no claim")

print("base supply planner tests passed")
