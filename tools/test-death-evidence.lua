local root=arg[1] or "."
package.path=root.."/mod/42/media/lua/client/?.lua;"..package.path
local data={}
ModData={getOrCreate=function(key) data[key]=data[key] or {}; return data[key] end}
Events={OnSave={Add=function() end},OnGameStart={Add=function() end}}
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
require "KS_Persistence"

local id="evidence"
KnoxPersistence.ensureSurvivorIdentity(id,"Evidence","Test",0)
assert(KnoxPersistence.setRecord(id,"record"),"record established")
assert(KnoxPersistence.setPlayerCompanion(id,"owner","follow",0),"player ownership established")
KnoxPersistence.setInventorySummary(id,"Base.Pistol=1;Base.Bullets9mm=10",8)
KnoxPersistence.setUnloadedSurvivalState(id,{virtualX=12,virtualY=34,virtualZ=0,health=42,bleedingParts=2,pain=7})
assert(KnoxPersistence.markSurvivorDead(id,10,"unloaded",{locationSource="loaded",corpseState="native_pending",x=50,y=60,z=0}),"first death persists")
local e=assert(KnoxPersistence.getSurvivorDeathEvidence(id))
assert(e.x==50 and e.y==60 and e.locationSource=="loaded" and e.corpseState=="native_pending","explicit exact coordinates win")
assert(e.ownerId=="owner" and e.ownerKind=="player" and e.dutyMode=="companion","ownership and duty snapshot")
assert(e.inventorySummary:find("Bullets9mm",1,true) and e.inventorySummaryAtHours==8 and e.health==42 and e.bleedingParts==2 and e.pain==7,"inventory and vitals snapshot")
assert(KnoxPersistence.markSurvivorCorpseCreated(id),"native pending advances")
assert(not KnoxPersistence.markSurvivorCorpseCreated(id) and KnoxPersistence.getSurvivorDeathEvidence(id).corpseState=="native_created","corpse state only advances once")
assert(KnoxPersistence.markSurvivorDead(id,99,"overwrite",{x=1,y=1,z=1}) and KnoxPersistence.getSurvivorDeathEvidence(id).x==50,"death evidence immutable")

local logical="logical"
KnoxPersistence.ensureSurvivorIdentity(logical,"Logical","Test",0)
KnoxPersistence.setUnloadedSurvivalState(logical,{virtualX=7,virtualY=8,virtualZ=0})
assert(KnoxPersistence.markSurvivorDead(logical,11,"unloaded"),"logical death persists")
e=assert(KnoxPersistence.getSurvivorDeathEvidence(logical))
assert(e.x==7 and e.locationSource=="logical" and e.corpseState=="logical_only" and not KnoxPersistence.markSurvivorCorpseCreated(logical),"logical evidence never claims a corpse")

local invalid="invalid"
KnoxPersistence.ensureSurvivorIdentity(invalid,"Invalid","Test",0)
KnoxPersistence.setUnloadedSurvivalState(invalid,{virtualX="bad",virtualY=8,virtualZ=0})
assert(KnoxPersistence.markSurvivorDead(invalid,12,"unloaded",{x=1/0,y=2,z=0}),"invalid-coordinate death persists")
e=assert(KnoxPersistence.getSurvivorDeathEvidence(invalid))
assert(e.x==nil and e.locationSource==nil,"invalid coordinates are not recorded")
assert(KnoxPersistence.getSurvivorDeathEvidence("missing")==nil,"legacy or missing death evidence stays nil")
print("Death evidence PASS immutable=true logical=true coordinates=true ownership=true")
