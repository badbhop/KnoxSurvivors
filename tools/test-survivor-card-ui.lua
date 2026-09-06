local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_SurvivorCard.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(string.find(source, 'require "XpSystem/ISUI/ISCharacterScreen"', 1, true),
    "survivor card must use the vanilla Character Screen for the portrait")
assert(string.find(source, 'ISCharacterScreen:new', 1, true),
    "survivor card must create the vanilla Character Screen view")
assert(not string.find(source, 'ISUI3DModel:new', 1, true),
    "survivor card must not maintain a second custom portrait model")
assert(string.find(source, 'require "KS_CompanionInventory"', 1, true),
    "survivor card must reuse the companion inventory bridge")
assert(string.find(source, 'CompanionInventory.show', 1, true),
    "survivor card must expose the vanilla inventory shortcut")
assert(string.find(source, 'local CompanionInventory = require "KS_CompanionInventory"', 1, true),
    "survivor card must bind the inventory module returned by require")
assert(string.find(source, 'CompanionInventory == nil or CompanionInventory.show == nil', 1, true),
    "survivor card must fail safely when the inventory module is unavailable")
assert(string.find(source, 'view.doBodyPartContextMenu = function() end', 1, true),
    "survivor card health view must remain read-only for off-slot characters")
assert(string.find(source, 'context.medicalCheck', 1, true),
    "survivor card must expose the shared medical-check shortcut")
assert(string.find(source, 'progressBar.char = self.char', 1, true)
    and string.find(source, 'view.playerNum = window.playerNum', 1, true),
    "vanilla skill bars must use a valid local UI slot and read the selected survivor")
assert(not string.find(source, 'pcall(function() view:createChildren() end)', 1, true),
    "health children must be instantiated exactly once by the vanilla addView lifecycle")

print("Survivor card UI PASS vanilla_portrait=true inventory=true medical=true skills=true health_single=true")
