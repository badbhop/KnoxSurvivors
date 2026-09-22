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
    return { getWorldAgeHours = function() return 30 end }
end

require "KS_Persistence"

for _, id in ipairs({ "worker-a", "worker-b" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
    assert(KnoxPersistence.setPlayerCompanion(id, "player-1", "follow", 30))
end

local base = assert(KnoxPersistence.createBase("player", "player-1", {
    minX = 10, minY = 10, width = 4, height = 4,
}, 30))
for _, id in ipairs({ "worker-a", "worker-b" }) do
    assert(KnoxPersistence.setPlayerBaseResident(id, "player-1", base.id, 30))
end

local original = {
    id = "barricade:original", x = 10, y = 10, z = 0, objectIndex = 1,
}
local occupied = {
    id = "barricade:occupied", x = 11, y = 10, z = 0, objectIndex = 2,
}
local replacement = {
    id = "barricade:replacement", x = 12, y = 10, z = 0, objectIndex = 3,
}
local first = assert(KnoxPersistence.queueBaseTask(
    base.id, "barricade", original, { hammer = 1, plank = 1, nails = 2 }, 60
))
local originalSignature = first.signature
local second = assert(KnoxPersistence.queueBaseTask(
    base.id, "barricade", occupied, { hammer = 1, plank = 1, nails = 2 }, 60
))
assert(KnoxPersistence.claimBaseTask(base.id, first.id, "worker-a", 30))

local denied, deniedReason = KnoxPersistence.retargetClaimedBaseTask(
    base.id, first.id, "worker-a", occupied
)
assert(denied == nil and deniedReason == "target_already_owned",
    "a claimed barricade task must not retarget onto queued work")

local retargeted, retargetReason = KnoxPersistence.retargetClaimedBaseTask(
    base.id, first.id, "worker-a", replacement
)
assert(retargeted == first and retargetReason == "retargeted"
    and first.target.id == replacement.id,
    "a worker-owned barricade task should retain its durable replacement target")
assert(first.signature ~= second.signature and first.signature ~= originalSignature,
    "retargeting must update the persistent duplicate-prevention signature")

local foreign, foreignReason = KnoxPersistence.retargetClaimedBaseTask(
    base.id, first.id, "worker-b", original
)
assert(foreign == nil and foreignReason == "not_claimed_by_survivor",
    "only the current claimant may change a barricade task target")

print("Barricade task ownership PASS atomic_retarget=true duplicate_target=true")
