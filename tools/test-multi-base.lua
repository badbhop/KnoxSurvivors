local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

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
}
getGameTime = function()
    return { getWorldAgeHours = function() return 48 end }
end

package.loaded["KS_BaseTaskBoard"] = true
package.loaded["KS_BaseStorage"] = true
package.loaded["KS_BaseBarricades"] = true
package.loaded["KS_BaseFarming"] = true
package.loaded["KS_BaseWoodcutting"] = true
package.loaded["KS_BaseCorpseHandling"] = true
package.loaded["KS_BaseCooking"] = true
package.loaded["KS_BaseRepairs"] = true
package.loaded["KS_BaseNeeds"] = true
package.loaded["KS_BaseSupplyPlanner"] = true
package.loaded["KS_CompanionPatrol"] = true
package.loaded["KS_JobTestSupplies"] = true

require "KS_Persistence"

local function area(x, y)
    return { minX = x, minY = y, width = 4, height = 4 }
end

-- Single-home gate stays for ordinary creation.
local home = assert(KnoxPersistence.createBase("player", "player-1", area(10, 10), 48))
local again, reason = KnoxPersistence.createBase("player", "player-1", area(50, 50), 49)
assert(again ~= nil and again.id == home.id and reason == "existing",
    "ordinary creation keeps the single-home gate")

-- Outposts opt in explicitly and cannot overlap.
local outpost, outResult = KnoxPersistence.createBase("player", "player-1", area(100, 100), 50,
    { minX = 96, minY = 96, maxX = 107, maxY = 107, allFloors = true }, true)
assert(outpost ~= nil and outpost.id ~= home.id,
    "allowMultiple creates a second home: " .. tostring(outResult))
local overlap = KnoxPersistence.createBase("player", "player-1", area(11, 11), 51,
    { minX = 8, minY = 8, maxX = 15, maxY = 15, allFloors = true }, true)
assert(overlap == nil, "overlapping territory rejected even for outposts")

-- Deterministic oldest-first listing and primary.
local bases = KnoxPersistence.getBasesForOwner("player", "player-1")
assert(#bases == 2 and bases[1].id == home.id and bases[2].id == outpost.id,
    "bases list oldest first")
assert(KnoxPersistence.getBaseForOwner("player", "player-1").id == home.id,
    "singular getters resolve the primary home")

-- Residents stay per base; supply orders read back for UI rows.
assert(KnoxPersistence.setRecord("w-home", "record-w-home"))
assert(KnoxPersistence.setPlayerCompanion("w-home", "player-1", "follow", 51))
assert(KnoxPersistence.setPlayerBaseResident("w-home", "player-1", home.id, 51))
assert(KnoxPersistence.setRecord("w-out", "record-w-out"))
assert(KnoxPersistence.setPlayerCompanion("w-out", "player-1", "follow", 51))
assert(KnoxPersistence.setPlayerBaseResident("w-out", "player-1", outpost.id, 51))
local homeRes = KnoxPersistence.getBaseResidentIds(home.id)
local outRes = KnoxPersistence.getBaseResidentIds(outpost.id)
assert(#homeRes == 1 and homeRes[1] == "w-home", "home roster separate")
assert(#outRes == 1 and outRes[1] == "w-out", "outpost roster separate")
assert(KnoxPersistence.setBaseSupplyOrder("w-home", "player-1", home.id, "find_food", 52, 24),
    "supply order issues at home")
local order = KnoxPersistence.getBaseSupplyOrder("w-home")
assert(order ~= nil and order.kind == "find_food"
    and (tonumber(order.expiresAtHours) or 0) > 52, "supply order reads back with expiry")
order.kind = "find_water"
assert(KnoxPersistence.getBaseSupplyOrder("w-home").kind == "find_food",
    "supply read is a copy")
assert(KnoxPersistence.getBaseSupplyOrder("w-out") == nil, "no order reads nil")

print("Multi-base PASS gate=true overlap=true primary=true rosters=true supply_read=true")
