local root = arg[1] or "."
for _, name in ipairs({ "KS_Persistence", "KS_SurvivorRuntime", "KS_ActivityFeed",
    "KS_Settings", "KS_CompanionVehicles", "KS_OrderCatalog", "KS_OrderSignals" }) do
    package.loaded[name] = true
end
local duty = { mode = "companion", ownerId = "player", order = "follow" }
local roster = { "one", "two" }
local player, base = {}, {}
KnoxPersistence = {
    getSurvivorDuty = function() return duty end,
    getSurvivorPolicies = function() return {} end,
    getCompanionIds = function() return roster end,
}
KnoxBaseManager = { get = function() return base end }
local service = dofile(root .. "/mod/42/media/lua/client/KS_CompanionService.lua")
service.resolvePlayer = function() return player end
local calls, baseCalls, fail = 0, 0, false
local controller = {
    setWeaponPreference = function() end,
    setCompanionOrder = function(self, owner, target, order, slot)
        calls = calls + 1
        if fail then error("injected setter failure") end
        self.target, self.order, self.slot = target, order, slot
    end,
    clearCompanionOrder = function() end,
    clearBaseAssignment = function() end,
    setBaseAssignment = function(self, id, value)
        baseCalls = baseCalls + 1
        self.base = value
    end,
}
local function sync() service.syncController("one", controller) end
sync(); sync()
assert(calls == 1, "unchanged companion sync must skip setters")
player = {}; sync()
assert(calls == 2 and controller.target == player, "replacement player must rebind")
roster = { "two", "one" }; sync()
assert(controller.slot == 2, "roster change must update follow slot")
duty.order = "hold"; fail = true
assert(not pcall(sync), "failure must reach caller")
fail = false; sync()
assert(controller.order == "hold", "failed update must retry")
duty.order = "follow"; fail = true
assert(not pcall(sync))
duty.order = "hold"; fail = false
local before = calls; sync()
assert(calls == before + 1, "reverting after partial failure must still synchronize")
local visible = 0
KnoxJavaBridge = { setNpcPartyVisible = function() visible = visible + 1 end }
sync(); sync()
assert(visible == 1, "late bridge must synchronize once")
duty = { mode = "base", baseId = "home" }
sync(); sync()
assert(baseCalls == 2, "supply progress must reconcile despite unchanged duty")
base = {}; sync()
assert(controller.base == base, "replacement base must bind")
print("Companion sync PASS stable=true player=true retry=true roster=true base=true bridge=true")
