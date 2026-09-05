require "KS_SurvivorNeeds"
require "KS_SurvivorInventoryActions"

local Support = rawget(_G, "KnoxGroupSupport") or {}
_G.KnoxGroupSupport = Support

local SUPPORT_DISTANCE_SQUARED = 9

local function safeCall(object, method, fallback, ...)
    if object == nil or type(object[method]) ~= "function" then return fallback end
    local ok, value = pcall(object[method], object, ...)
    return ok and value or fallback
end

local function walk(container, visitor)
    local items = safeCall(container, "getItems", nil)
    local size = tonumber(safeCall(items, "size", 0)) or 0
    for index = 0, size - 1 do
        local item = safeCall(items, "get", nil, index)
        if item ~= nil then
            visitor(item)
            if safeCall(item, "IsInventoryContainer", false) == true then
                walk(safeCall(item, "getInventory", nil), visitor)
            end
        end
    end
end

local function needKind(character)
    if character == nil or safeCall(character, "isDead", false) == true then return nil end
    local ok, decision = pcall(KnoxSurvivorNeeds.decide, character, nil)
    local kind = ok and type(decision) == "table" and decision.kind or nil
    if kind == "find_food" or kind == "find_water" or kind == "find_medical" then
        return kind, decision.state or KnoxSurvivorNeeds.snapshot(character)
    end
    return nil
end

local function category(item, kind)
    if kind == "find_food" then
        local ok, result = pcall(KnoxSurvivorNeeds.isSafeFood, item)
        return ok and result == true
    end
    if kind == "find_water" then
        local ok, result = pcall(KnoxSurvivorNeeds.isWaterItem, item, false)
        return ok and result == true
    end
    return kind == "find_medical" and safeCall(item, "isCanBandage", false) == true
end

local function utility(item, kind)
    if kind == "find_food" then
        return math.abs(tonumber(safeCall(item, "getHungerChange", 0)) or 0)
    end
    if kind == "find_water" then
        local fluid = safeCall(item, "getFluidContainer", nil)
        return tonumber(safeCall(fluid, "getAmount", 0)) or 0
    end
    return tonumber(safeCall(item, "getBandagePower", 0)) or 0
end

local function ownNeed(character, kind)
    local needed = needKind(character)
    return needed == kind
end

function Support.findSafeSurplus(character, kind)
    if character == nil or character:getInventory() == nil then return nil, "missing_inventory" end
    local candidates = {}
    walk(character:getInventory(), function(item)
        if category(item, kind)
            and safeCall(item, "isFavorite", false) ~= true
            and safeCall(character, "isEquipped", false, item) ~= true then
            candidates[#candidates + 1] = item
        end
    end)
    local reserve = 1
    if ownNeed(character, kind) then reserve = reserve + 1 end
    if #candidates <= reserve then return nil, "reserve_protected" end
    table.sort(candidates, function(first, second)
        local firstScore, secondScore = utility(first, kind), utility(second, kind)
        if firstScore == secondScore then
            return tostring(safeCall(first, "getFullType", ""))
                < tostring(safeCall(second, "getFullType", ""))
        end
        return firstScore > secondScore
    end)
    return candidates[1], "surplus_available"
end

local function nearby(first, second)
    local a = safeCall(first, "getCurrentSquare", nil)
    local b = safeCall(second, "getCurrentSquare", nil)
    if a == nil or b == nil or a:getZ() ~= b:getZ() then return false end
    local dx, dy = a:getX() - b:getX(), a:getY() - b:getY()
    return dx * dx + dy * dy <= SUPPORT_DISTANCE_SQUARED
end

local function urgency(kind, state)
    if kind == "find_medical" then
        return 300 + (tonumber(state ~= nil and state.bleedingParts) or 0) * 20
    end
    if kind == "find_water" then
        return 200 + (tonumber(state ~= nil and state.thirst) or 0) * 100
    end
    return 100 + (tonumber(state ~= nil and state.hunger) or 0) * 100
end

function Support.plan(donor, recipients, reservedRecipients, reservedItems)
    if donor == nil or safeCall(donor, "isDead", false) == true then return nil end
    local seen, choices = {}, {}
    for _, recipient in ipairs(recipients or {}) do
        if recipient ~= nil and recipient ~= donor and not seen[recipient]
            and safeCall(recipient, "isDead", false) ~= true
            and nearby(donor, recipient)
            and (reservedRecipients == nil or reservedRecipients[recipient] == nil) then
            seen[recipient] = true
            local kind, state = needKind(recipient)
            if kind ~= nil then
                local item = Support.findSafeSurplus(donor, kind)
                if item ~= nil and (reservedItems == nil or reservedItems[item] == nil) then
                    choices[#choices + 1] = {
                        recipient = recipient,
                        kind = kind,
                        item = item,
                        source = safeCall(item, "getContainer", nil),
                        destination = safeCall(recipient, "getInventory", nil),
                        urgency = urgency(kind, state),
                    }
                end
            end
        end
    end
    table.sort(choices, function(first, second)
        if first.urgency == second.urgency then
            return tostring(first.recipient) < tostring(second.recipient)
        end
        return first.urgency > second.urgency
    end)
    local plan = choices[1]
    return plan ~= nil and plan.source ~= nil and plan.destination ~= nil and plan or nil
end

function Support.mostUrgentNeed(observer, recipients)
    local seen, best = {}, nil
    for _, recipient in ipairs(recipients or {}) do
        if recipient ~= nil and recipient ~= observer and not seen[recipient]
            and safeCall(recipient, "isDead", false) ~= true
            and nearby(observer, recipient) then
            seen[recipient] = true
            local kind, state = needKind(recipient)
            if kind ~= nil then
                local score = urgency(kind, state)
                if best == nil or score > best.urgency then
                    best = { recipient = recipient, kind = kind,
                        state = state, urgency = score }
                end
            end
        end
    end
    return best
end

function Support.queue(donor, plan)
    if donor == nil or plan == nil or plan.source == nil or plan.destination == nil
        or not plan.source:contains(plan.item) then
        return nil, "support_item_unavailable"
    end
    return KnoxInventoryActions.queueTransfer(
        donor,
        plan.item,
        plan.source,
        plan.destination,
        nil
    )
end

function Support.verify(plan)
    return plan ~= nil and plan.source ~= nil and plan.destination ~= nil
        and not plan.source:contains(plan.item) and plan.destination:contains(plan.item)
end

return Support
