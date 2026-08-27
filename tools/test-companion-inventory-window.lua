local rootPath = arg[1] or "."
local file = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_CompanionInventory.lua", "r"))
local source = file:read("*a")
file:close()

assert(string.find(source, 'ISInventoryTransferUtil.newInventoryTransferAction', 1, true),
    "companion inventory window must use native transfer actions")
assert(string.find(source, 'MAX_DISTANCE_SQUARED', 1, true),
    "companion inventory window must be distance-gated")
assert(string.find(source, 'source:contains(item)', 1, true),
    "transfers must validate the live source item")
assert(string.find(source, 'setRenderThisPlayerOnly(playerNum)', 1, true),
    "companion inventory window must remain split-screen isolated")
assert(string.find(source, '"Take Selected"', 1, true),
    "companion inventory window must expose a selected-item transfer")
assert(string.find(source, 'function Window:onOpenSelected()', 1, true)
    and string.find(source, 'item:getInventory()', 1, true),
    "companion inventory window must support nested carried containers")
assert(string.find(source, 'function Window:onBack()', 1, true),
    "nested inventory navigation must allow returning to the parent container")

print("Companion inventory window PASS native_transfer=true split_screen=true nested_containers=true")
