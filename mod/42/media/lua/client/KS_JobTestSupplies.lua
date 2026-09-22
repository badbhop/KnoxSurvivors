-- Explicit developer aid: create real test stock, never fake job completion.
require "KS_Settings"
require "KS_BaseStorage"
require "KS_BaseSupplyPlanner"
local Supplies = rawget(_G, "KnoxJobTestSupplies") or {}
_G.KnoxJobTestSupplies = Supplies
local nextFill = setmetatable({}, {__mode="k"})
local KIT = {
    {"Base.Hammer", 2, "tool"}, {"Base.Saw", 2, "tool"},
    {"Base.HandAxe", 2, "tool"}, {"Base.HandShovel", 2, "tool"},
    {"Base.Wrench", 1, "tool"}, {"Base.Screwdriver", 1, "tool"},
    {"Base.Log", 8}, {"Base.Plank", 16}, {"Base.Nails", 40},
    {"Base.Hinge", 4}, {"Base.Doorknob", 2}, {"Base.TomatoSeed", 6},
    {"Base.Book", 2}, {"Base.FishFillet", 2},
    {"Base.BucketWaterDebug", 2, "water"},
}

-- Engine-minted stock only, via the string overload: the same native call
-- survivor starting gear (and reference NPC mods) use. Adding a pre-created
-- instance carries its existing id, which vanilla rejects with "container
-- already has id"; worse, the factory/script-manager paths do not exist in
-- every client context, which used to fail the whole refill closed with no
-- stock and no diagnosis. The engine call needs neither: progress is
-- measured by recounting the container afterwards, and every run reports
-- its outcome so a live log always shows why stock did or did not land.
local function addRealItem(inventory, full, requirements, beforeCount)
    local addedItem = nil
    local ok = pcall(function()
        addedItem = inventory:AddItem(full)
    end)
    if not ok or addedItem == nil then
        return nil
    end
    local countOk, afterCount = pcall(function()
        return KnoxBaseSupplyPlanner.inventoryCount(inventory, full, requirements)
    end)
    if not countOk or (tonumber(afterCount) or 0) <= (tonumber(beforeCount) or 0) then
        return nil
    end
    return addedItem
end

