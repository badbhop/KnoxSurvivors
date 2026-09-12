local w={now=0,blocked={},people={},otherVehicles={},wall=nil}
require=function() return true end
getTimestampMs=function() return w.now end
Vector3f={new=function() return {vx=0,vz=1,x=function(self) return self.vx end,z=function(self) return self.vz end} end}
instanceof=function(object,kind) return object.kind==kind end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local squares={}
function w.square(x,y,z)
    z=z or 0
    local key=x..":"..y..":"..z
    if squares[key]~=nil then return squares[key] end
    local sq={getX=function() return x end,getY=function() return y end,getZ=function() return z end,
        canStand=function() return true end,isOutside=function() return true end,
        isSolid=function() return w.blocked[x..":"..y]==true end,isSolidTrans=function() return false end,
        HasTree=function() return w.blocked[x..":"..y]=="tree" end,
        getMovingObjects=function() return list(w.people[x..":"..y] or {}) end}
    sq.isBlockedTo=function(_,other) return w.wall~=nil and w.wall(x,y,other:getX(),other:getY()) end
    squares[key]=sq;return sq
end
w.cell={getGridSquare=function(_,x,y,z)
    if w.unloaded~=nil and w.unloaded(x,y,z) then return nil end
    return w.square(x,y,z)
end,getVehicles=function()
    return {iterator=function() local i=0;return {hasNext=function() return i<#w.otherVehicles end,
        next=function() i=i+1;return w.otherVehicles[i] end} end}
end}
getCell=function() return w.cell end
KnoxSettings={enableExperimentalNpcDriving=function() return true end,npcDrivingSpeed=function() return 20 end}
ISTimedActionQueue={queues={}}
function ISTimedActionQueue.add(action)
    local queue=ISTimedActionQueue.queues[action.character] or {queue={}}
    ISTimedActionQueue.queues[action.character]=queue
    queue.queue[#queue.queue+1]=action
end
function ISTimedActionQueue.clear(character) ISTimedActionQueue.queues[character]={queue={}} end
ISPathFindAction={pathToVehicleSeat=function(_,character,vehicle,seat) return {character=character,seat=seat,kind="path"} end}
ISEnterVehicle={new=function(_,character,vehicle,seat) return {character=character,seat=seat,kind="enter"} end}
ISSwitchVehicleSeat={new=function(_,character,seat,from) return {character=character,seat=seat,from=from,kind="switch"} end}
ISCloseVehicleDoor=nil
ISExitVehicle={new=function(_,character) return {character=character,kind="exit"} end}
w.controls={resetCount=0,reset=function(self)
    self.resetCount=self.resetCount+1
    self.forward,self.backward,self.brake,self.steering=false,false,false,0
end}
w.controller={parkCount=0,getClientControls=function() return w.controls end,
    park=function(self) self.parkCount=self.parkCount+1;w.controls:reset() end}
w.character={health=100,kind="IsoGameCharacter",getVehicle=function(self) return self.vehicle end,
    isDead=function() return false end,getBodyDamage=function(self) return {getHealth=function() return self.health end} end}
w.vehicle={x=0,y=0,fx=0,fy=1,speed=0,driver=nil,
    getDriver=function(self) return self.driver end,getSeat=function(self,character) return self.driver==character and 0 or 1 end,
    isSeatOccupied=function(self) return self.driver~=nil end,isSeatInstalled=function() return true end,
    isEnterBlocked=function() return false end,getPassengerDoor=function() return nil end,
    isEngineRunning=function() return true end,isDriveable=function() return true end,
    getX=function(self) return self.x end,getY=function(self) return self.y end,
    getCurrentSpeedKmHour=function(self) return self.speed end,
    getSquare=function(self) return w.square(math.floor(self.x),math.floor(self.y)) end,
    getForwardVector=function(self,vector) vector.vx,vector.vz=self.fx,self.fy;return vector end,
    getScript=function() return {getExtents=function() return {x=function() return 2 end,z=function() return 4 end} end} end,
    getController=function() return w.controller end}
KnoxSurvivorRuntime={idForCharacter=function() return "driver" end,
    prepareVehicle=function()
        if KnoxCompanionVehicles~=nil then KnoxCompanionVehicles.cancel(w.character) end
        return true
    end}
function w.seatDriver() w.vehicle.driver=w.character;w.character.vehicle=w.vehicle;ISTimedActionQueue.clear(w.character) end
return w
