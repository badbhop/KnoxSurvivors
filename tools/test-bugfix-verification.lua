local root = arg[1] or "."
require = function() return true end

-- 1. Firearms use the exact vanilla attack hook; Java must clear stale shove
-- mode so that hook enters its ranged branch.
local fh = assert(io.open(root .. "/mod/42/media/lua/client/KS_FirearmSupport.lua", "r"))
local fsrc = fh:read("*a"); fh:close()
assert(not string.find(fsrc, "character,\n        0,\n        gun", 1, true),
    "fireNative must not hardcode chargeDelta 0")
assert(string.find(fsrc, "getUseChargeDelta", 1, true),
    "fireNative retains the primed combat charge for native attack input")
local jh = assert(io.open(root .. "/java/src/main/java/com/knoxsurvivors/npc/KnoxCombatController.java", "r"))
local jsrc = jh:read("*a"); jh:close()
assert(string.find(jsrc, 'getMethod("setDoShove", boolean.class)', 1, true)
    and string.find(jsrc, ".invoke(body, !ranged && unarmedCombat);", 1, true),
    "armed and ranged attacks must clear stale native shove mode")

-- 2. Barricade execution must use base storage, not inventory-only.
local bh = assert(io.open(root .. "/mod/42/media/lua/client/KS_BaseBarricades.lua", "r"))
local bsrc = bh:read("*a"); bh:close()
assert(string.find(bsrc, "function Barricades.queueAction(character, target, base)", 1, true),
    "queueAction must accept base for storage lookup")
local ch = assert(io.open(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r"))
local csrc = ch:read("*a"); ch:close()
assert(string.find(csrc, "queueAction(\n                    self.character,\n                    target,\n                    self.base", 1, true),
    "controller must pass base into barricade queueAction")

-- 3. Ignore-mode supplies fall back to worker inventory when no storage assigned.
local sh = assert(io.open(root .. "/mod/42/media/lua/client/KS_JobTestSupplies.lua", "r"))
local ssrc = sh:read("*a"); sh:close()
assert(string.find(ssrc, "worker", 1, true) and string.find(ssrc, "getInventory", 1, true),
    "ensure must fall back to worker inventory")

-- 4. Road staging resume must consult roadFinalById, not just self field.
assert(string.find(csrc, "roadFinalById[self.id] ~= nil", 1, true),
    "Succeeded guard must check roadFinalById stash")
assert(string.find(csrc, "COMBAT_RETARGET_SCORE_MARGIN = 72", 1, true),
    "retarget margin must be above footwork noise")
assert(string.find(csrc, "FORMATION_ARRIVAL_TOLERANCE_SQUARED = 1", 1, true),
    "formation arrival must tolerate 1 tile")

-- 5. Spouse corrections must persist via recapture.
local sp = assert(io.open(root .. "/mod/42/media/lua/client/KS_SpouseStart.lua", "r"))
local spsrc = sp:read("*a"); sp:close()
assert(string.find(spsrc, "captureActiveSurvivor(start.id)", 1, true),
    "spouse surname/gender fix must be recaptured")

-- 6. Zone confirm must refresh highlights after save.
local zh = assert(io.open(root .. "/mod/42/media/lua/client/KS_BaseZoneSelector.lua", "r"))
local zsrc = zh:read("*a"); zh:close()
local yesPos = string.find(zsrc, 'button.internal == "YES"', 1, true)
assert(yesPos, "confirm block missing")
local afterYes = string.sub(zsrc, yesPos, yesPos + 1200)
assert(string.find(afterYes, "KnoxBaseHighlights.refresh", 1, true),
    "highlights must refresh after YES save")

print("Bugfix verification PASS tracer=true barricade_base=true supply_fallback=true road_guard=true spouse_recapture=true highlights_refresh=true")
