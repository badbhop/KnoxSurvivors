local root = arg[1] or "."
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path
local saved = {}
ModData = { getOrCreate = function(key) saved[key] = saved[key] or {}; return saved[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 12 end } end
SandboxVars = { KnoxSurvivors = { SpawnWithSpouse = true } }
require "KS_SpouseStart"
local blocked = false
local function square(x, y)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end, canStand = function() return not blocked end,
        isSomethingTo = function() return false end }
end
getCell = function() return { getGridSquare = function(_, x, y) return square(x, y) end } end
local function player(hours)
    local data = {}
    return { getModData = function() return data end, getCurrentSquare = function() return square(10, 10) end,
        isDead = function() return false end, getHoursSurvived = function() return hours or 0 end }
end
local calls, ids = 0, {}
local function activate(id, tile, record)
    calls = calls + 1; ids[#ids + 1] = id
    assert(tile ~= nil or record ~= nil)
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
    return true
end
local first = player()
blocked = true
assert(not KnoxSpouseStart.update(first, activate) and calls == 0, "blocked start waits without allocating body")
local id = first:getModData().KnoxSurvivors.spouseStart.id
blocked = false
assert(KnoxSpouseStart.update(first, activate) and calls == 1)
assert(ids[1] == id and KnoxPersistence.getSurvivorDuty(id).mode == "companion")
local owner = KnoxPersistence.ensurePlayerId(first)
assert(KnoxPersistence.getPlayerRelationship(owner, id).trust == 90)
assert(not KnoxSpouseStart.update(first, activate) and calls == 1, "reload cannot duplicate spouse")
assert(not KnoxSpouseStart.update(player(2), activate) and calls == 1, "old characters are never retroactively assigned a spouse")
local second = player()
assert(KnoxSpouseStart.update(second, activate) and ids[2] ~= id, "local players have independent spouse identity")
local retry = player()
assert(not KnoxSpouseStart.update(retry, function(reservedId)
    KnoxPersistence.setRecord(reservedId, "partial-record"); return false
end))
assert(KnoxSpouseStart.update(retry, function(_, tile, record)
    assert(tile == nil and record == "partial-record", "partial successful capture restores instead of respawning")
    return true
end))
SandboxVars.KnoxSurvivors.SpawnWithSpouse = false
local disabled = player()
assert(not KnoxSpouseStart.update(disabled, activate))
SandboxVars.KnoxSurvivors.SpawnWithSpouse = true
assert(not KnoxSpouseStart.update(disabled, activate), "changing settings later does not create a second starting condition")
print("Spouse start PASS stable_identity=true reload=true blocked=true established_character=true partial_retry=true local_players=true")
