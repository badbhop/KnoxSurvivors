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
    base_idle = {
        "Quiet for now. I should check on everyone.",
        "We have a roof. Next we make this place livable.",
        "I keep thinking about what we still need.",
        "Anyone need a hand before I settle down?",
        "I might walk the yard and clear my head.",
    },
    base_social = {
        "Good to see a living face. How are you holding up?",
        "We made it another day. That counts for something.",
        "Sit with me a minute. Tell me what you have seen out there.",
        "This place is starting to feel like ours, do you not think?",
        "When the work is done we should eat together, all of us.",
    },
    base_snack = {
        "I am having a bite. There is enough if you want some.",
        "A quick drink and back to it.",
        "Nothing fancy, but it keeps me going.",
    },
    camp = {
        "I'm staying close for a while.", "This place will do for now.",
    },
    player_talk = {
        "Keep your voice down. Sound carries.",
        "I have been moving carefully since this started.",
        "If we stay alive, we will need a plan beyond tonight.",
        "I remember when a locked door meant something.",
        "I am watching the roads. People are becoming the bigger danger.",
    },
    player_warm_up = {
        "I am not ready to trust a stranger. Give me a little time.",
        "You seem all right. I still need to see how you handle trouble.",
        "Talk to me again after we have both made it through another day.",
    },
    player_independent = {
        "I travel alone. It is how I have stayed alive.",
        "I appreciate the offer, but I have my own route to follow.",
        "No hard feelings. I do better when I answer only for myself.",
    },
    player_lure = {
        "I know a place nearby. Come on, I can show you.",
        "There is shelter just past those buildings. You should see it.",
        "Keep walking with me. We can talk somewhere quieter.",
    },
    player_attack_warning = {
        "Back away. I do not want to fight, but I will.",
        "You should have kept walking.",
        "One more step and we settle this the hard way.",
    },
}

