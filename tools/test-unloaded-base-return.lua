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
local storeAt=assert(autonomy:find("KnoxUnloadedSurvival.markStored(survivorId, now)",1,true))
local routeAt=assert(autonomy:find("KnoxUnloadedSurvival.beginBaseReturn(survivorId, base, now)",1,true))
local removeAt=assert(autonomy:find("bridge:removeNpc(survivorId)",1,true))
local unregisterAt=assert(autonomy:find("KnoxSurvivorRuntime.unregister(survivorId, controller)",1,true))
assert(storeAt<routeAt and routeAt<removeAt and removeAt<unregisterAt,
    "stored route is durable before shell removal, with unregister only after removal")
assert(autonomy:find("store_failed=",1,true) and autonomy:find("route_failed=",1,true)
    and autonomy:find("remove_failed=",1,true) and autonomy:find("rollback=",1,true),
    "store, route and removal failures remain retryable and report rollback")

local unloaded=read(rootPath .. "/mod/42/media/lua/client/KS_UnloadedSurvival.lua")
assert(unloaded:find("function Simulation.rollbackBaseReturn",1,true)
    and unloaded:find("state.baseReturn = nil",1,true)
    and unloaded:find('state.status = "loaded"',1,true)
    and unloaded:find('state.activity = "loaded"',1,true),
    "failed native removal restores live-ledger ownership without moving the survivor")

local service = read(rootPath .. "/mod/42/media/lua/client/KS_CompanionService.lua")
assert(service:find("autonomy.beginVirtualBaseReturn", 1, true),
    "Return to Base command must request a virtual handoff for unloaded destinations")

local population = read(rootPath .. "/mod/42/media/lua/client/KS_WorldPopulation.lua")
assert(population:find("returning_to_base = true", 1, true)
    and population:find("hasMaterializableVirtualLocation(state)", 1, true),
    "virtual return route must be eligible through the named hidden-materialization boundary")

print("Unloaded base return PASS capture_remove=true virtual_route=true materialization=true")
