local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local printed = {}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local log = dofile(rootPath .. "/mod/42/media/lua/client/KS_DebugLog.lua")
assert(log ~= nil and log.log ~= nil and log.once ~= nil and log.verbose ~= nil)

-- Failures/transitions: 1st + every 10th only.
assert(log.log("barricade", "worker-1", "queue_failed", { reason = "x" }) == true)
assert(#printed == 1)
for _ = 1, 8 do assert(log.log("barricade", "worker-1", "queue_failed", { reason = "x" }) == false) end
assert(#printed == 1)
assert(log.log("barricade", "worker-1", "queue_failed", { reason = "x" }) == true)
assert(#printed == 2)

-- Verbose gated behind ShowDeveloperDiagnostics + tick throttle.
KnoxSettings = { showDeveloperDiagnostics = function() return false end }
assert(log.verbose("jobs", "worker-1", "poll", nil, 100, 600) == false)
KnoxSettings = { showDeveloperDiagnostics = function() return true end }
assert(log.verbose("jobs", "worker-1", "poll", nil, 100, 600) == true)
assert(log.verbose("jobs", "worker-1", "poll", nil, 200, 600) == false)
assert(log.verbose("jobs", "worker-1", "poll", nil, 800, 600) == true)

-- Permanent sandbox switch: the whole structured log honours the existing
-- Developer-page diagnostics setting. Missing settings default ON.
KnoxSettings = nil
assert(log.diagnosticsEnabled() == true)
assert(log.log("gate", "worker-9", "probe", nil) == true)
KnoxSettings = { showDeveloperDiagnostics = function() return false end }
assert(log.diagnosticsEnabled() == false)
assert(log.log("gate", "worker-9", "probe2", nil) == false)
assert(log.once("gate", "worker-9", "snapshot", nil) == false)
KnoxSettings = { showDeveloperDiagnostics = function() return true end }
assert(log.diagnosticsEnabled() == true)
assert(log.log("gate", "worker-9", "probe3", nil) == true)
assert(log.once("gate", "worker-9", "snapshot2", nil) == true)

-- Every failure verdict carries a one-line why; unknown codes fall back.
assert(log.brief ~= nil, "brief lookup must exist")
assert(log.brief("timeout") ~= "timeout" and #log.brief("timeout") > 10)
assert(log.brief("test_zombie_killed_without_damage") ~= "test_zombie_killed_without_damage")
assert(log.brief("native_task_completion_timeout") ~= "native_task_completion_timeout")
assert(log.brief("no_valid_raid_proposal") ~= "no_valid_raid_proposal")
assert(log.brief("some_future_code_xyz") == "some_future_code_xyz")
assert(log.brief(nil) ~= nil)

print = realPrint
print("Debug log PASS throttle=true verbose_gate=true briefs=true")
