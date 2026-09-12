local root=arg[1] or "."
require=function() return true end
local now, enabled, busy=0,true,false
getTimestampMs=function() return now end
KnoxSettings={orderGesturesEnabled=function() return enabled end}
local function actor(x)
    local result={events={},state="idle",x=x}
    function result:getCurrentSquare() return {getX=function() return self.x end,getY=function() return 0 end,getZ=function() return 0 end} end
    function result:getCharacterActions() return {isEmpty=function() return not busy end} end
    function result:getCurrentStateName() return self.state end
    function result:playEmote(kind) self.events[#self.events+1]=kind end
    return result
end
local player,npc=actor(0),actor(2)
local signals=dofile(root.."/mod/42/media/lua/client/KS_OrderSignals.lua")
assert(signals.order(player,"follow",npc))
assert(player.events[1]=="followme" and npc.events[1]=="yes", "accepted follow order has leader and recipient gestures")
assert(not signals.order(player,"follow",npc) and #npc.events==1, "party orders coalesce gestures per actor")
now=3000
assert(signals.order(player,"guard",npc) and player.events[2]=="stop")
now=6000
busy=true
assert(not signals.order(player,"go_to",npc), "native work cannot be replaced with gestures")
busy=false
player.state="ClimbOverFenceState"
assert(not signals.order(player,"follow",nil), "traversal retains animation ownership")
player.state="SwipeStatePlayer"
assert(not signals.order(player,"follow",nil), "combat retains animation ownership")
player.state="idle"
enabled=false
assert(not signals.order(player,"follow",npc), "player customization suppresses signals")
enabled=true
npc.x=100
local npcCount=#npc.events
assert(signals.order(player,"patrol_area",npc) and #npc.events==npcCount, "remote NPCs do not nod across the map")
print("Order gestures PASS mapping=true acknowledgement=true cooldown=true ownership=true setting=true")

now=9000
local accepted=true
KnoxPersistence={ensurePlayerId=function() return "player" end,updateCompanionOrder=function() return accepted end}
KnoxSurvivorRuntime={notifyDutyChanged=function() end,getCharacter=function() return npc end}
KnoxActivityFeed={speak=function() end}
KnoxOrderCatalog={isPrimaryOrder=function() return true end}
getGameTime=function() return {getWorldAgeHours=function() return 1 end} end
local service=dofile(root.."/mod/42/media/lua/client/KS_CompanionService.lua")
local events=#player.events
accepted=false
assert(not service.command(player,"npc","follow") and #player.events==events,
    "rejected orders do not play a success gesture")
accepted=true
assert(service.command(player,"npc","follow") and player.events[#player.events]=="followme",
    "real accepted command dispatches the native gesture")
