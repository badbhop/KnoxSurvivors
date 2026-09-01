local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = { schemaVersion = 13 }
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
require "KS_Persistence"
require "KS_KnoxEvents"
local P, E = KnoxPersistence, KnoxEvents
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = clone(v) end
    return result
end
local ids = { "a", "b", "c", "d", "e" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, "native-record-" .. id))
    assert(P.ensureSurvivorIdentity(id, id, "Tester", 10))
end
local group = assert(P.createTravelGroup(ids, 10))
for _, id in ipairs({ "b", "c", "d", "e" }) do
    P.recordEncounter("a", id, { worldAgeHours = 10, began = true, sharedRoam = 1 })
end
local faction = assert(P.evaluateTravelGroupFaction(group.id, 10))
local playerFaction = assert(P.ensurePlayerFaction("player-1", 10))
local home = assert(P.createBase("faction", faction.id,
    { minX = 100, minY = 100, width = 10, height = 10 }, 10))
local target = assert(P.createBase("player", "player-1",
    { minX = 200, minY = 200, width = 10, height = 10 }, 10))
for _, id in ipairs(ids) do assert(P.setFactionBaseResident(id, faction.id, home.id, 10)) end
assert(data.schemaVersion == 15 and P.getRecord("a") == "native-record-a", "additive migration preserves native inventory records")
assert(E.proposeRaid(faction.id, target.id, 10) == nil, "neutral factions cannot schedule a raid")
assert(P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", 10, "test"))
local proposal = assert(E.proposeRaid(faction.id, target.id, 10))
assert(#proposal.memberIds == 2 and proposal.defendersAtProposal == 3,
    "five persistent residents can send two and keep three home")
local baseline = clone(data)
home.tasks.busy = { state = "claimed", claimedBy = "a" }
local busy = assert(E.proposeRaid(faction.id, target.id, 10))
assert(busy.memberIds[1] == "b", "in-progress base work is not stolen by a proposal")
home.tasks = {}
local duties = {}
for _, id in ipairs(ids) do duties[id] = P.getSurvivorDuty(id) end
local event = assert(E.scheduleRaid(faction.id, target.id, 10, 1))
assert(event.phase == "scheduled" and event.memberIds[1] == "a" and E.memberEvent("a").id == event.id)
assert(E.scheduleRaid(faction.id, target.id, 10, 1) == nil, "same faction cannot commit another simultaneous party")
event.memberIds[1] = "made-up"
assert(E.get(event.id).memberIds[1] == "a", "callers receive a defensive event snapshot")
for _, id in ipairs(ids) do
    assert(P.getRecord(id) == "native-record-" .. id, "scheduling never manufactures equipment or copies native inventory")
    assert(P.getSurvivorDuty(id).revision == duties[id].revision, "scheduling never overwrites companion/base intent")
end
assert(#P.getSurvivorIds() == 5, "raid planning does not allocate replacement NPCs")
assert(E.transition(event.id, 1, "spawning", 10.5) == nil, "not due yet")
assert(E.transition(event.id, 0, "spawning", 11) == nil, "stale callback cannot advance state")
event = assert(E.transition(event.id, 1, "spawning", 11))
assert(E.transition(event.id, 1, "spawning", 11).revision == 2, "repeated same-phase callback is idempotent")
assert(E.transition(event.id, 2, "objective", 11) == nil, "no skipping arrival/active phases")
data = clone(data)
_G.KnoxEvents, package.loaded.KS_KnoxEvents = nil, nil
E = require "KS_KnoxEvents"
assert(E.get(event.id).phase == "spawning" and E.memberEvent("a").id == event.id,
    "event identity, phase and roster survive a new module over serialized state")
for _, phase in ipairs({ "approaching", "active", "objective", "withdrawing", "completed" }) do
    event = assert(E.transition(event.id, event.revision, phase, 12, phase))
end
assert(E.memberEvent("a") == nil, "terminal event releases its member reservation")
assert(E.transition(event.id, event.revision, "scheduled", 13) == nil, "finished event cannot resurrect itself")
assert(E.proposeRaid(faction.id, target.id, 13) == nil, "cooldown prevents repeated faction raids")
event = assert(E.scheduleRaid(faction.id, target.id, 40, 0))
assert(P.markSurvivorDead("a", 40.1, "test"))
assert(E.maintain(40.2) > 0)
assert(E.get(event.id).phase == "failed" and E.memberEvent("b") == nil,
    "scheduled party loss cancels once without replacing the dead survivor")
assert(not P.isSurvivorAlive("a") and #P.getSurvivorIds() == 5,
    "event recovery retains the durable dead identity without resurrecting or replacing it")
event = assert(E.scheduleRaid(faction.id, target.id, 70, 0))
P.getBase(target.id).relocatedAtHours = 70.1
E.maintain(70.2)
assert(E.get(event.id).reason == "base_changed", "relocation invalidates old raid coordinates")
event = assert(E.scheduleRaid(faction.id, target.id, 100, 0))
event = assert(E.transition(event.id, event.revision, "spawning", 100))
assert(P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "neutral", 101, "peace"))
E.maintain(101)
assert(E.get(event.id).phase == "withdrawing", "peace withdraws a deployed event, not erase its roster")
assert(E.memberEvent("b") ~= nil, "withdrawal stays reserved until an actual return/cleanup result")
assert(E.maintain(200, 1) == 1, "maintenance work is bounded")
assert(E.get(event.id).phase == "withdrawing", "deadline cannot fabricate a completed return")
event = E.get(event.id)
assert(E.transition(event.id, event.revision, "completed", 201, "returned_home") ~= nil,
    "actual return callback can complete withdrawal after hostility ends")
assert(E.maintain(0/0) == 0 and E.scheduleRaid(faction.id, target.id, math.huge) == nil,
    "invalid clocks cannot poison persisted scheduling")
local function reset()
    data = clone(baseline)
    _G.KnoxEvents, package.loaded.KS_KnoxEvents = nil, nil
    E = require "KS_KnoxEvents"
end

reset()
event = assert(E.scheduleRaid(faction.id, target.id, 10, 0))
assert(P.markSurvivorDead("c", 10.1, "defender_lost"))
E.maintain(10.2)
assert(E.get(event.id).reason == "insufficient_home_strength",
    "loss of a non-raider rechecks minority commitment, not just two remaining defenders")
assert(P.isSurvivorAlive("a") and P.isSurvivorAlive("b"), "cancelled raid never kills its planned members")

reset()
event = assert(E.scheduleRaid(faction.id, target.id, 10, 0))
P.getBase(home.id).tasks.newWork = { state = "claimed", claimedBy = "a" }
E.maintain(10.1)
local cancelled = E.get(event.id)
assert(cancelled.phase == "failed" and cancelled.reason == "member_unavailable")
E.maintain(10.2)
assert(E.get(event.id).revision == cancelled.revision, "cancellation is not repeated every maintenance tick")
assert(P.getBase(home.id).tasks.newWork.claimedBy == "a", "event cancellation preserves actual job ownership")

reset()
event = assert(E.scheduleRaid(faction.id, target.id, 10, 0))
event = assert(E.transition(event.id, event.revision, "spawning", 10))
assert(P.markSurvivorDead("a", 10.1, "raider_lost"))
E.maintain(10.2)
assert(E.get(event.id).phase == "withdrawing" and E.memberEvent("b").id == event.id,
    "a deployed casualty retains the surviving member for real return cleanup")
assert(P.getSurvivorAffiliation("b").factionId == faction.id and P.getSurvivorDuty("b").baseId == home.id,
    "event loss does not rewrite faction or home identity")

reset()
event = assert(E.scheduleRaid(faction.id, target.id, 10, 0))
event = assert(E.transition(event.id, event.revision, "spawning", 10))
P.getKnoxEventState().records[event.id].revision = "damaged"
E.maintain(11)
assert(E.get(event.id).phase == "withdrawing" and E.memberEvent("b").id == event.id,
    "malformed deployed state retains its real party, not silently mark completed or erase members")
E.maintain(12)
assert(E.get(event.id).revision == 1, "malformed withdrawal does not thrash revisions")
local invalid = E.get(event.id)
invalid.memberIds = { "a", "a" }
assert(not E.validate(invalid), "duplicate members fail validation")
invalid.memberIds = { [2] = "b" }
assert(not E.validate(invalid), "sparse member lists fail validation")

reset()
P.getBase(target.id).home.z = {}
assert(E.proposeRaid(faction.id, target.id, 10) == nil, "malformed floor data fails without concatenation error")
reset()
local state = P.getKnoxEventState()
state.nextId = 1e100
state.records["knox-event-1"] = { phase = "failed", revision = 1, lastChangedAtHours = 0 }
event = assert(E.scheduleRaid(faction.id, target.id, 10, 0))
assert(event.id == "knox-event-2", "poisoned serial falls back without collision or non-incrementing loop")
assert(E.transition(event.id, event.revision, "failed", 10, "cancelled"))
for index = 1, 160 do
    local id = "history-" .. index
    state.records[id] = { id = id, phase = "failed", revision = 1, lastChangedAtHours = 11 }
end
for _ = 1, 15 do assert(E.maintain(12, 4) <= 4) end
local count = 0
for _ in pairs(state.records) do count = count + 1 end
assert(count <= 128 and E.get(event.id) == nil, "finished history prunes in bounded batches")
local _, reason = E.proposeRaid(faction.id, target.id, 12)
assert(reason == "faction_event_cooldown", "history pruning does not erase faction raid cooldown")
data = clone(data)
assert(E.proposeRaid(faction.id, target.id, 12) == nil, "cooldown survives save state cloning")
E.maintain(35)
assert(E.proposeRaid(faction.id, target.id, 35) ~= nil, "elapsed cooldown permits a later real-roster proposal")
print("Knox Events PASS migration=true real_roster=true minority=true no_spawn=true phases=true reload=true cancellation=true bounded=true corruption=true cooldown=true")
