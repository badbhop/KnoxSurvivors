local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(source:find("function Controller:beginAmbientBaseRest", 1, true),
    "base residents need an explicit ambient rest decision")
assert(source:find("ISRestAction:new", 1, true)
    and source:find("ISSitOnGround:new", 1, true),
    "ambient base life must reuse vanilla furniture and ground sitting actions")
assert(source:find('"BASE_AMBIENT_REST"', 1, true)
    and source:find("BASE_AMBIENT_REST_TICKS", 1, true),
    "ambient rest must be bounded and independently represented")
assert(source:find('self.activeDecision == "base_ambient_rest"', 1, true)
    and source:find("self:leaveRecoveryPosture()", 1, true),
    "ambient rest must release its vanilla posture when it finishes")

print("Base ambient life PASS vanilla_sit=true bounded=true cleanup=true")
