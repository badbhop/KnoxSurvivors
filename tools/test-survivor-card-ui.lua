local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_SurvivorCard.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

local attach = assert(string.find(source, "self:addChild%(self%.portrait%)"),
    "portrait must be attached")
local state = assert(string.find(source, 'self%.portrait:setState%("idle"%)'),
    "portrait idle state must be configured")
assert(attach < state,
    "Build 42 UI3DModel must be attached before Java-backed methods are called")

print("Survivor card UI PASS portrait_instantiated_before_state=true")
