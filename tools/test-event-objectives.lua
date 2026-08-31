local rootPath, nativePath = arg[1] or ".", arg[2]
require = function() return true end
local data, hours = {}, 10
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return hours end } end
local function load(name) return assert(loadfile(rootPath .. "/mod/42/media/lua/client/" .. name .. ".lua"))() end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k, v in pairs(value) do result[k] = clone(v) end; return result
end
load("KS_Persistence"); load("KS_KnoxEvents"); load("KS_BaseManager")
local P, E = KnoxPersistence, KnoxEvents
local ids = { "a", "b", "c", "d", "e" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, "native-record-" .. id))
    assert(P.ensureSurvivorIdentity(id, id, "Tester", hours))
end
local group = assert(P.createTravelGroup(ids, hours))
for _, id in ipairs({ "b", "c", "d", "e" }) do
    P.recordEncounter("a", id, { worldAgeHours = hours, began = true, sharedRoam = 1 })
end
local faction = assert(P.evaluateTravelGroupFaction(group.id, hours))
local playerFaction = assert(P.ensurePlayerFaction("player-1", hours))
local home = assert(P.createBase("faction", faction.id, { minX = 100, minY = 100, width = 10, height = 10 }, hours))
local target = assert(P.createBase("player", "player-1", { minX = 200, minY = 200, width = 10, height = 10 }, hours))
for _, id in ipairs(ids) do assert(P.setFactionBaseResident(id, faction.id, home.id, hours)) end
assert(P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", hours, "fixture"))
local event = assert(E.scheduleRaid(faction.id, target.id, hours, 0))
event = assert(E.transition(event.id, event.revision, "spawning", hours))
assert(P.claimEventDuty(event.id, hours))
for _, phase in ipairs({ "approaching", "active" }) do event = assert(E.transition(event.id, event.revision, phase, hours)) end
event = assert(E.beginRaidObjective(event.id, event.revision, hours))
assert(event.objective.requiredItems == 4 and event.phase == "objective")
assert(E.beginRaidObjective(event.id, event.revision, hours) == nil, "cannot reset live receipts")
local baseline = clone(data)
local function reset() data = clone(baseline); hours = 10; event = E.get(event.id) end
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z or 0 end }
end
local function container(x, y)
    local c = { items = {}, parent = { getOverlaySprite = function() return nil end }, square = x and square(x, y) }
    function c:contains(item) return self.items[item] == true end
    function c:isInCharacterInventory(character) return self == character.inventory end
    function c:getSourceGrid() return self.square end
    function c:getParent() return self.parent end
    function c:getType() return "crate" end
    function c:setDrawDirty() end
    function c:setHasBeenLooted() end
    return c
end
local sequence = 0
local function item(c)
    sequence = sequence + 1
    local i = { id = sequence, container = c }
    function i:getID() return self.id end
    function i:getFullType() return "Base.Nails" end
    function i:getContainer() return self.container end
    function i:getWeight() return .01 end
    function i:isFavorite() return false end
    function i:setJobDelta() end
    c.items[i] = true
    return i
end
local actor = { inventory = container() }
function actor:getInventory() return self.inventory end
KnoxSurvivorRuntime = { getCharacter = function(id) if id == "a" then return actor end end,
    idForCharacter = function(character) if character == actor then return "a" end end }
instanceof = function(object, class) return object ~= nil and object.class == class end
local R = load("KS_EventRuntime")
ISBaseTimedAction = {}
function ISBaseTimedAction:derive(name)
    local class = { Type = name }; class.__index = class
    return setmetatable(class, { __index = self })
end
function ISBaseTimedAction.perform(self) self.completed = true end
ISInventoryPage = {}
if nativePath then
    -- Execute the installed native batch/perform/transfer functions, mocking only
    -- Java containers, item movement, UI/sound and action construction/validation.
    assert(loadfile(nativePath .. "/media/lua/client/TimedActions/ISInventoryTransferAction.lua"))()
else
    ISInventoryTransferAction = ISBaseTimedAction:derive("ISInventoryTransferAction")
    function ISInventoryTransferAction:canMergeAction(action)
        return action ~= nil and action.Type == self.Type and action.srcContainer == self.srcContainer
            and action.destContainer == self.destContainer
    end
    function ISInventoryTransferAction:transferItem(value)
        self.item = ISTransferAction:transferItem(self.character, value, self.srcContainer, self.destContainer)
    end
    function ISInventoryTransferAction:perform()
        for _, batch in ipairs(self.queueList) do
            for _, value in ipairs(batch.items) do
                self.item = value
                if self:isValid() then self:transferItem(value) end
            end
        end
        ISBaseTimedAction.perform(self)
    end
