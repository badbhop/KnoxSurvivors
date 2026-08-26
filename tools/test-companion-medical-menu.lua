local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(string.find(source, 'require "TimedActions/ISMedicalCheckAction"', 1, true),
    "companion treatment must use the native medical check action")
assert(string.find(source, 'ISHealthPanel.canPerformMedicalCheck', 1, true),
    "companion treatment must retain vanilla reachability checks")
assert(string.find(source, 'ISMedicalCheckAction:new(player, patient)', 1, true),
    "the real local player must be the doctor and the companion the patient")
assert(string.find(source, '"Medical Check"', 1, true),
    "companion context menu must expose medical treatment")

print("Companion medical menu PASS native_action=true local_doctor=true")
