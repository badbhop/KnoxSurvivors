require "KS_ActivityFeed"
require "KS_Settings"

local Dialogue = rawget(_G, "KnoxSurvivorDialogue") or {}
_G.KnoxSurvivorDialogue = Dialogue

local DEFAULT_COOLDOWN = 1800
local GLOBAL_COOLDOWN = 240
local states = {}

local BANKS = {
    roam_building = {
        "I'm checking that building.", "Might be something useful in there.",
        "Let's see what they left behind.",
    },
    roam_area = {
        "I'm moving on.", "Nothing keeping me here.", "I'll check farther out.",
    },
    search = {
        "Let me check this.", "I'll have a quick look.", "See what's left.",
    },
    loot_found = {
        "This'll help.", "Worth carrying.", "We can use this.",
    },
    no_supplies = {
        "Nothing useful here.", "Place is picked clean.", "No luck here.",
    },
    share_supply = {
        "Take this. I have enough.",
        "Here. You need this more than I do.",
        "I've got a spare. Take it.",
    },
    need_food = {
        "I need to find something to eat.", "I'm running low on food.",
    },
    need_water = {
        "I need water soon.", "I'm getting thirsty.",
    },
    need_medical = {
        "I need something for this wound.", "I could use medical supplies.",
    },
    rest = {
        "I need a minute.", "I'm catching my breath.", "Let me rest a little.",
    },
    regroup = {
        "Wait up.", "Stay together.", "I'm coming back to you.",
    },
    combat = {
        "Contact!", "Got one here!", "Watch yourself!",
    },
    flee = {
        "Too many—move!", "We need to get clear!", "Fall back!",
    },
    base_work = {
        "I'll get this handled.", "I've got work to do.", "I'll take care of it.",
    },
    camp = {
        "I'm staying close for a while.", "This place will do for now.",
    },
}

local function stableIndex(id, event, ticks, count)
    local text = tostring(id or "survivor") .. ":" .. tostring(event)
        .. ":" .. tostring(math.floor((tonumber(ticks) or 0) / 300))
    local hash = 23
    for index = 1, #text do
        hash = (hash * 37 + string.byte(text, index)) % 2147483647
    end
    return (hash % count) + 1
end

local function enabled()
    return KnoxSettings == nil or KnoxSettings.showSurvivorSpeech == nil
        or KnoxSettings.showSurvivorSpeech()
end

function Dialogue.sayLines(character, survivorId, event, lines, ticks, cooldown)
    if character == nil or type(lines) ~= "table" or #lines == 0 or not enabled() then
        return false, "unavailable"
    end
    local id = tostring(survivorId or "survivor")
    local now = math.max(0, tonumber(ticks) or 0)
    local state = states[id] or { nextGlobal = 0, events = {} }
    states[id] = state
    if now < (state.nextGlobal or 0) or now < (state.events[event] or 0) then
        return false, "cooldown"
    end
    local line = lines[stableIndex(id, event, now, #lines)]
    KnoxActivityFeed.speak(character, line)
    state.nextGlobal = now + GLOBAL_COOLDOWN
    state.events[event] = now + math.max(GLOBAL_COOLDOWN,
        tonumber(cooldown) or DEFAULT_COOLDOWN)
    return true, line
end

function Dialogue.say(character, survivorId, event, ticks, cooldown)
    return Dialogue.sayLines(character, survivorId, event, BANKS[event], ticks, cooldown)
end

function Dialogue.lines(event)
    return BANKS[event]
end

function Dialogue.resetRuntime()
    states = {}
end

return Dialogue
