require "KS_ActivityFeed"

-- One-click in-game setups for every base job. Each scenario stages the real
-- prerequisites (base, storage role, stock, work area, resident preference)
-- and then lets the normal scheduler and native actions run, so what you see
-- is what players get. Nothing here invents stock or completes work.
local Scenarios = rawget(_G, "KnoxJobTestScenarios") or {}
_G.KnoxJobTestScenarios = Scenarios

local DEFINITIONS = {
    { key = "barricade_here", label = "Test: Barricade This Building" },
    { key = "farm_here", label = "Test: Farm Here" },
    { key = "wood_here", label = "Test: Chop Trees Here" },
    { key = "saw_here", label = "Test: Saw Logs Here" },
    { key = "haul_here", label = "Test: Haul Corpses Here" },
    { key = "burn_here", label = "Test: Burn Corpses Here" },
    { key = "cook_here", label = "Test: Cook Here" },
    { key = "repair_here", label = "Test: Repair Here" },
    { key = "guard_here", label = "Test: Guard Here" },
    { key = "patrol_here", label = "Test: Patrol Here" },
    { key = "scavenge_run", label = "Test: Scavenge Run" },
}

function Scenarios.list()
    return DEFINITIONS
end

local function getGlobal(name)
    return rawget(_G, name)
end

local function feed(message)
    local feedModule = getGlobal("KnoxActivityFeed")
    if feedModule ~= nil and feedModule.event ~= nil then
        feedModule.event(message)
    end
end

local function squareOf(worldObjects)
    for _, object in ipairs(worldObjects or {}) do
        local square = object ~= nil and object.getSquare ~= nil and object:getSquare() or nil
        if square ~= nil then
            return square
        end
    end
    return nil
end

local function clickedContainer(worldObjects)
    for _, object in ipairs(worldObjects or {}) do
        local ok, count = pcall(function() return object:getContainerCount() end)
        if ok and (tonumber(count) or 0) > 0 then
            return object
        end
    end
    return nil
end

-- Base, or a reason string when the player has none established yet.
local function setupBase(player, square)
    local service = getGlobal("KnoxCompanionService")
    local manager = getGlobal("KnoxBaseManager")
    local playerId = player ~= nil and service ~= nil and service.getPlayerId ~= nil
        and service.getPlayerId(player) or nil
    local base = playerId ~= nil and manager ~= nil and manager.getForOwner ~= nil
        and manager.getForOwner("player", playerId) or nil
    if base ~= nil then
        return base
    end
    if player ~= nil and square ~= nil and manager ~= nil
        and manager.establishPlayerBase ~= nil then
        local established = manager.establishPlayerBase(player, square)
        if established ~= nil then
            return established
        end
    end
    return nil, "Right-click inside a building and Establish Home Base first."
end

local function setupResident(base)
    local persistence = getGlobal("KnoxPersistence")
    local residents = base ~= nil and persistence ~= nil
        and persistence.getBaseResidentIds ~= nil
        and persistence.getBaseResidentIds(base.id) or {}
    if type(residents) == "table" and #residents > 0 then
        return residents[1]
    end
    return nil, "No resident yet: recruit a companion and send them home first."
end

-- Assigns the clicked container to the role, or confirms an existing policy.
local function setupStorage(base, worldObjects, role)
    local manager = getGlobal("KnoxBaseManager")
    local storage = getGlobal("KnoxBaseStorage")
    if base == nil or manager == nil or storage == nil then
        return nil, "storage unavailable"
    end
    for _, policy in ipairs(storage.policies ~= nil and storage.policies(base) or {}) do
        if policy ~= nil and tostring(policy.storageRole or "") == role then
            return policy
        end
    end
    local object = clickedContainer(worldObjects)
    if object ~= nil and manager.setStoragePolicy ~= nil then
        local policy = manager.setStoragePolicy(base.id, object, role, 0)
        if policy ~= nil then
            return policy
        end
    end
    return nil, "Right-click a container for this test so it can hold " .. tostring(role) .. "."
end

local function stock(base, actor)
    local supplies = getGlobal("KnoxJobTestSupplies")
    if supplies == nil or supplies.ensure == nil then
        return 0, "supplies_unavailable"
    end
    return supplies.ensure(base, actor, true)
end

