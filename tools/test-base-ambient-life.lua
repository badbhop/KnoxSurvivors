local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(source:find("function Controller:beginAmbientBaseRest", 1, true),
    "base residents need an explicit ambient rest decision")
assert(source:find("ISRestAction:new", 1, true)
    and source:find("ISSitOnGround:new", 1, true),
    "ambient base life must reuse vanilla furniture and ground sitting actions")
assert(source:find('"BASE_AMBIENT_REST"', 1, true)
    and source:find("BASE_AMBIENT_REST_TICKS", 1, true),
    "ambient rest must be bounded and independently represented")
assert(source:find('self.activeDecision == "base_ambient_rest"', 1, true)
    and source:find("self:leaveRecoveryPosture()", 1, true),
    "ambient rest must release its vanilla posture when it finishes")
assert(source:find("function Controller:beginAmbientSnack", 1, true)
    and source:find('self.activeDecision = "base_ambient_snack"', 1, true)
    and source:find('self.state = "TIMED_ACTION"', 1, true)
    and source:find("self.selfCareIntent = intent", 1, true),
    "ambient snacks must consume real supplies through the shared self-care completion path")
assert(source:find("function Controller:beginAmbientSocial", 1, true)
    and source:find("faceThisObject", 1, true)
    and source:find("self.nextSocialAt = ticks + 1800", 1, true),
    "ambient socials must face a nearby resident and respect a shared cooldown")
assert(source:find("function Controller:beginAmbientWatch", 1, true)
    and source:find('self.activeDecision = "base_ambient_watch"', 1, true)
    and source:find('instanceof(object, "IsoTelevision")', 1, true)
    and source:find("self.nextWatchAt = ticks + 3600", 1, true),
    "ambient television must face a nearby in-base set and respect a cooldown")
assert(source:find("function Controller:setTelevisionPower", 1, true)
    and source:find("function Controller:isTelevisionOn", 1, true)
    and source:find("function Controller:releaseWatch", 1, true)
    and source:find("deviceData:setIsTurnedOn(on == true)", 1, true)
    and source:find("deviceData:canBePoweredHere()", 1, true)
    and source:find("function Controller:isTelevisionPowered", 1, true)
    and source:find("self:setTelevisionPower(set.object, true)", 1, true)
    and source:find("self:releaseWatch()", 1, true),
    "watchers must switch a dark set on and back off, never touching a set they did not power")
assert(source:find('if phase <= 9 then return "tv" end', 1, true),
    "scheduled recreation must include television in company time")
assert(source:find('if assignment == "patrol" or assignment == "guard" then', 1, true)
    and source:find('preference = assignment', 1, true),
    "patrol/guard schedule windows must bias election toward watch tasks")
assert(source:find('self.nextThink = ticks + 90', 1, true)
    and source:find('self.nextExplorationSearch = ticks + EMPTY_SEARCH_COOLDOWN_TICKS', 1, true),
    "settled followers must think less often and throttle empty loot peeks")
assert(source:find('function Controller:maintainBaseLights', 1, true)
    and source:find('function Controller:releaseLights', 1, true)
    and source:find('instanceof(object, "IsoLightSwitch")', 1, true)
    and source:find('found:setActivated(true)', 1, true)
    and source:find('self.character:tooDarkToRead()', 1, true),
    "idle residents must light dark rooms and switch them back off")
assert(source:find("function Controller:beginFollowerCompany", 1, true)
    and source:find('sayDialogue(self.character, self.id, "player_talk", ticks, 2400)', 1, true)
    and source:find("self:beginFollowerCompany(ticks, self.companionTarget, true)", 1, true)
    and source:find("self:beginFollowerCompany(ticks, self.groupLeader, false)", 1, true),
    "idle followers must keep company: face a settled leader, player-bound chatter only")
assert(source:find('if self.companionOrder == "relax" then', 1, true)
    and source:find("if not self:beginAmbientSnack(ticks) then", 1, true),
    "relax orders must snack from the hip pocket before resting")
assert(source:find("function Controller:beginFollowerHygiene", 1, true)
    and source:find("KnoxBaseHygiene.beginNear(self.character, 16, self.bridge, self.id, ticks)", 1, true)
    and source:find('if self:beginFollowerHygiene(ticks) then return end', 1, true),
    "idle followers must wash at nearby water through the shared hygiene machinery")
assert(source:find("self.leisureBreakDue = true", 1, true)
    and source:find("self.consecutiveAutoTasks", 1, true)
    and source:find("local forceLeisure = false", 1, true),
    "consecutive automatic successes must earn one ambient leisure round instead of another claim")

local dialoguePath = rootPath .. "/mod/42/media/lua/client/KS_SurvivorDialogue.lua"
local dialogueFile = assert(io.open(dialoguePath, "r"))
local dialogue = dialogueFile:read("*a")
dialogueFile:close()
assert(dialogue:find("base_social = {", 1, true)
    and dialogue:find("base_snack = {", 1, true),
    "ambient company needs its own dialogue banks")

print("Base ambient life PASS vanilla_sit=true bounded=true cleanup=true snack=true social=true tv=true tv_power=true leisure_break=true follower_company=true relax_snack=true follower_hygiene=true steady_follow=true room_lights=true")
