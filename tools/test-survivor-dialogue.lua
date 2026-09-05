local rootPath = arg[1] or "."

local spoken = {}
KnoxActivityFeed = {
    speak = function(character, line)
        spoken[#spoken + 1] = { character = character, line = line }
    end,
}
KnoxSettings = { showSurvivorSpeech = function() return true end }
package.preload.KS_ActivityFeed = function() return KnoxActivityFeed end
package.preload.KS_Settings = function() return KnoxSettings end

local dialogue = assert(loadfile(rootPath
    .. "/mod/42/media/lua/client/KS_SurvivorDialogue.lua"))()
local character = {}

local first, line = dialogue.say(character, "gary", "search", 100, 1000)
assert(first and type(line) == "string" and #spoken == 1,
    "first contextual line is emitted")
assert(not dialogue.say(character, "gary", "search", 200, 1000),
    "same event respects its cooldown")
assert(not dialogue.say(character, "gary", "combat", 200, 1000),
    "global cooldown prevents overlapping callouts")
assert(dialogue.say(character, "gary", "combat", 400, 1000),
    "different event may speak after the short global cooldown")
assert(not dialogue.say(character, "gary", "search", 900, 1000),
    "event-specific cooldown remains authoritative")
assert(dialogue.say(character, "gary", "search", 1100, 1000),
    "event becomes available after bounded cooldown")

KnoxSettings.showSurvivorSpeech = function() return false end
assert(not dialogue.say(character, "other", "rest", 2000),
    "speech setting disables contextual chatter")
KnoxSettings.showSurvivorSpeech = function() return true end
dialogue.resetRuntime()
assert(dialogue.say(character, "gary", "search", 0, 1000),
    "runtime reset clears transient cooldown state")

for _, event in ipairs({ "roam_building", "roam_area", "search", "loot_found",
    "no_supplies", "share_supply", "need_food", "need_water", "need_medical", "rest",
    "regroup", "combat", "flee", "base_work", "camp" }) do
    assert(type(dialogue.lines(event)) == "table" and #dialogue.lines(event) >= 2,
        "dialogue bank missing for " .. event)
end

print("Survivor dialogue PASS banks=true cooldown=true global=true settings=true reset=true")
