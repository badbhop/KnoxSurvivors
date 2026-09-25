local rootPath = arg[1] or "."

local modData = {}
ModData = {
    getOrCreate = function(key)
        modData[key] = modData[key] or {}
        return modData[key]
    end,
}
Events = {
    OnSave = { Add = function() end },
    OnPostSave = { Add = function() end },
    OnGameStart = { Add = function() end },
    OnTick = { Add = function() end, Remove = function() end },
}
getGameTime = function()
    return { getWorldAgeHours = function() return 48 end }
end
ZombRand = function()
    return 0
end

local persistencePath = rootPath
    .. "/mod/42/media/lua/client/KS_Persistence.lua"
assert(loadfile(persistencePath))()

modData["KnoxSurvivors_IsoPlayer"] = { survivors = {
    ["bed-companion"] = {
        id = "bed-companion",
        alive = true,
        affiliation = { kind = "player", ownerId = "owner1" },
        duty = { mode = "companion", order = "follow", revision = 0 },
        policies = {},
    },
    ["bed-resident"] = {
        id = "bed-resident",
        alive = true,
        affiliation = { kind = "player", ownerId = "owner1" },
        duty = { mode = "base", order = "work", baseId = "base1", revision = 0 },
        policies = {},
    },
} }

-- Bed assignment: owner only, validated coordinates, clearable.
local ok, reason = KnoxPersistence.setSurvivorBed("bed-companion", "owner1",
    { x = 10, y = 10, z = 0, objectIndex = 3 }, 48)
assert(ok, "owner assigns bed, got: " .. tostring(reason))
local policies = KnoxPersistence.getSurvivorPolicies("bed-companion")
assert(type(policies.assignedBed) == "table"
    and policies.assignedBed.x == 10
    and policies.assignedBed.objectIndex == 3, "bed record stored")
ok, reason = KnoxPersistence.setSurvivorBed("bed-companion", "stranger",
    { x = 1, y = 1, z = 0, objectIndex = 0 }, 48)
assert(not ok, "strangers cannot assign beds")
ok, reason = KnoxPersistence.setSurvivorBed("bed-companion", "owner1",
    { x = 0 / 0, y = 1, z = 0, objectIndex = 0 }, 48)
assert(not ok, "invalid coordinates rejected")
ok, reason = KnoxPersistence.setSurvivorBed("bed-resident", "owner1",
    { x = 4, y = 4, z = 0, objectIndex = 1 }, 48)
assert(ok, "base residents receive beds, got: " .. tostring(reason))
ok, reason = KnoxPersistence.clearSurvivorBed("bed-companion", "owner1", 48)
assert(ok, "assignment clears, got: " .. tostring(reason))
assert(KnoxPersistence.getSurvivorPolicies("bed-companion").assignedBed == nil,
    "cleared bed reads nil")
ok, reason = KnoxPersistence.clearSurvivorBed("bed-companion", "owner1", 48)
assert(not ok, "double clear reports no assignment")

-- Load-time schedule validation through the identity boundary.
local duty = KnoxPersistence.getSurvivorDuty("bed-companion")
duty.schedule = { { from = 8, to = 12, assignment = "nap" } }
duty = KnoxPersistence.getSurvivorDuty("bed-companion")
assert(duty.schedule == nil, "corrupt schedule falls back to nil on load")

-- New resident supply categories persist through the validated boundary.
for _, kind in ipairs({ "find_wood", "find_materials", "find_clothing", "find_ammo" }) do
    assert(KnoxPersistence.setBaseSupplyOrder("bed-resident", "owner1",
        "base1", kind, 48, 24), "supply order accepted: " .. kind)
    local check = KnoxPersistence.getSurvivorDuty("bed-resident")
    assert(check.baseSupplyOrder ~= nil and check.baseSupplyOrder.kind == kind,
        "supply order stored: " .. kind)
    KnoxPersistence.clearBaseSupplyOrder("bed-resident", "owner1", "base1", 48)
end
assert(not KnoxPersistence.setBaseSupplyOrder("bed-resident", "owner1",
    "base1", "find_dragon", 48, 24), "unknown supply kind rejected")

print("Assigned beds PASS assign=true ownership=true validation=true schedule=true supply_kinds=true")
