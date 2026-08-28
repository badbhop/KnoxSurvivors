local rootPath = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local vehicles = read(rootPath .. "/mod/42/media/lua/client/KS_CompanionVehicles.lua")
assert(vehicles:find('require "TimedActions/ISEnterVehicle"', 1, true)
    and vehicles:find('require "TimedActions/ISExitVehicle"', 1, true),
    "companion vehicle support must use vanilla enter and exit actions")
assert(vehicles:find('ISPathFindAction:pathToVehicleSeat', 1, true)
    and vehicles:find('ISEnterVehicle:new', 1, true),
    "companion boarding must follow vanilla path and entry flow")
assert(vehicles:find('for seat = 1, vehicle:getMaxPassengers() - 1 do', 1, true),
    "companion boarding must reserve driver seat zero for the player")
assert(vehicles:find('door:isLocked()', 1, true),
    "companion boarding must not bypass locked doors")

local service = read(rootPath .. "/mod/42/media/lua/client/KS_CompanionService.lua")
assert(service:find('function CompanionService.boardPlayerVehicle', 1, true)
    and service:find('function CompanionService.exitVehicle', 1, true),
    "companion service must expose passenger board and exit commands")
assert(service:find('No more seats.', 1, true),
    "full vehicles must give the player-facing wait message")

local context = read(rootPath .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua")
assert(context:find('Enter My Vehicle', 1, true)
    and context:find('Exit Vehicle', 1, true),
    "companion Orders menu must expose vehicle commands")

print("Companion vehicles PASS vanilla_actions=true passenger_only=true context_commands=true")