end
isClient = function() return false end
isServer = function() return false end
round = function(number) return number end
table.wipe = function(value) for key in pairs(value) do value[key] = nil end end
ItemPicker = { updateOverlaySprite = function() end }
local nativeCalls, mode, floor = 0, "move", container()
ISTransferAction = { transferItem = function(_, character, value, source, destination)
    nativeCalls = nativeCalls + 1
    if mode == "noop" or not source:contains(value) then return value end
    source.items[value] = nil
    if mode == "floor" then destination = floor end
    if mode == "replace" then value = item(destination) else destination.items[value] = true end
    value.container = destination
    return value
end }
local queue = { queue = {} }
function queue:indexOf(action) for i, value in ipairs(self.queue) do if value == action then return i end end; return -1 end
ISTimedActionQueue = { add = function(action)
    queue.queue[#queue.queue + 1] = action
    if #queue.queue == 1 then assert(action.knoxEventContext ~= nil or action.ordinaryExpected) end
end, getTimedActionQueue = function() return queue end }
function ISInventoryTransferAction:new(character, value, source, destination)
    return setmetatable({ character = character, item = value, srcContainer = source, destContainer = destination,
        maxTime = 1, queueList = { { items = { value }, type = value:getFullType(), time = 1 } },
        action = { stopTimedActionAnim = function() end, setLoopedAction = function() end, setTime = function() end },
        ordinaryExpected = mode == "ordinary" }, self)
end
function ISInventoryTransferAction:isValid() return self.srcContainer:contains(self.item) and not self.invalid end
function ISInventoryTransferAction:getNotFullFloorSquare() return nil end
function ISInventoryTransferAction:playTransferCompleteSound() end
function ISInventoryTransferAction:playSourceContainerCloseSound() end
function ISInventoryTransferAction:playDestContainerCloseSound() end
function ISInventoryTransferAction:stopLoopingSound() end
load("KS_SurvivorInventoryActions")
local A = KnoxInventoryActions
local source, inventory = container(202, 202), actor.inventory
local function actionFor(value) return assert(A.queueTransfer(actor, value, source, inventory)) end
local firstItem = item(source)
local first = actionFor(firstItem)
assert(first.knoxEventContext.eventId == event.id and first:isValid(), "context installed before queue starts")
assert(E.objectiveCount(E.get(event.id)) == 0, "queuing is not evidence")
mode = "noop"; first:transferItem(firstItem)
assert(E.objectiveCount(E.get(event.id)) == 0 and source:contains(firstItem), "native no-op cannot grant loot")
mode = "floor"; first:transferItem(firstItem)
assert(E.objectiveCount(E.get(event.id)) == 0 and floor:contains(firstItem), "floor fallback is not carried loot")
mode = "move"
local one, two = item(source), item(source)
first, queue.queue = nil, {}
first = actionFor(one)
local second = actionFor(two)
assert(first:canMergeAction(second), "same raid permits native batching")
local other = clone(second.knoxEventContext); other.eventId = "different"
second.knoxEventContext = other
assert(not first:canMergeAction(second), "different ownership must not disappear into a merged action")
second.knoxEventContext = nil
assert(not first:canMergeAction(second), "ordinary action must not absorb event action")
second.knoxEventContext = clone(first.knoxEventContext)
if not nativePath then first.queueList[1].items = { one, two } end
first:perform()
assert(E.objectiveCount(E.get(event.id)) == 2 and inventory:contains(one) and inventory:contains(two), "each actual batched transfer counted")
assert(not R.observeLootTransfer(first.knoxEventContext, actor, source, inventory, one, one, true), "duplicate callback ignored")
data = clone(data)
assert(E.objectiveCount(E.get(event.id)) == 2, "receipt IDs survive saved-state reconstruction")
mode = "replace"
local replacementAction = actionFor(item(source)); replacementAction:transferItem(replacementAction.item)
assert(E.objectiveCount(E.get(event.id)) == 3, "native returned replacement item is authoritative")
mode = "move"
local finalAction = actionFor(item(source)); finalAction:transferItem(finalAction.item)
assert(E.objectiveCount(E.get(event.id)) == 4)
local extra = actionFor(item(source)); local calls = nativeCalls
assert(not extra:isValid()); extra:transferItem(extra.item)
assert(nativeCalls == calls, "quota prevents additional native transfers")
R.reviewObjective(event, hours)
assert(E.get(event.id).phase == "withdrawing" and E.get(event.id).objective.outcome == "supplies_taken")
assert(P.getSurvivorDuty("a").eventId == event.id, "success still requires actual return before duty release")
assert(not finalAction:isValid(), "withdrawal cancels queued looting")

reset(); queue.queue = {}
local pending = actionFor(item(source))
P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "neutral", hours, "peace")
assert(not pending:isValid()); calls = nativeCalls; pending:transferItem(pending.item)
assert(nativeCalls == calls, "peace prevents stealing while runtime catches up")
reset(); pending = actionFor(item(source))
assert(P.releaseEventDuty("a", event.id, hours)); assert(not pending:isValid(), "lost duty cancels")
reset(); pending = actionFor(item(source))
P.getBase(target.id).relocatedAtHours = 11
assert(not pending:isValid(), "relocation cancels old target work")
reset(); pending = actionFor(item(source))
assert(P.markSurvivorDead("a", hours, "fixture")); assert(not pending:isValid(), "dead member cannot keep looting")

