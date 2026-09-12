local root = assert(arg[1], "repository root argument missing")

local function read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local function readAbsolute(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local wood = read("mod/42/media/lua/client/KS_BaseWoodcutting.lua")
local storage = read("mod/42/media/lua/client/KS_BaseStorage.lua")
local corpse = read("mod/42/media/lua/client/KS_BaseCorpseHandling.lua")
local autonomy = read("mod/42/media/lua/client/KS_SurvivorAutonomy.lua")
local jobs = read("mod/42/media/lua/client/KS_BaseJobs.lua")
local gameDirectory = arg[2]

assert(storage:find("function Storage.findItemType", 1, true),
    "base storage must expose loaded real items to task discovery")
assert(wood:find("storedItem(base", 1, true),
    "wood discovery must bootstrap an axe from assigned storage")
assert(not wood:find("ISCraftAction:new", 1, true),
    "Build 42 woodwork must not queue the legacy recipe action")
assert(not corpse:find("character:pickUpCorpse", 1, true),
    "corpse handling must not repeat the native pickup outside the vanilla action")
assert(corpse:find("ISGrabCorpseAction:new", 1, true),
    "corpse handling must retain the vanilla grab action")
assert(autonomy:find("abandonBaseTask", 1, true),
    "controller failures must release claimed base work")
assert(not jobs:find("return next(items)", 1, true),
    "base requirements must not call Lua next(), which Kahlua does not expose")
assert(autonomy:find('controller.state = "IDLE"', 1, true)
    and autonomy:find("retryAt=", 1, true),
    "ordinary controller failures must recover after a bounded delay")

if gameDirectory ~= nil then
    local recipe = readAbsolute(gameDirectory .. "/media/scripts/generated/recipes/recipes_carpentry.txt")
    assert(recipe:find("craftRecipe SawLogs", 1, true),
        "installed game no longer exposes SawLogs as a legacy recipe")
end

print("base mechanics PASS storage-bootstrap=true native-corpse=true claim-recovery=true")
