local root = assert(arg[1], "repository root required")
local function read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local inventory = read("mod/42/media/lua/client/KS_CompanionInventory.lua")
local corpse = read("mod/42/media/lua/client/KS_BaseCorpseHandling.lua")

assert(inventory:find('wrapOffslotActionMethod%(ISEquipWeaponAction, "complete"'),
    "off-slot weapon completion must bridge the absent local inventory UI")
assert(inventory:find('wrapOffslotActionMethod%(ISWearClothing, "perform"'),
    "off-slot clothing completion must bridge the absent local inventory UI")
assert(inventory:find('wrapOffslotActionMethod%(ISUnequipAction, "perform"'),
    "corpse-preparation unequip must bridge the absent local inventory UI")
assert(inventory:find("sourceSurvivor ~= character", 1, true)
    and inventory:find("detachTransferredSurvivorItem", 1, true),
    "taking survivor equipment must reconcile that survivor's equipment")
assert(inventory:find('character:removeWornItem%(item, false%)'),
    "taking worn clothing must clear its real worn-item state")
assert(corpse:find("ISGrabCorpseAction:new", 1, true)
    and corpse:find("ISUnequipAction:new", 1, true),
    "corpse hauling must retain the native unequip and grab actions")

print("Companion inventory actions PASS offslot_ui=true visual_detach=true native_corpse=true")

-- Execute the production transfer decorator with native transfer outcomes.
local first = assert(inventory:find("local function detachTransferredSurvivorItem", 1, true))
local last = assert(inventory:find("local inventoryLogLast", first, true))
local segment = inventory:sub(first, last - 1)
local source = { present = true }
function source:contains() return self.present end
local item = {}
local owner = { worn = true, primary = item, refreshes = 0 }
function owner:getPrimaryHandItem() return self.primary end
function owner:getSecondaryHandItem() return nil end
function owner:removeFromHands() self.primary = nil end
function owner:isEquipped() return self.worn end
function owner:removeWornItem() self.worn = false end
function owner:resetModelNextFrame() self.refreshes = self.refreshes + 1 end
local outcome = "reject"
ISInventoryTransferUtil = { newInventoryTransferAction = function()
    return { transferItem = function()
        if outcome == "reject" then return false end
        if outcome == "fail_before" then error("before transfer") end
        source.present = false
        if outcome == "fail_after" then error("after transfer") end
        return true
    end }
end }
triggerEvent = function() end
local builder = assert(loadstring("return function(owner)\n"
    .. "local active = { [0] = true }; local CompanionInventory = {}\n"
    .. "local function sourceHasItem(source, item) return source:contains(item) end\n"
    .. "local function isSurvivorContainer() return true, owner end\n"
    .. segment .. "\nend"))()
builder(owner)
for _, mode in ipairs({ "reject", "fail_before", "success", "fail_after" }) do
    outcome = mode
    source.present, owner.worn, owner.primary, owner.refreshes = true, true, item, 0
    local action = ISInventoryTransferUtil.newInventoryTransferAction({}, item, source, {})
    local ok = pcall(action.transferItem, action, item)
    local moved = mode == "success" or mode == "fail_after"
    assert(owner.worn == not moved and (owner.primary == nil) == moved,
        "equipment must match actual transfer outcome: " .. mode)
    assert(owner.refreshes == (moved and 1 or 0), "refresh only moved gear: " .. mode)
    assert(ok == (mode == "reject" or mode == "success"), "native errors remain visible")
end
print("Transfer outcomes PASS rejection=true early_error=true success=true late_error=true")