reset()
local empty = { eventAssignment = { id = event.id }, id = "a", nextExplorationSearch = 0,
    nextThink = 0, calls = 0, companionDirective = { kind = "hold" } }
function empty:beginExploration(ticks, directive)
    assert(directive.eventId == event.id and directive.kind == "loot_area" and directive.minX == P.getBase(target.id).territory.minX)
    self.calls = self.calls + 1; self.nextExplorationSearch = ticks + 90
    E.recordEmptySearch(event.id, self.id); return false
end
assert(R.beginObjectiveWork(empty, 0)); assert(R.beginObjectiveWork(empty, 1))
assert(empty.calls == 1 and empty.companionDirective.kind == "hold", "bounded retries preserve companion intent")
R.beginObjectiveWork(empty, 90); R.beginObjectiveWork(empty, 180); R.beginObjectiveWork(empty, 270)
assert(empty.calls == 3)
for _ = 1, 5 do E.recordEmptySearch(event.id, "b") end
R.reviewObjective(event, hours)
assert(E.get(event.id).objective.outcome == "no_supplies", "exhaustion withdraws honestly")
reset(); hours = 12; R.reviewObjective(event, hours)
assert(E.get(event.id).objective.outcome == "no_supplies", "deadline cannot fake success")
reset(); pending = actionFor(item(source)); pending:transferItem(pending.item)
hours = 12; R.reviewObjective(event, hours)
assert(E.get(event.id).objective.outcome == "partial_supplies", "partial outcome requires actual item evidence")
reset(); assert(E.finishRaidObjective(event.id, event.revision, hours, "supplies_taken") == nil)
local raw = P.getKnoxEventState().records[event.id]
raw.objective.deadlineHours = math.huge
assert(not E.recordLoot(event.id, "a", { itemId = "fake", fullType = "Base.Nails", x = 202, y = 202, z = 0 }, hours))
R.reviewObjective(event, hours)
assert(E.get(event.id).phase == "withdrawing" and E.get(event.id).objective.outcome == nil, "corrupt objective safely withdraws without false success")
reset()
P.getKnoxEventState().records[event.id].objective.receipts.fake = true
R.reviewObjective(event, hours)
assert(E.get(event.id).phase == "withdrawing" and E.get(event.id).objective.outcome == nil,
    "malformed persisted receipts cannot manufacture a successful objective")
reset()
assert(R.captureLootContext(actor, container(400, 400), inventory) == nil, "outside target is not raid loot")
source.parent.class = "IsoGameCharacter"
assert(R.captureLootContext(actor, source, inventory) == nil, "trade/carried containers are not raid loot")
source.parent.class = nil
assert(R.captureLootContext(actor, inventory, inventory) == nil)
assert(not E.recordEmptySearch(event.id, "unknown") and #P.getSurvivorIds() == 5, "unknown callback cannot create identity")
mode = "ordinary"; queue.queue = {}
local ordinaryItem, outside = nil, container(400, 400); ordinaryItem = item(outside)
local ordinary = assert(A.queueTransfer(actor, ordinaryItem, outside, inventory))
assert(ordinary.knoxEventContext == nil and ordinary:isValid())
ordinary:transferItem(ordinaryItem)
assert(inventory:contains(ordinaryItem) and E.objectiveCount(E.get(event.id)) == 0, "ordinary native transfer unchanged")
for _, id in ipairs(ids) do assert(P.getRecord(id) == "native-record-" .. id) end
print("Event objectives PASS real_transfers=true batching=true no_fake_loot=true ownership=true bounded_search=true reload=true honest_outcomes=true native_lua=" .. tostring(nativePath ~= nil))
