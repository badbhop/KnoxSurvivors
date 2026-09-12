require "KS_BaseStorage"
require "KS_SurvivorInventoryActions"
require "TimedActions/ISReadABook"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"

local Recreation = {}
KnoxBaseRecreation = Recreation
local ReadAction = ISReadABook:derive("KnoxNpcReadAction")
function ReadAction:perform()
    ISReadABook.perform(self)
    self.knoxReadingFinished = true
end

local function call(value, name, fallback, ...)
    if value == nil then return fallback end
    local method = value[name]
    if method == nil then return fallback end
    local ok, result = pcall(method, value, ...)
    if ok and result ~= nil then return result end
    return fallback
end

local function tagged(item, name)
    local tag = ItemTag ~= nil and ItemTag[name] or nil
    return tag ~= nil and call(item, "hasTag", false, tag)
end

function Recreation.readable(character, item)
    if not instanceof(item, "Literature") or call(character, "tooDarkToRead", true) then return false end
    if tagged(item, "UNINTERESTING") then return false end
    if CharacterTrait ~= nil and CharacterTrait.ILLITERATE ~= nil
        and call(character, "hasTrait", false, CharacterTrait.ILLITERATE)
        and not tagged(item, "PICTUREBOOK") and not tagged(item, "PICTURE") then return false end
    local data = call(item, "getModData", {})
    -- Print-media actions open a local player's image/map UI. Off-slot survivors
    -- can read ordinary literature and skill books, without borrowing player UI.
    if data.printMedia ~= nil then return false end
    if data.literatureTitle ~= nil and call(character, "isLiteratureRead", false, data.literatureTitle) then return false end
    local trained = call(item, "getSkillTrained", "")
    local skill = SkillBook ~= nil and SkillBook[trained] or nil
    if skill ~= nil then
        local level = call(character, "getPerkLevel", -100, skill.perk) + 1
        if level < call(item,"getLvlSkillTrained",math.huge)
            or level > call(item,"getMaxLevelTrained",-1) then return false end
    end
    local pages = call(item,"getNumberOfPages",0)
    if pages == 0 then return false end
    if pages > 0 and call(character,"getAlreadyReadPages",0,item:getFullType()) >= pages then return false end
    return true
end

local function scan(container, visitor, seen, depth)
    if container == nil or seen[container] or depth > 4 then return nil end
    seen[container] = true
    local items = container:getItems()
    for i = 0, items:size()-1 do
        local item = items:get(i)
        local result = visitor(item,container)
        if result ~= nil then return result end
        if call(item,"IsInventoryContainer",false) then
            result = scan(item:getInventory(),visitor,seen,depth+1)
            if result ~= nil then return result end
        end
    end
    return nil
end

function Recreation.find(character, base, available)
    if character == nil or base == nil or call(character,"getVehicle",nil) ~= nil then return nil end
    local origin,inventory=character:getCurrentSquare(),character:getInventory()
    if origin == nil or inventory == nil then return nil end
    local returning = scan(inventory,function(item,source)
        local loan=call(item,"getModData",{}).KnoxBaseBookLoan
        if type(loan)=="table" and loan.baseId==base.id and available(item,true) then
            return {item=item,source=source,baseId=base.id,sourcePolicy=loan.storageKey,
                borrowed=true,phase="return"}
        end
    end,{},0)
    if returning~=nil then return returning end
    if call(character,"tooDarkToRead",true) then return nil end
    local owned = scan(inventory,function(item,source)
        if available(item) and Recreation.readable(character,item) then
            return {item=item,source=source,baseId=base.id,phase="prepare"}
        end
    end,{},0)
    if owned ~= nil then return owned end
    for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
        if math.abs((tonumber(policy.z) or 0)-origin:getZ())<=2
            and ((tonumber(policy.x) or math.huge)-origin:getX())^2
                + ((tonumber(policy.y) or math.huge)-origin:getY())^2<=32*32 then
            local store=KnoxBaseStorage.resolvePolicy(policy)
            if store ~= nil then
                local plan=scan(store.container,function(item,source)
                    if available(item) and not call(item,"isFavorite",false) and Recreation.readable(character,item) then
                        return {item=item,source=source,sourcePolicy=policy.key,baseId=base.id,phase="prepare"}
                    end
                end,{},0)
                if plan ~= nil then return plan end
            end
        end
    end
    return nil
end

-- Find the physical owner again after interruptions or inventory management.
-- A carried bag is not the actor's root container and transfers must name it.
local function carriedSource(inventory,item)
    return scan(inventory,function(candidate,source)
        if candidate==item then return source end
    end,{},0)
end

local function assignedStore(base,key)
    for _,policy in ipairs(KnoxBaseStorage.policies(base)) do
        if policy.key==key then return KnoxBaseStorage.resolvePolicy(policy) end
    end
    return nil
end

