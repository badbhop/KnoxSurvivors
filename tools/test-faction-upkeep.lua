local root = arg[1] or "."
require = function() return true end
Events = { OnGameStart = { Add = function() end } }
dofile(root .. "/mod/42/media/lua/client/KS_BaseManager.lua")
local Manager = KnoxBaseManager

local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local function containerOf(kind)
    return { getType = function() return kind end }
end
local function squareAt(x, y, z)
    local square = {}
    square.getX = function() return x end
    square.getY = function() return y end
    square.getZ = function() return z end
    square.objects = {}
    square.getObjects = function() return list(square.objects) end
    square.canStand = function() return true end
    square.getRoom = function() return {} end
    return square
end
local modData = {}
local function worldObject(kind, square, index)
    local data = {}
    return {
        getContainerCount = function() return 1 end,
        getContainerByIndex = function() return containerOf(kind) end,
        getSquare = function() return square end,
        getObjectIndex = function() return index end,
        getModData = function() return data end,
    }
end

-- Faction home: a crate, a cupboard, and a fridge. Everything else unloaded.
local squares = {}
do
    local crateSquare = squareAt(10, 10, 0)
    local cupSquare = squareAt(11, 10, 0)
    local fridgeSquare = squareAt(12, 10, 0)
    crateSquare.objects = { worldObject("crate", crateSquare, 5) }
    cupSquare.objects = { worldObject("cupboard", cupSquare, 6) }
    fridgeSquare.objects = { worldObject("fridge", fridgeSquare, 7) }
    squares["10,10,0"] = crateSquare
    squares["11,10,0"] = cupSquare
    squares["12,10,0"] = fridgeSquare
end
getCell = function()
    return { getGridSquare = function(_, x, y, z) return squares[x .. "," .. y .. "," .. z] end }
end

local base = {
    id = "faction-base-1",
    ownerKind = "faction",
    ownerId = "faction-1",
    territory = { minX = 10, minY = 10, maxX = 12, maxY = 10, z = 0 },
    zones = {},
    storage = {},
}
KnoxPersistence = {
    getBase = function() return base end,
    getBaseResidentIds = function() return {} end,
    addBaseZone = function() return {}, "added" end,
    setBaseStoragePolicy = function(baseId, reference, category)
        local policy = { key = reference.key, storageRole = category }
        base.storage[reference.key] = policy
        return policy, "assigned"
    end,
}
KnoxSettings = { autoGenerateBaseWorkAreas = function() return true end }
KnoxBaseStorage = { policies = function(b) local out = {} for _, p in pairs(b.storage or {}) do out[#out + 1] = p end return out end }
getGameTime = function() return { getWorldAgeHours = function() return 5 end } end

local faction = {
    kind = "npc",
    id = "faction-1",
    name = "Remnants",
    homeBase = { minX = 10, minY = 10, maxX = 12, maxY = 10, z = 0 },
    homeBaseId = nil,
    memberIds = {},
}
-- createBase path is persistence-owned; emulate a fresh faction record.
KnoxPersistence.createBase = function()
    faction.homeBaseId = base.id
    return base, "created"
end

local ensured, result = Manager.ensureFactionBase(faction)
assert(ensured ~= nil and result == "created", "faction base must be created, got " .. tostring(result))
local roles = {}
for _, policy in pairs(base.storage) do roles[policy.storageRole] = (roles[policy.storageRole] or 0) + 1 end
assert(roles.food == 1, "fridge must serve food storage")
assert(roles.tools == 1, "cupboard must serve tool storage")
assert(roles.building == 1, "crate must serve building storage")

-- Second pass must not duplicate or steal designations.
local count = 0
for _ in pairs(base.storage) do count = count + 1 end
Manager.ensureFactionBase(faction)
local recount = 0
for _ in pairs(base.storage) do recount = recount + 1 end
assert(recount == count, "faction storage designation must be idempotent")

print("Faction upkeep PASS storage_roles=true idempotent=true")

KnoxPersistence.getBaseResidentIds = function() return {"a","b","c","d","e","f"} end
KnoxPersistence.addBaseZone = function(_, kind, bounds, label)
    local zone = {type=kind, label=label, enabled=true}
    base.zones[label]=zone
    return zone, "added"
end
Manager.ensureFactionBase(faction)
local function zoneCount(kind)
    local count=0
    for _,zone in pairs(base.zones) do if zone.type==kind then count=count+1 end end
    return count
end
assert(zoneCount("guard")==2 and zoneCount("patrol")==2, "large bases receive secondary security areas")
Manager.ensureFactionBase(faction)
assert(zoneCount("guard")==2 and zoneCount("patrol")==2, "secondary areas must not duplicate")

base.storage={}
KnoxToolCupboard={isDryContainerType=function(kind) return kind~="fridge" end}
squares["12,10,0"].objects={worldObject("shelves",squares["12,10,0"],7)}
Manager.ensureFactionBase(faction)
local hasFood=false
for _,policy in pairs(base.storage) do if policy.storageRole=="food" then hasFood=true end end
assert(hasFood, "a dry pantry replaces missing refrigerator storage")
