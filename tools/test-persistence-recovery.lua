local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path
local nested = { item = "native-equipment-reference" }
for _ = 1, 9 do nested = { child = nested } end
local data = {
    schemaVersion = 17,
    survivors = { saved = { id = "saved", record = "native-inventory-and-wounds",
        customHistory = nested, alive = true } },
    camps = { camp = { memberIds = { "saved" } } },
    awayTeams = { team = { memberIds = { "saved" } } },
    relationships = { pair = { trust = 31 } },
    knoxEvents = { records = { event = { survivorId = "saved" } } },
    population = { initialized = true },
    nextWorldSurvivorId = 42,
}
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
assert(loadfile(projectRoot .. "/mod/42/media/lua/client/KS_Persistence.lua"))()
local P = KnoxPersistence
assert(P.getRecord("saved") == "native-inventory-and-wounds")
local backup = data.preMigrationBackup
assert(backup.version == 2 and backup.fromSchema == 17)
local original = backup.snapshot.survivors.saved.customHistory
for _ = 1, 9 do original = assert(original.child, "backup truncated nested history") end
assert(original.item == "native-equipment-reference")
data.survivors.saved.record = "changed"
data.camps.camp.memberIds[1] = "changed"
data.awayTeams = {}
data.relationships.pair.trust = 0
data.knoxEvents.records = {}
data.nextWorldSurvivorId = 99
data.postMigrationOnly = true
assert(P.restorePreMigrationBackup())
assert(data.schemaVersion == 17 and data.nextWorldSurvivorId == 42
    and data.postMigrationOnly == nil, "restore must include schema, counters and absent fields")
assert(data.camps.camp.memberIds[1] == "saved" and data.awayTeams.team.memberIds[1] == "saved"
    and data.relationships.pair.trust == 31 and data.knoxEvents.records.event.survivorId == "saved",
    "restore must keep survivor membership and related world domains coherent")
assert(P.getRecord("saved") == "native-inventory-and-wounds" and data.schemaVersion == 18,
    "the first read must normalize restored data instead of reusing cached migration state")
assert(data.preMigrationBackup == backup, "recovery must retain the original backup")
data.survivors.saved.customHistory.child = nil
assert(P.restorePreMigrationBackup())
assert(data.survivors.saved.customHistory.child ~= nil, "restored tables must not alias the backup")
-- Old partial backups remain readable, without claiming to recover domains
-- or nested data which the original writer never saved.
data.preMigrationBackup = { survivors = { legacy = { record = "legacy-record" } } }
assert(P.restorePreMigrationBackup() and P.getRecord("legacy") == "legacy-record")
print("Persistence recovery PASS nested=true domains=true cache=true legacy=true")
