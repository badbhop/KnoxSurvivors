local root=arg[1] or "."
package.path=root.."/mod/42/media/lua/client/?.lua;"..package.path
local data={}
ModData={getOrCreate=function(key) data[key]=data[key] or {};return data[key] end}
Events={OnSave={Add=function() end},OnGameStart={Add=function() end}}
local hours=0
getGameTime=function() return {getWorldAgeHours=function() return hours end} end
SandboxVars={KnoxSurvivors={WorldPopulation=16,InitialGroupChance=100,InitialGroupMaxSize=4,
    NPCFactionMinimumMembers=4,AllowNPCFactions=true}}
local points={}
for i=0,19 do points[#points+1]={posX=100+i%5*6,posY=100+math.floor(i/5)*6,posZ=0} end
points[#points+1]={posX=500,posY=100,posZ=0}
package.preload.SpawnRegions=function() return true end
SpawnRegionMgr={getSpawnRegions=function() return {{name="Town",points={unemployed=points}}} end}
require "KS_Persistence"
local p=KnoxPersistence
local population=require "KS_WorldPopulation"
local cohesion=require "KS_GroupCohesion"
local simulation=require "KS_UnloadedSurvival"
_G.KnoxOffscreenStoriesDisabled = true
local player={getCurrentSquare=function() return {getX=function() return 100 end,
    getY=function() return 100 end,getZ=function() return 0 end} end}
local outcome=population.maintain(0,{players={player},initialAllocationBudget=48})
assert(outcome.status=="initialized")
local group
for _,id in ipairs(p.getLivingWorldSurvivorIds()) do
    local candidate=p.getTravelGroupFor(id)
    if candidate~=nil and #candidate.memberIds==4 then group=candidate;break end
end
assert(group~=nil and group.factionId==nil, "normal initialization permits a four-person group without fabricating a faction")
for _,id in ipairs(group.memberIds) do assert(p.getRecord(id)==nil, "test uses never-materialized world survivors") end
assert(population.advanceOriginTravel(group.leaderId,0.5))
assert(group.factionId==nil, "a new group still needs actual shared survival time")
assert(population.advanceOriginTravel(group.leaderId,1.1))
local faction=assert(p.getFactionForSurvivor(group.leaderId))
assert(#faction.memberIds==4 and group.factionId==faction.id)
local follower=group.memberIds[2]
local evidence=p.getRelationship(group.leaderId,follower).nearbyHours
population.advanceOriginTravel(group.leaderId,1.1)
assert(p.getRelationship(group.leaderId,follower).nearbyHours==evidence, "replaying the clock cannot duplicate cohesion")
for _,id in ipairs(group.memberIds) do assert(p.getRecord(id)==nil, "formation creates no body, inventory or supplies") end
-- Stored survivors mature through the existing physiology/movement scheduler.
local ids={"a","b","c","d"}
for i,id in ipairs(ids) do
    p.setRecord(id,"record-"..id)
    p.setUnloadedSurvivalState(id,{hunger=.1,thirst=.1,health=100,fatigue=.1,endurance=.9,lastHours=0,
        virtualX=100,virtualY=100+i*3,virtualZ=0,status="hibernated"})
end
local stored=assert(p.createTravelGroup(ids,0))
KnoxSurvivorNeeds={sleepRequired=function() return true end}
KnoxJavaBridge={consumeNpcRecordSupply=function() return nil end}
simulation.advanceAll({"a"},1)
assert(stored.factionId==nil, "a partially active cohort cannot receive offscreen shared-time credit")
SandboxVars.KnoxSurvivors.AllowNPCFactions=false
simulation.advanceAll({},2)
assert(stored.factionId==nil, "disabled faction creation stays disabled")
SandboxVars.KnoxSurvivors.AllowNPCFactions=true
simulation.advanceAll({},2.1)
assert(stored.factionId~=nil, "stored cohesive group can form when factions are enabled")
local farIds={"e","f","g","h"};local members={}
for i,id in ipairs(farIds) do
    p.setRecord(id,"record-"..id)
    members[#members+1]={id=id,state={virtualX=i*100,virtualY=100,virtualZ=0,lastHours=0}}
end
local separated=assert(p.createTravelGroup(farIds,0))
local before=cohesion.snapshot(members)
for _,member in ipairs(members) do member.state.lastHours=10 end
cohesion.record(separated,before,members,10)
assert(separated.factionId==nil, "distant members do not gain invented shared experience")
assert(p.getRelationship("e","f")==nil or p.getRelationship("e","f").nearbyHours==0)
print("Faction development PASS opening_cohort=true earned_formation=true origin_travel=true stored_survival=true no_duplicate_time=true active_boundary=true settings=true separation=true")

local readiness=p.getFactionReadiness(separated.id,4)
assert(readiness.reason=="requires_shared_survival" and readiness.members==4
    and readiness.sharedMembers==1 and #readiness.missingShared==3)
assert(separated.factionId==nil, "reading formation diagnostics cannot create a faction")
local logs={};local oldPrint=print
print=function(line) logs[#logs+1]=line end
require=function() return true end
Events.OnFillWorldObjectContextMenu={Add=function() end}
KnoxActivityFeed={event=function() end}
dofile(root.."/mod/42/media/lua/client/KS_DeveloperTools.lua")
KnoxDeveloperTools.printFactionReadiness()
print=oldPrint
local found=false
for _,line in ipairs(logs) do
    if line:find("group="..separated.id.." ",1,true) then
        assert(line:find("formation=requires_shared_survival",1,true) and line:find("members=4 required=4 shared=1",1,true))
        found=true
    end
end
assert(found, "developer diagnostics explain why the actual group has not formed")
print("Faction diagnostics PASS read_only=true shared_evidence=true")