local function nearby(character,store)
    local origin=character:getCurrentSquare()
    local square=store.square
    return origin~=nil and origin:getZ()==square:getZ()
        and (origin:getX()-square:getX())^2+(origin:getY()-square:getY())^2<=2
        and (origin==square or (origin.isSomethingTo~=nil and not origin:isSomethingTo(square)))
end

function Recreation.cancelAction(character,plan)
    local queue=ISTimedActionQueue.getTimedActionQueue(character)
    if plan.action~=nil and queue:indexOf(plan.action)~=-1 then
        if queue.current==plan.action then ISTimedActionQueue.clear(character)
        else plan.action:forceCancel(); queue:removeFromQueue(plan.action) end
    end
    plan.action=nil
end

local function moveToStore(plan,store,character,bridge,id,ticks,phase)
    local approach=AdjacentFreeTileFinder.Find(store.square,character)
    if approach==nil then return "failed","book_storage_unreachable" end
    local result=tostring(bridge:moveNpc(id,approach))
    if result:find("MOVE_STARTED",1,true)~=1 then return "failed","book_route:"..result end
    plan.phase,plan.moveStarted=phase,ticks
    return "working"
end

function Recreation.step(plan,character,base,bridge,id,ticks)
    if base==nil or base.id~=plan.baseId then return "failed","base_changed" end
    local inventory=character:getInventory()
    local busy=not character:getCharacterActions():isEmpty()
    if plan.phase=="borrow_move" or plan.phase=="return_move" then
        local result=tostring(bridge:tickNpc(id))
        if result=="Succeeded" then
            plan.phase=plan.phase=="borrow_move" and "prepare" or "return"
        elseif result:find("Failed",1,true) or ticks-(plan.moveStarted or ticks)>1800 then
            return "failed","book_route:"..result
        end
        return "working"
    end
    if plan.phase=="borrowing" then
        if busy then return "working" end
        if not inventory:contains(plan.item) or plan.source:contains(plan.item) then
            return "failed","book_transfer_not_completed"
        end
        plan.borrowed=plan.sourcePolicy~=nil
        if plan.borrowed then
            plan.item:getModData().KnoxBaseBookLoan={baseId=base.id,storageKey=plan.sourcePolicy}
        end
        plan.phase,plan.action="prepare",nil
    end
    if plan.phase=="prepare" then
        if busy then return "failed","book_action_busy" end
        if not inventory:contains(plan.item) then
            if not plan.source:contains(plan.item) then return "failed","book_missing" end
            if plan.sourcePolicy~=nil then
                local store=assignedStore(base,plan.sourcePolicy)
                if store==nil then return "failed","book_storage_unavailable" end
                if not nearby(character,store) then return moveToStore(plan,store,character,bridge,id,ticks,"borrow_move") end
            end
            local action,reason=KnoxInventoryActions.queueTransfer(character,plan.item,plan.source,inventory,nil)
            if action==nil then return "failed",reason end
            plan.action,plan.phase=action,"borrowing"
            return "working"
        end
        if not Recreation.readable(character,plan.item) then
            plan.phase="return"
            return "working"
        end
        local action=ReadAction:new(character,plan.item)
        ISTimedActionQueue.add(action)
        if ISTimedActionQueue.getTimedActionQueue(character):indexOf(action)==-1 then
            return "failed","reading_not_queued"
        end
        plan.phase,plan.action,plan.readStarted="reading",action,ticks
        return "working"
    end
    if plan.phase=="reading" then
        if busy and ticks-(plan.readStarted or ticks)<3600 then return "working" end
        plan.completed=plan.action~=nil and plan.action.knoxReadingFinished==true
        Recreation.cancelAction(character,plan)
        plan.phase="return"
        return "working"
    end
    if plan.phase=="return" then
        if busy then return "working" end
        if not plan.borrowed then return "done",plan.completed and "reading_completed" or "reading_paused" end
        local source=carriedSource(inventory,plan.item)
        if source==nil then return "failed","borrowed_book_missing" end
        local store=assignedStore(base,plan.sourcePolicy)
        if store==nil then
            local main=KnoxBaseStorage.mainPolicy(base)
            if main~=nil then store=KnoxBaseStorage.resolvePolicy(main) end
        end
        if store==nil then return "done","book_retained_storage_unavailable" end
        if not nearby(character,store) then return moveToStore(plan,store,character,bridge,id,ticks,"return_move") end
        local action,reason=KnoxInventoryActions.queueTransfer(character,plan.item,source,store.container,nil)
        if action==nil then return "done","book_retained:"..tostring(reason) end
        plan.phase,plan.action,plan.returnContainer="returning",action,store.container
        return "working"
    end
    if plan.phase=="returning" then
        if busy then return "working" end
        if carriedSource(inventory,plan.item)~=nil or not plan.returnContainer:contains(plan.item) then
            return "failed","book_return_not_completed"
        end
        plan.item:getModData().KnoxBaseBookLoan=nil
        return "done",plan.completed and "reading_completed" or "reading_paused"
    end
    return "failed","unknown_recreation_phase"
end
return Recreation
