require "KS_Settings"
local Signals = rawget(_G, "KnoxOrderSignals") or {}
_G.KnoxOrderSignals = Signals
local cooldowns = setmetatable({}, {__mode="k"})
local EMOTES = {follow="followme",hold="stop",relax="signalok",guard="stop",
    patrol="moveout",patrol_area="moveout",go_to="moveout",return_to_base="comehere",
    scavenge="moveout",investigate_building="moveout",base_supply="comehere",
    loot_area="moveout",loot_building="moveout",loot_corpses="moveout",
    find_food="moveout",find_water="moveout",find_medical="moveout",
    find_weapon="moveout",find_tools="moveout",find_wood="moveout",find_materials="moveout",
    find_clothing="moveout",find_ammo="moveout",clean_inventory="signalok",
    farming="signalok",woodwork="signalok",hauling="signalok",
    repair="signalok",haul_corpse="signalok",sort_depot="signalok",
    auto="signalok",rest="signalok",job="signalok",
    allow_climbing="signalok",disallow_climbing="signalok",
    allow_doors="signalok",disallow_doors="signalok",
    enable_autoloot="moveout",disable_autoloot="signalok",
    formation="moveout",combat_stance="stop",weapon_preference="signalok",
    enter_vehicle="comehere",exit_vehicle="signalok",dismiss="signalok",
    signalok="signalok",
    talk="wavehi",joke="clap",compliment="thumbsup",funny_face="shrug",
    insult="insult",slap="thumbsdown"}
local function call(actor, method)
    local ok,value=pcall(function() return actor[method](actor) end)
    return ok and value or nil
end
function Signals.play(actor, emote)
    if actor==nil or actor.playEmote==nil then return false end
    local settings=rawget(_G,"KnoxSettings")
    if settings~=nil and settings.orderGesturesEnabled~=nil and not settings.orderGesturesEnabled() then return false end
    if call(actor,"isDead")==true or call(actor,"getVehicle")~=nil or call(actor,"isAiming")==true then return false end
    local actions=call(actor,"getCharacterActions")
    if actions==nil or not actions:isEmpty() then return false end
    local state=string.lower(tostring(call(actor,"getCurrentStateName") or "")
        .." "..tostring(call(actor,"getCurrentActionContextStateName") or ""))
    for _,busy in ipairs({"climb","attack","swipe","hitreact","grappl","fall"}) do
        if state:find(busy,1,true) then return false end
    end
    local now=getTimestampMs~=nil and tonumber(getTimestampMs()) or nil
    if now==nil then now=getGameTime~=nil and getGameTime():getWorldAgeHours()*3600000 or 0 end
    local previous=cooldowns[actor]
    if previous~=nil and now>=previous and now-previous<3000 then return false end
    local success=pcall(function() actor:playEmote(emote) end)
    if success then cooldowns[actor]=now end
    return success
end
function Signals.order(player, kind, survivor)
    local emote=EMOTES[kind]
    if emote==nil then return false end
    local played=Signals.play(player,emote)
    if survivor~=nil and survivor~=player then
        local first,second=call(player,"getCurrentSquare"),call(survivor,"getCurrentSquare")
        if first~=nil and second~=nil and first:getZ()==second:getZ()
            and (first:getX()-second:getX())^2+(first:getY()-second:getY())^2<=49 then
            Signals.play(survivor,"yes")
        end
    end
    return played
end

-- Autonomous leaders use the same readable gestures as player-issued orders.
-- Only nearby loaded followers acknowledge; the group objective remains the
-- durable authority and this helper never changes movement or task state.
function Signals.group(leader, members, kind)
    local emote = EMOTES[kind]
    if emote == nil or not Signals.play(leader, emote) then return false end
    local first = leader ~= nil and call(leader, "getCurrentSquare") or nil
    for _, member in ipairs(members or {}) do
        if member ~= nil and member ~= leader then
            local second = call(member, "getCurrentSquare")
            if first ~= nil and second ~= nil and first:getZ() == second:getZ()
                and (first:getX() - second:getX()) ^ 2
                    + (first:getY() - second:getY()) ^ 2 <= 49 then
                Signals.play(member, "yes")
            end
        end
    end
    return true
end
return Signals