function Supplies.ensure(base, character, force)
    local settings = rawget(_G, "KnoxSettings")
    local freeResources = settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() == true
    if not freeResources then return 0, "disabled" end
    if base == nil or character == nil then return 0, "base_or_worker_missing" end
    local now = getTimestampMs ~= nil and tonumber(getTimestampMs()) or nil
    if now == nil then
        now = getGameTime ~= nil and getGameTime():getWorldAgeHours() * 3600000 or 0
    end
    if force ~= true and nextFill[base] ~= nil and now < nextFill[base] then return 0, "cooldown" end
    nextFill[base] = now + 10000
    local policy
    for _, candidate in ipairs(KnoxBaseStorage.policies(base)) do
        policy = candidate; break
    end
    local resolved = policy ~= nil and KnoxBaseStorage.resolvePolicy(policy) or nil
    local inventory = resolved ~= nil and resolved.container or nil
    if inventory == nil then
        -- Ignore-mode with no assigned storage yet: top up the worker's own
        -- inventory so discovery and native actions have real items.
        inventory = character.getInventory ~= nil and character:getInventory() or nil
        if inventory == nil then return 0, "assign_typed_storage_first" end
    end
    local added = 0
    local failures = {}
    local stopped = nil
    -- The just-added engine item doubles as the room/allowed probe for the
    -- next top-up: it carries real weight and a real id, so container
    -- capacity and restrictions are honored without any factory.
    local probes = {}
    for _, entry in ipairs(KIT) do
        local full, amount, kind = entry[1], entry[2], entry[3]
        local requirements = {items={[full]=amount}}
        if kind ~= nil then
            requirements.itemRules = {[full]=kind=="water" and {water=true} or {usable=true}}
        end
        local missing = amount - KnoxBaseSupplyPlanner.inventoryCount(inventory, full, requirements)
        local guard = 0
        while missing > 0 and guard < amount + 8 do
            guard = guard + 1
            local probe = probes[full]
            if probe ~= nil then
                local room, allowed = pcall(function()
                    return inventory:hasRoomFor(character, probe) and inventory:isItemAllowed(probe)
                end)
                if not room or not allowed then
                    stopped = "cupboard_full_or_item_restricted"
                    break
                end
            end
            local addedItem = addRealItem(inventory, full, requirements, amount - missing)
            if addedItem == nil then
                stopped = "cupboard_full_or_item_restricted"
                break
            end
            probes[full] = addedItem
            local allowedOk, allowed = pcall(function()
                return inventory:isItemAllowed(addedItem)
            end)
            if not allowedOk or allowed ~= true then
                if inventory.Remove ~= nil then
                    pcall(function() inventory:Remove(addedItem) end)
                end
                stopped = "cupboard_full_or_item_restricted"
                break
            end
            added = added + 1
            missing = amount - KnoxBaseSupplyPlanner.inventoryCount(inventory, full, requirements)
        end
        if stopped ~= nil then break end
        if missing > 0 and guard >= amount + 8 then
            failures[#failures+1]=full
        end
    end
    local result = stopped
        or (#failures > 0 and ("unavailable_items=" .. table.concat(failures, ",")) or "test_stock_ready")
    print("[KnoxSurvivors][JobTests] ensure base=" .. tostring(base.id)
        .. " added=" .. tostring(added) .. " result=" .. tostring(result))
    return added, result
end

-- Ignore-mode worker top-up: real engine-minted items straight into the
-- worker's pockets so native actions validate against carried stock with no
-- fetch trips. Items are genuinely created, carried, and consumed by the
-- normal timed actions; nothing is faked. Tools persist once carried, so
-- repeated top-ups only replace what tasks actually consumed.
function Supplies.topUp(character, requirements)
    local settings = rawget(_G, "KnoxSettings")
    local freeResources = settings ~= nil and settings.ignoreJobResourceRequirements ~= nil
        and settings.ignoreJobResourceRequirements() == true
    if not freeResources then return 0, "disabled" end
    if character == nil or type(requirements) ~= "table" then return 0, "missing" end
    local inventory = character.getInventory ~= nil and character:getInventory() or nil
    if inventory == nil then return 0, "no_inventory" end
    local added = 0
    local itemRules = requirements.itemRules
    local missingTypes = {}
    for fullType, required in pairs(requirements.items or {}) do
        local amount = math.max(0, math.floor(tonumber(required) or 0))
        if amount > 0 then
            local scoped = { items = { [fullType] = amount } }
            if type(itemRules) == "table" and itemRules[fullType] ~= nil then
                scoped.itemRules = { [fullType] = itemRules[fullType] }
            end
            local missing = amount
                - KnoxBaseSupplyPlanner.inventoryCount(inventory, fullType, scoped)
            local guard = 0
            while missing > 0 and guard < amount + 8 do
                guard = guard + 1
                if addRealItem(inventory, fullType, scoped, amount - missing) == nil then
                    break
                end
                added = added + 1
                missing = amount
                    - KnoxBaseSupplyPlanner.inventoryCount(inventory, fullType, scoped)
            end
            if missing > 0 then missingTypes[#missingTypes + 1] = tostring(fullType) end
        end
    end
    if #missingTypes > 0 then
        table.sort(missingTypes)
        return added, "unavailable_items=" .. table.concat(missingTypes, ",")
    end
    return added, "topped_up"
end
-- Small discovery kit per worker. The bulk developer kit must never be put
-- into every resident's pockets: eight logs alone can prevent normal work.
-- Actual claimed tasks receive their exact quantities through topUp.
function Supplies.prepareDiscovery(base, character)
    local items = { ["Base.Hammer"] = 1, ["Base.Plank"] = 1, ["Base.Nails"] = 2 }
    local rules = { ["Base.Hammer"] = { usable = true } }
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone.enabled ~= false then
            if zone.type == "woodcutting" then
                items["Base.HandAxe"] = 1
                rules["Base.HandAxe"] = { usable = true }
            elseif zone.type == "log_processing" then
                items["Base.Saw"], items["Base.Log"] = 1, 1
                rules["Base.Saw"] = { usable = true }
            elseif zone.type == "farming" then
                items["Base.HandShovel"], items["Base.TomatoSeed"] = 1, 1
                items["Base.BucketWaterDebug"] = 1
                rules["Base.HandShovel"] = { usable = true }
                rules["Base.BucketWaterDebug"] = { water = true }
            elseif zone.type == "cooking" then
                items["Base.FishFillet"] = 1
            end
        end
    end
    return Supplies.topUp(character, { items = items, itemRules = rules })
end

return Supplies
