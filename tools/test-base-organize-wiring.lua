-- Controller ↔ organize wiring contract: begin/update/release must honor
-- Organize.find(base, character, ...) argument order, route through the
-- idle tidy choice, and clean up on interrupts/recovery/danger.
local rootPath = arg[1] or "."
local controllerPath = rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
local controllerFile = assert(io.open(controllerPath, "r"))
local controller = controllerFile:read("*a")
controllerFile:close()
local organizePath = rootPath .. "/mod/42/media/lua/client/KS_BaseOrganize.lua"
local organizeFile = assert(io.open(organizePath, "r"))
local organize = organizeFile:read("*a")
organizeFile:close()

assert(organize:find("function Organize.find(base, character, available, reserved)", 1, true)
    and organize:find("function Organize.step(plan, character, base, bridge, id, ticks)", 1, true),
    "organize round owns the (base, character) contract on both ends")
assert(controller:find("KnoxBaseOrganize.find(self.base, self.character,", 1, true),
    "beginBaseOrganize must pass base first, character second")
assert(controller:find("KnoxBaseOrganize.step(\n        plan, self.character, self.base, self.bridge, self.id, ticks)", 1, true)
    or controller:find("KnoxBaseOrganize.step(plan, self.character, self.base", 1, true),
    "updateBaseOrganize must step with (plan, character, base, bridge, id, ticks)")
assert(controller:find("function Controller:beginBaseOrganize", 1, true)
    and controller:find("function Controller:updateBaseOrganize", 1, true)
    and controller:find("function Controller:releaseBaseOrganize", 1, true),
    "organize needs begin/update/release like every other idle round")
assert(controller:find('self.state == "BASE_ORGANIZE"', 1, true)
    and controller:find("self:updateBaseOrganize(ticks)", 1, true),
    "the tick loop must service the organize state")
assert(controller:find('elseif choice == "tidy" then', 1, true)
    and controller:find("if not self:beginBaseOrganize(ticks) then", 1, true),
    "idle residents must reach organize through the tidy choice")
assert(controller:find('if self.state == "BASE_ORGANIZE" then', 1, true)
    and controller:find("self:releaseBaseOrganize()", 1, true),
    "directives, recovery, and danger must release an in-progress organize round")

print("Base organize wiring PASS arg_order=true idle_route=true tick=true interrupts=true recovery=true")
