local root = arg[1] or "."
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path
for _, module in ipairs({ "KS_Persistence", "KS_SurvivorRuntime", "KS_ActivityFeed", "KS_Settings",
    "KS_CompanionVehicles", "KS_OrderCatalog", "KS_OrderSignals" }) do
    package.preload[module] = function() return true end
end

local trust, meetings, hostile = 30, 0, false
local nextSocial, nextTalk = {}, 0
local square = { getX = function() return 1 end, getY = function() return 1 end,
    getZ = function() return 0 end }
local character = { getCurrentSquare = function() return square end,
    isDead = function() return false end }
local player = { getCurrentSquare = function() return square end,
    isDead = function() return false end }
local emotes = {}

KnoxSettings = { enabled = function() return true end,
    companionLimit = function() return 8 end,
    useReputation = function() return true end }
KnoxPersistence = {
    ensurePlayerId = function() return "player" end,
    isSurvivorAlive = function() return true end,
    isSurvivorHostileToPlayer = function() return hostile end,
    setSurvivorHostileToPlayer = function(_, _, value) hostile = value == true; return true end,
    isIndependentSurvivor = function() return true end,
    getTravelGroupFor = function() return nil end,
    getFactionForSurvivor = function() return nil end,
    getCompanionIds = function() return {} end,
    getPlayerSocialDisposition = function() return "join" end,
    getPlayerRelationship = function()
        return { trust = trust, meetings = meetings, nextTalkHours = nextTalk,
            nextSocialHours = nextSocial }
    end,
    recordPlayerSocialEvent = function() end,
    recordPlayerSocialAct = function(_, _, act, delta, cooldown, now)
        if (nextSocial[act] or 0) > now then return { trust = trust }, "cooldown" end
        nextSocial[act] = now + cooldown
        nextTalk = now
        meetings = meetings + 1
        trust = math.max(0, math.min(100, trust + delta))
        return { trust = trust, meetings = meetings }, "recorded"
    end,
    setPlayerCompanion = function() return true, "saved" end,
    getSurvivorIdentity = function() return { forename = "Test", surname = "Person" } end,
}
KnoxSurvivorRuntime = {
    getCharacter = function() return character end,
    notifyDutyChanged = function() end,
    beginPlayerConversation = function() return true end,
    endPlayerConversation = function() end,
}
KnoxActivityFeed = { speak = function() end, event = function() end,
    reputation = function() end }
KnoxOrderCatalog = { isPrimaryOrder = function() return true end, normalize = function(v) return v end }
KnoxOrderSignals = { order = function(_, kind) emotes[#emotes + 1] = kind; return true end,
    play = function() return true end }
getGameTime = function() return { getWorldAgeHours = function() return 8 end } end

local service = dofile(root .. "/mod/42/media/lua/client/KS_CompanionService.lua")

-- Friendly acts build trust with emotes, no cooldown while neutral.
assert(service.socialAct(player, "candidate", "joke"))
assert(trust == 34 and meetings == 1, "joke builds trust")
assert(emotes[#emotes] == "joke", "joke plays its emote")
assert(service.socialAct(player, "candidate", "compliment"))
assert(trust == 39, "compliment stacks without a talk timer while neutral")
assert(service.socialAct(player, "candidate", "offer_gift"))
assert(trust == 47, "gifts build more trust")

-- Per-act cooldowns still apply on repeat.
local ok, reason = service.socialAct(player, "candidate", "offer_gift")
assert(not ok and reason == "cooldown", "gifts keep their own cooldown")

-- Hostile acts burn trust and can turn the survivor.
trust = 30
assert(service.socialAct(player, "candidate", "insult"))
assert(trust == 18, "insults burn trust")
assert(service.socialAct(player, "candidate", "slap") == false, "slap at low trust turns hostile")
assert(hostile, "repeated hostility turns the survivor hostile")

-- Reputation gates recruiting while on, ignored while off.
hostile, trust = false, 10
local ready, why = service.canRecruit(player, "candidate")
assert(not ready and why == "low_reputation", "low trust blocks recruiting with reputation on")
KnoxSettings.useReputation = function() return false end
assert(service.canRecruit(player, "candidate"), "reputation off restores contact-rule recruiting")

print("Social acts PASS trust=true emotes=true cooldowns=true reputation_gate=true")
