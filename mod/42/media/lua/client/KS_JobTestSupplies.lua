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
    {"Base.Log", 8}, {"Base.Plank", 16}, {"Base.Nails", 40},
    {"Base.Hinge", 4}, {"Base.Doorknob", 2}, {"Base.TomatoSeed", 6},
    {"Base.Book", 2},
    {"Base.AnimalFeedBag", 2}, {"Base.BucketWaterDebug", 2, "water"},
}

function Supplies.ensure(base, character, force)
    local settings = rawget(_G, "KnoxSettings")
    if settings == nil or settings.developerJobSuppliesEnabled == nil
        or not settings.developerJobSuppliesEnabled() then return 0, "disabled" end
    if base == nil or character == nil then return 0, "base_or_worker_missing" end
    local now = getTimestampMs ~= nil and tonumber(getTimestampMs()) or nil
    if now == nil then
        now = getGameTime ~= nil and getGameTime():getWorldAgeHours() * 3600000 or 0
    end
    if force ~= true and nextFill[base] ~= nil and now < nextFill[base] then return 0, "cooldown" end
    nextFill[base] = now + 10000
    local policy
    for _, candidate in ipairs(KnoxBaseStorage.policies(base)) do
        if candidate.toolCupboard == true or candidate.key == base.toolCupboardKey then policy = candidate; break end
    end
    local resolved = policy ~= nil and KnoxBaseStorage.resolvePolicy(policy) or nil
    if resolved == nil then return 0, "set_a_loaded_central_cupboard_first" end
    local inventory, added = resolved.container, 0
    local failures = {}
    for _, entry in ipairs(KIT) do
        local full, amount, kind = entry[1], entry[2], entry[3]
        local requirements = {items={[full]=amount}}
        if kind ~= nil then
            requirements.itemRules = {[full]=kind=="water" and {water=true} or {usable=true}}
        end
        local missing = amount - KnoxBaseSupplyPlanner.inventoryCount(inventory, full, requirements)
        while missing > 0 do
            local ok, item = pcall(function() return InventoryItemFactory.CreateItem(full) end)
            if not ok or item == nil then failures[#failures+1]=full; break end
            local room, allowed = pcall(function()
                return inventory:hasRoomFor(character, item) and inventory:isItemAllowed(item)
            end)
            if not room or not allowed then return added, "cupboard_full_or_item_restricted" end
            local success = pcall(function() inventory:AddItem(item) end)
            if not success or not inventory:contains(item) then failures[#failures+1]=full; break end
            local countOk, quantity = pcall(function() return item:getCount() end)
            missing = missing - math.max(1, countOk and (tonumber(quantity) or 1) or 1)
            added = added + 1
        end
    end
    if added > 0 then
        print("[KnoxSurvivors][JobTests] supplied base=" .. tostring(base.id) .. " items=" .. tostring(added))
    end
    return added, #failures > 0 and ("unavailable_items=" .. table.concat(failures, ",")) or "test_stock_ready"
end
return Supplies