local function markZone(base, square, kind, half, label)
    local persistence = getGlobal("KnoxPersistence")
    if base == nil or square == nil or persistence == nil
        or persistence.addBaseZone == nil then
        return nil, "zone_unavailable"
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    return persistence.addBaseZone(base.id, kind, {
        x1 = x - half, y1 = y - half, x2 = x + half, y2 = y + half, z = z,
    }, label)
end

local function setPreference(player, residentId, preference)
    local service = getGlobal("KnoxCompanionService")
    if service == nil or service.setBaseJobPreference == nil then
        return false, "preference_unavailable"
    end
    return service.setBaseJobPreference(player, residentId, preference)
end

-- Hands the resident the first queued task of one of the given types.
local function assignQueued(player, base, residentId, types)
    local board = getGlobal("KnoxBaseTaskBoard")
    if board == nil or board.claimSpecific == nil then
        return nil, "task_board_unavailable"
    end
    local wanted = {}
    for _, kind in ipairs(types or {}) do wanted[tostring(kind)] = true end
    local candidates = {}
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task ~= nil and task.state == "queued" and wanted[tostring(task.type)] then
            candidates[#candidates + 1] = task
        end
    end
    table.sort(candidates, function(a, b)
        return (tonumber(a.priority) or 0) > (tonumber(b.priority) or 0)
    end)
    local task = candidates[1]
    if task == nil then
        return nil, "no_queued_task"
    end
    local service = getGlobal("KnoxCompanionService")
    local playerId = player ~= nil and service ~= nil and service.getPlayerId ~= nil
        and service.getPlayerId(player) or nil
    return board.claimSpecific(base.id, task.id, residentId, playerId)
end

local function finish(key, ok, message)
    feed(message)
    print("[KnoxSurvivors][JobTests] scenario=" .. tostring(key)
        .. " ok=" .. tostring(ok) .. " " .. tostring(message))
    return ok, message
end

local function prepare(playerNum, worldObjects, role)
    local specificPlayer = getGlobal("getSpecificPlayer")
    local player = specificPlayer ~= nil and specificPlayer(playerNum) or nil
    if player == nil then
        return nil, "no_player"
    end
    local square = squareOf(worldObjects)
    if square == nil then
        return nil, "Right-click the ground or a container where the work should happen."
    end
    local base, baseReason = setupBase(player, square)
    if base == nil then
        return nil, baseReason
    end
    local residentId, residentReason = setupResident(base)
    if residentId == nil then
        return nil, residentReason
    end
    if role ~= nil then
        local _, storageReason = setupStorage(base, worldObjects, role)
        if storageReason ~= nil then
            -- Storage staging is best-effort: assigned stores or the worker's
            -- own pockets can still satisfy the native action.
            feed(tostring(storageReason))
        end
    end
    local stocked, stockResult = stock(base, player)
    local stockNote
    if (tonumber(stocked) or 0) > 0 then
        stockNote = "Test stock landed (" .. tostring(stocked) .. " items)."
    elseif tostring(stockResult) == "disabled" then
        stockNote = "Test stock is off: enable Ignore Job Resource Requirements, "
            .. "or stock the assigned cupboard with real tools and materials."
    else
        stockNote = "Test stock reported " .. tostring(stockResult)
            .. ": stock the assigned cupboard with real tools and materials."
    end
    return {
        player = player,
        square = square,
        base = base,
        residentId = residentId,
        stockNote = stockNote,
    }
end

local RUNNERS = {}

RUNNERS.barricade_here = function(context)
    local menu = getGlobal("KnoxBaseContextMenu")
    if menu == nil or menu.orderBarricadeHere == nil then
        return false, "barricade_orders_unavailable"
    end
    menu.orderBarricadeHere(context.player, context.base, context.square)
    return true, "Barricade work ordered: watch the resident fetch tools and hammer planks."
end

local function preferenceScenario(key, context, zoneKind, half, zoneLabel, preference, types, watchText, emptyText)
    if zoneKind ~= nil then
        markZone(context.base, context.square, zoneKind, half or 2, zoneLabel or zoneKind)
    end
    setPreference(context.player, context.residentId, preference)
    local assigned = assignQueued(context.player, context.base, context.residentId, types)
    if assigned ~= nil then
        return true, watchText
    end
    return true, emptyText
end

RUNNERS.farm_here = function(context)
    return preferenceScenario("farm_here", context, "farming", 2, "Test Plot", "farming",
        { "farm_water", "farm_harvest", "farm_plow", "farm_seed" },
        "Farm work assigned: watch the resident work the plot with native animations.",
        "Test plot marked and gardener assigned: plow, plant, or wait for thirsty crops.")
end

RUNNERS.wood_here = function(context)
    return preferenceScenario("wood_here", context, "woodcutting", 4, "Test Wood Lot", "woodwork",
        { "chop_tree" },
        "Tree-felling assigned: watch the resident chop with an axe.",
        "Wood lot marked and lumberjack assigned: tasks appear for live trees in the area.")
end

RUNNERS.saw_here = function(context)
    return preferenceScenario("saw_here", context, "log_processing", 2, "Test Log Yard", "woodwork",
        { "saw_logs" },
        "Log sawing assigned: watch the resident saw with native animations.",
        "Log yard marked: drop logs nearby and the saw task will queue.")
end

RUNNERS.haul_here = function(context)
    return preferenceScenario("haul_here", context, "corpse", 2, "Test Corpse Drop", "hauling",
        { "haul_corpse" },
        "Corpse haul assigned: watch the grab, drag, and drop.",
        "Drop area marked and hauler assigned: the next nearby body will be hauled.")
end

RUNNERS.burn_here = function(context)
    return preferenceScenario("burn_here", context, "corpse", 2, "Test Corpse Drop", "hauling",
        { "burn_corpse" },
        "Pile burning assigned: watch the resident burn the full pile.",
        "Drop area marked: burning queues automatically once the pile is full.")
end

RUNNERS.cook_here = function(context)
    return preferenceScenario("cook_here", context, "cooking", 1, "Test Kitchen", "auto",
        { "cook" },
        "Cooking assigned: watch the resident cook at the stove.",
        "Kitchen marked near this stove: cooking queues when ingredients are stored.")
end

RUNNERS.repair_here = function(context)
    setPreference(context.player, context.residentId, "repair")
    local assigned = assignQueued(context.player, context.base, context.residentId, { "repair" })
    if assigned ~= nil then
        return true, "Repair assigned: watch the resident fix the structure."
    end
    return true, "Handyman assigned: repairs queue when structures in the territory take damage."
end

RUNNERS.guard_here = function(context)
    return preferenceScenario("guard_here", context, "guard", 1, "Test Guard Post", "guard",
        { "guard" },
        "Guard duty assigned: watch the resident take the post.",
        "Guard post marked: the resident will staff it from the duty roster.")
end

RUNNERS.patrol_here = function(context)
    return preferenceScenario("patrol_here", context, "patrol", 3, "Test Patrol", "patrol",
        { "patrol" },
        "Patrol assigned: watch the resident walk the route.",
        "Patrol area marked: the resident will walk it from the duty roster.")
end

RUNNERS.scavenge_run = function(context)
    local service = getGlobal("KnoxCompanionService")
    if service == nil or service.setBaseSupplyOrder == nil then
        return false, "supply_orders_unavailable"
    end
    local ok, result = service.setBaseSupplyOrder(context.player, context.residentId, "find_food")
    if ok then
        return true, "Scavenge run ordered: watch the resident loot nearby buildings and haul food home."
    end
    return false, "Scavenge order failed: " .. tostring(result)
end

-- Storage roles per scenario: the clicked container is assigned when the
-- base has no store of that kind yet.
local SCENARIO_STORAGE = {
    barricade_here = "tools",
    farm_here = "farming",
    wood_here = "tools",
    saw_here = "building",
    haul_here = nil,
    burn_here = nil,
    cook_here = "food",
    repair_here = "building",
    guard_here = nil,
    patrol_here = nil,
    scavenge_run = "food",
}

function Scenarios.run(playerNum, key, worldObjects)
    local runner = RUNNERS[tostring(key)]
    if runner == nil then
        return finish(key, false, "Unknown job test: " .. tostring(key) .. ".")
    end
    local context, reason = prepare(playerNum, worldObjects, SCENARIO_STORAGE[tostring(key)])
    if context == nil then
        return finish(key, false, reason)
    end
    local ok, message = runner(context)
    -- Never report a staged job without saying whether materials exist:
    -- an unstocked cupboard is the usual reason a resident walks but never acts.
    if context.stockNote ~= nil then
        message = tostring(message) .. " " .. tostring(context.stockNote)
    end
    return finish(key, ok ~= false, message)
end

return Scenarios
