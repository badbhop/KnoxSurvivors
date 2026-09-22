local root = arg[1] or "."
require = function() return true end
ISTimedActionQueue = { add = function(action) action.queued = true return action end }
ISApplyBandage = {}
function ISApplyBandage:derive(name)
    local t = { Type = name }
    t.__index = t
    setmetatable(t, { __index = self })
    return t
end
function ISApplyBandage.new(self, doctor, patient, item, bodyPart, flag)
    assert(doctor ~= nil and patient ~= nil and item ~= nil and bodyPart ~= nil)
    return setmetatable({
        character = doctor, patient = patient, item = item,
        bodyPart = bodyPart, flag = flag,
    }, self)
end
function ISApplyBandage:start() end
function ISApplyBandage:complete() return true end
function ISApplyBandage:perform() end
function ISApplyBandage:stop() end
local medical = dofile(root .. "/mod/42/media/lua/client/KS_SurvivorMedicalActions.lua")

-- Bandage discovery only takes usable bandages, never random pocket litter.
local function item(canBandage, broken)
    return {
        isCanBandage = function() return canBandage end,
        isBroken = function() return broken == true end,
    }
end
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local doctor = { getInventory = function()
    return { getItems = function() return list({ item(false), item(true, true), item(true) }) end }
end }
local found = medical.findBandageItem(doctor)
assert(found ~= nil and found:isCanBandage() and not found:isBroken(),
    "aid must pick the usable bandage, skipping litter and broken stock")
assert(medical.findBandageItem({}) == nil)

-- Doctor and patient stay distinct through the native constructor shape.
local part = {}
local queued, reason = medical.queueAidBandage(doctor, { id = "patient" }, found, part)
assert(queued ~= nil and queued.queued == true, "aid action must queue, got " .. tostring(reason))
assert(queued.character == doctor and queued.patient.id == "patient",
    "native action must keep doctor and patient distinct")

-- Self-treatment still routes through the proven self path.
local selfAction = medical.queueAidBandage(doctor, doctor, found, part)
assert(selfAction ~= nil, "self aid must keep working")

print("Battlefield aid PASS bandage=true distinct=true self=true")

-- Controller behavior: an idle medic with bandages moves to a bleeding ally,
-- queues the native aid, and verifies the bleed stopped.
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController
local function tile(x, y)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return 0 end }
end
local function bodyPart(bleeding, bandaged)
    return { bleeding = function() return bleeding end, bandaged = function() return bandaged end,
        HasInjury = function() return true end }
end
local allySquare = tile(3, 0, 0)
local ally = {
    getCurrentSquare = function() return allySquare end,
    isDead = function() return false end,
    getBodyDamage = function()
        return { getBodyParts = function()
            return list({ bodyPart(true, false) })
        end }
    end,
}
local medicSquare = tile(0, 0, 0)
local medic = {
    getCurrentSquare = function() return medicSquare end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
    getInventory = function()
        return { getItems = function() return list({ item(true) }) end }
    end,
}
KnoxPersistence = {
    getBaseResidentIds = function() return { "medic", "ally" } end,
    getSurvivorAffiliation = function() return { factionId = "faction-1" } end,
    areSurvivorsHostile = function() return false end,
}
KnoxSurvivorRuntime = {
    getCharacter = function(id) return id == "ally" and ally or nil end,
    activeIds = function() return { "medic", "ally" } end,
}
AdjacentFreeTileFinder = { Find = function() return tile(2, 0, 0) end }
ISTimedActionQueue = { queues = {}, add = function(a) return a end }
KnoxActivityFeed = { speak = function() end, event = function() end }
local c = setmetatable({
    id = "medic",
    character = medic,
    state = "IDLE",
    nextThink = 0,
    nextThreatScan = 100000,
    baseId = "base-1",
    base = {},
    nextAidAt = 0,
    groupMembers = {},
    bridge = { moveNpc = function() return "MOVE_STARTED" end, cancelNpcMove = function() end,
        tickNpc = function() return "Succeeded" end },
    finishDecision = function(self) self.state = "IDLE" end,
}, Controller)
assert(c:beginBattlefieldAid(100) == true)
assert(c.state == "AID_MOVE", "medic must walk to a distant bleeder, got " .. tostring(c.state))
-- Arrival next to the patient queues the native bandage action.
c.state = "AID_MOVE"
c.pendingAidPatient = ally
c:tick(101)
assert(c.state == "AID_ACTION", "arrival must queue aid, got " .. tostring(c.state))
-- Verified bleed stop completes the aid.
c.pendingAidPart = bodyPart(true, true)
c:tick(102)
assert(c.state == "IDLE" and (c.nextAidAt or 0) > 102, "verified aid must complete with cooldown")

print("Battlefield aid behavior PASS move=true queue=true verify=true")

-- Same-faction camp mates are found through proximity even without a shared
-- base roster; the hostile and the far away are not patients.
KnoxPersistence.getBaseResidentIds = function() return { "medic" } end
local farAlly = {
    getCurrentSquare = function() return tile(100, 100, 0) end,
    isDead = function() return false end,
    getBodyDamage = function()
        return { getBodyParts = function() return list({ bodyPart(true, false) }) end }
    end,
}
KnoxSurvivorRuntime.getCharacter = function(id)
    if id == "ally" then return ally end
    if id == "far" then return farAlly end
    return nil
end
KnoxSurvivorRuntime.activeIds = function() return { "medic", "ally", "far" } end
local scout = setmetatable({
    id = "medic",
    character = medic,
    state = "IDLE",
    nextThink = 0,
    nextThreatScan = 100000,
    baseId = nil,
    base = nil,
    campId = "camp-1",
    camp = {},
    nextAidAt = 0,
    groupMembers = {},
    bridge = { moveNpc = function() return "MOVE_STARTED" end, cancelNpcMove = function() end,
        tickNpc = function() return "Succeeded" end },
    finishDecision = function(self) self.state = "IDLE" end,
}, Controller)
local found = scout:findAidPatient(200)
assert(found ~= nil and found.patient == ally, "nearby same-faction bleeder must be found")
KnoxPersistence.areSurvivorsHostile = function() return true end
assert(scout:findAidPatient(201) == nil, "hostile survivors are never patients")
KnoxPersistence.areSurvivorsHostile = function() return false end
KnoxPersistence.getSurvivorAffiliation = function(id)
    return id == "ally" and { factionId = "faction-9" } or { factionId = "faction-1" }
end
assert(scout:findAidPatient(202) == nil, "other-faction survivors are never patients")

print("Battlefield aid factions PASS campmate=true hostile=false foreign=false")

-- Owned companions and player-base residents may treat their actual owner,
-- controlled by the dedicated sandbox option.
local player = ally
KnoxPersistence.ensurePlayerId = function(candidate)
    return candidate == player and "player-1" or nil
end
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function() return player end
KnoxSettings = { allowSurvivorsTreatPlayer = function() return true end }
KnoxSurvivorRuntime.activeIds = function() return { "medic" } end
KnoxSurvivorRuntime.getCharacter = function() return nil end
local ownedMedic = setmetatable({
    id = "medic", character = medic, companionOwnerId = "player-1",
    nextAidAt = 0, groupMembers = {},
}, Controller)
found = ownedMedic:findAidPatient(203)
assert(found ~= nil and found.patient == player,
    "owned survivor must find its nearby bleeding player")
KnoxSettings.allowSurvivorsTreatPlayer = function() return false end
assert(ownedMedic:findAidPatient(204) == nil,
    "player treatment sandbox option must suppress player aid")

print("Battlefield aid player PASS enabled=true disabled=true")