local PERSONALITY_BANKS = {
    frightened = {
        player_talk = { "I keep thinking I hear someone behind us.",
            "I had people with me once. I do not know where they are now.",
            "Please do not leave me in an empty building." },
        combat = { "I cannot do this alone!", "Stay close, please!", "There are too many!" },
        need_medical = { "It hurts more when I move.", "I need help with this wound." },
        camp = { "I just want one quiet night.", "Maybe tomorrow will be safer." },
    },
    guarded = {
        player_talk = { "I remember enough to know not to trust promises.",
            "Show me what you do when things go wrong.",
            "I am listening. That does not mean I agree." },
        combat = { "Watch the angles.", "Do not chase them into a bad position.", "Hold your ground." },
        need_medical = { "The wound is manageable. It still needs cleaning." },
        camp = { "We need a better fallback before we settle here.", "A base is only as good as its exits." },
    },
    brave = {
        player_talk = { "We can build something if we keep making smart choices.",
            "I have lost people before. I will not waste what they taught me.",
            "Give me a job and I will see it through." },
        combat = { "Stay behind me.", "We finish this and move on.", "Keep the pressure on." },
        need_medical = { "It is a bad cut, but I can still work after it is dressed." },
        camp = { "We should make this place worth defending.", "There is still a future if we plan for it." },
    },
    loner = {
        player_talk = { "I have survived by keeping my footprint small.",
            "I had a route before we met. I may return to it.",
            "Company is useful. Dependence gets people killed." },
        combat = { "Pick one and finish it.", "Do not draw the whole street.", "I will cover this side." },
        camp = { "I will keep to the edge of camp.", "A quiet corner is all I need." },
    },
    sociable = {
        player_talk = { "It helps hearing another living voice.",
            "We should learn what everyone is good at.",
            "I still think people can make a life here." },
        combat = { "Together, now!", "I have your side.", "Call out what you see." },
        camp = { "We should eat together when the work is done.", "A real routine might keep us sane." },
    },
    unstable = {
        player_talk = { "Some days I remember everything. Some days I remember too much.",
            "I had a plan. Then the dead started walking.",
            "Do not mistake a smile for calm." },
        combat = { "They keep coming. Good. Let them.", "I can hear them in the walls.", "Move! Move!" },
        camp = { "The quiet is worse than the noise.", "I need something to do before I start thinking." },
    },
    opportunist = {
        player_talk = { "Everybody needs something. The trick is finding out what.",
            "I know places people overlook.",
            "We could both come out ahead here." },
        combat = { "Take what you can and go.", "Do not get stuck fighting for pride.", "Find the weak side." },
        camp = { "A good base needs supplies and an exit nobody watches.", "I know where the useful things are kept." },
    },
    predatory = {
        player_talk = { "You are carrying more than you can protect.",
            "You should have kept your distance.",
            "This road belongs to whoever can hold it." },
        combat = { "No witnesses.", "Finish it.", "Do not let them run." },
    },
    gunner = {
        player_talk = { "Nice weapon. Do not reach for it.",
            "I have got a bead on this whole street.",
            "Plenty of ammo. Hoping I do not need it." },
        combat = { "Told you.", "Should have walked.", "Cover! Reloading!" },
        camp = { "I sleep light. Do not test it.", "Perimeter stays watched." },
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

local PLACE_WORDS = {
    "the ridge road", "empty houses", "the treeline", "a burned-out stop",
    "the river bend", "quiet streets", "a stripped farmhouse", "the rail line",
}

local function hashText(text)
    local hash = 23
    text = tostring(text or "")
    for index = 1, #text do
        hash = (hash * 37 + string.byte(text, index)) % 2147483647
    end
    return hash
end

local function placeWord(id, timestamp)
    return PLACE_WORDS[(hashText(tostring(id) .. ":" .. tostring(timestamp)) % #PLACE_WORDS) + 1]
end

--- How `viewerId` refers to `subjectId` inCampfire-style speech. Disposition
--- and shared affiliation decide the noun; no kinship is invented because the
--- ledger tracks none. Deterministic and side-effect free.
function Dialogue.relationNoun(viewerId, subjectId)
    if viewerId == nil or subjectId == nil then return "a traveler" end
    if tostring(viewerId) == tostring(subjectId) then return "myself" end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then return "a traveler" end
    local disposition = nil
    if persistence.getRelationship ~= nil then
        local ok, record = pcall(persistence.getRelationship, viewerId, subjectId)
        if ok and type(record) == "table" then disposition = record.disposition end
    end
    if disposition == "hostile" then return "that hostile soul" end
    if disposition == "declined" then return "that one" end
    local viewerGroup, subjectGroup = nil, nil
    if persistence.getTravelGroupFor ~= nil then
        local ok, group = pcall(persistence.getTravelGroupFor, viewerId)
        if ok and type(group) == "table" then viewerGroup = group end
        ok, group = pcall(persistence.getTravelGroupFor, subjectId)
        if ok and type(group) == "table" then subjectGroup = group end
    end
    if viewerGroup ~= nil and subjectGroup ~= nil
        and tostring(viewerGroup.id) == tostring(subjectGroup.id) then
        return "my groupmate"
    end
    local viewerFaction, subjectFaction = nil, nil
    if persistence.getFactionForSurvivor ~= nil then
        local ok, faction = pcall(persistence.getFactionForSurvivor, viewerId)
        if ok then viewerFaction = faction end
        ok, faction = pcall(persistence.getFactionForSurvivor, subjectId)
        if ok then subjectFaction = faction end
    end
    local viewerFactionId = type(viewerFaction) == "table" and viewerFaction.id or viewerFaction
    local subjectFactionId = type(subjectFaction) == "table" and subjectFaction.id or subjectFaction
    if viewerFactionId ~= nil and subjectFactionId ~= nil
        and tostring(viewerFactionId) == tostring(subjectFactionId) then
        return "one of ours"
    end
    if disposition == "allied" then return "my friend" end
    local meetings = 0
    if persistence.getRelationship ~= nil then
        local ok, record = pcall(persistence.getRelationship, viewerId, subjectId)
        if ok and type(record) == "table" then meetings = tonumber(record.meetings) or 0 end
    end
    if meetings >= 2 then return "someone I have crossed before" end
    return "a traveler"
end

local function forenameOf(id)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorIdentity ~= nil then
        local ok, identity = pcall(persistence.getSurvivorIdentity, id)
        if ok and type(identity) == "table" then
            local forename = identity.forename or identity.firstName
            if type(forename) == "string" and forename ~= "" then return forename end
        end
    end
    return nil
end

--- Build campfire recount lines from ledger history (newest first, max 3).
-- Names render relation-aware: repeat meetings speak of relations, first
-- meetings speak the recorded forename when one exists. Returns {} when the
-- survivor has no history worth retelling.
function Dialogue.recountLines(survivorId)
    local stories = rawget(_G, "KnoxOffscreenStories")
    if stories == nil or stories.historyFor == nil then return {} end
    local ok, history = pcall(stories.historyFor, survivorId)
    if not ok or type(history) ~= "table" or #history == 0 then return {} end
    local lines = {}
    for index = #history, math.max(1, #history - 2), -1 do
        local entry = history[index]
        if type(entry) == "table" then
            local line = Dialogue.recountEntry(survivorId, entry)
            if line ~= nil then lines[#lines + 1] = line end
            if #lines >= 3 then break end
        end
    end
    return lines
end

function Dialogue.recountEntry(survivorId, entry)
    local kind = tostring(entry.kind or "")
    local place = placeWord(survivorId, entry.t)
    local subject = nil
    if entry.with ~= nil then
        subject = Dialogue.relationNoun(survivorId, entry.with)
        if subject == "a traveler" or subject == "someone I have crossed before" then
            local name = forenameOf(entry.with)
            if name ~= nil then subject = name end
        end
    end
    if kind == "meet" and subject ~= nil then
        if entry.outcome == "hostile" then
            return "Crossed " .. subject .. " out past " .. place .. ". Things turned hostile between us."
        end
        if entry.outcome == "joined" then
            return "Met " .. subject .. " out past " .. place .. ". We decided to travel together."
        end
        if entry.outcome == "declined" or entry.outcome == "parted" then
            return "Met " .. subject .. " out past " .. place .. ". We decided to go our separate ways."
        end
        return "Ran into " .. subject .. " out past " .. place .. ". We talked and walked on."
    end
    if kind == "close_call" then
        if entry.outcome == "hurt" then
            return "Got torn up out near " .. place .. ". Still bled when I found cover."
        end
        return "Something stalked me near " .. place .. ". Went still until it passed."
    end
    if kind == "rest" then
        return "Found a quiet moment out past " .. place .. ". Caught my breath."
    end
    if kind == "haunt" then
        return "Walked ground that felt known, out past " .. place .. ". Steadied me."
    end
    if kind == "weather" then
        return "Pushed through bad weather past " .. place .. ". Still moving."
    end
    if kind == "cache" then
        return "Marked a spot out past " .. place .. " in my head. Might matter later."
    end
    if kind == "ride" then
        if entry.outcome == "arrived" then
            return "Caught wheels out past " .. place .. ". Rode all the way."
        end
        return "Caught a ride out past " .. place .. ". Saved my legs."
    end
    if kind == "scar" then
        if subject ~= nil then
            return "Came back to where " .. subject .. " and I drew weapons. Still standing."
        end
        return "Came back to where I bled out past " .. place .. ". It looks different in daylight."
    end
    return nil
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
    local lines = BANKS[event]
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getSurvivorPersonality ~= nil then
        local personality = persistence.getSurvivorPersonality(survivorId)
        local overrides = personality ~= nil and PERSONALITY_BANKS[personality.personality] or nil
        if overrides ~= nil and type(overrides[event]) == "table" then
            lines = overrides[event]
        end
    end
    if event == "base_social" then
        -- Campfire moments retell ledger history (TIS recount rule) about a
        -- third of the time; otherwise the normal lifestyle bank speaks.
        local window = math.floor((tonumber(ticks) or 0) / 1800)
        if hashText(tostring(survivorId) .. ":recount:" .. tostring(window)) % 100 < 35 then
            local recount = Dialogue.recountLines(survivorId)
            if #recount > 0 then
                return Dialogue.sayLines(character, survivorId, "recount", recount, ticks, cooldown)
            end
        end
    end
    return Dialogue.sayLines(character, survivorId, event, lines, ticks, cooldown)
end

function Dialogue.lines(event)
    return BANKS[event]
end

function Dialogue.resetRuntime()
    states = {}
end

return Dialogue
