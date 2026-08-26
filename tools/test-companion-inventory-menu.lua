local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_CompanionInventoryMenu.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(string.find(source, 'OnFillInventoryObjectContextMenu', 1, true),
    "inventory menu must use the vanilla extension event")
assert(string.find(source, 'ISInventoryTransferUtil.newInventoryTransferAction', 1, true),
    "give action must use vanilla inventory transfer")
assert(string.find(source, 'GIVE_DISTANCE_SQUARED', 1, true),
    "give action must require nearby companions")
assert(string.find(source, 'getActualItems', 1, true),
    "stack/wrapper items must resolve through the inventory pane")

print("Companion inventory menu PASS vanilla_transfer=true nearby_only=true")
