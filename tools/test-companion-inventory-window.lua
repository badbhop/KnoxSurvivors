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
assert(string.find(source, 'active[playerNum] = survivorId', 1, true),
    "companion inventory must track the active survivor per local player")
assert(string.find(source, 'getPlayerLoot(playerNum)', 1, true)
    and string.find(source, 'getPlayerInventory(playerNum)', 1, true),
    "companion inventory must use the matching player's vanilla inventory pages")
assert(string.find(source, 'page:addContainerButton(itemInv', 1, true),
    "companion inventory must expose survivor bags through vanilla container buttons")
assert(string.find(source, 'function CompanionInventory.finish(playerNum)', 1, true),
    "companion inventory must restore the vanilla loot page when finished")

print("Companion inventory UI PASS native_transfer=true split_screen=true nested_containers=true")
