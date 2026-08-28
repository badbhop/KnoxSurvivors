local rootPath = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local autonomy = read(rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua")
assert(autonomy:find("function Autonomy.beginVirtualBaseReturn", 1, true)
    and autonomy:find("controller:shutdown()", 1, true)
    and autonomy:find("bridge:removeNpc(survivorId)", 1, true),
    "unloaded base return must capture before removing the active shell")
assert(autonomy:find("KnoxUnloadedSurvival.beginBaseReturn", 1, true),
    "unloaded base return must create a virtual route after handoff")

local service = read(rootPath .. "/mod/42/media/lua/client/KS_CompanionService.lua")
assert(service:find("autonomy.beginVirtualBaseReturn", 1, true),
    "Return to Base command must request a virtual handoff for unloaded destinations")

local population = read(rootPath .. "/mod/42/media/lua/client/KS_WorldPopulation.lua")
assert(population:find('state.activity ~= "returning_to_base"', 1, true),
    "virtual return route must be eligible for normal hidden materialization")

print("Unloaded base return PASS capture_remove=true virtual_route=true materialization=true")
