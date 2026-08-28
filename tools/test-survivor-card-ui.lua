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
assert(string.find(source, 'context.medicalCheck', 1, true),
    "survivor card must expose the shared medical-check shortcut")

print("Survivor card UI PASS vanilla_portrait=true inventory=true medical=true")
