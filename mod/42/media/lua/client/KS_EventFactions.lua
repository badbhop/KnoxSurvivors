require "KS_Persistence"

local EventFactions = rawget(_G, "KnoxEventFactions") or {}
_G.KnoxEventFactions = EventFactions

-- Policy only. These definitions grant no actors, items, skills, accuracy,
-- health or hostility. Later event instances must use ordinary Knox survivors.
local DEFINITIONS = {
    police = {
        displayName = "Police",
        basePolicy = "optional",
        minimumWorldDays = 1,
        defaultDisposition = "neutral",
        loadoutTheme = "police",
        objectives = { "assist", "secure_area" },
        persistsAfterEvent = true,
    },
    scientists = {
        displayName = "Scientists",
        basePolicy = "event_only",
        minimumWorldDays = 14,
        defaultDisposition = "neutral",
        loadoutTheme = "science",
        objectives = { "research", "recover_research" },
        persistsAfterEvent = false,
    },
    military = {
        displayName = "Military",
        basePolicy = "event_only",
        minimumWorldDays = 14,
        defaultDisposition = "neutral",
        loadoutTheme = "military",
        objectives = { "secure_area", "recover_resource" },
        persistsAfterEvent = false,
    },
    black_division = {
        displayName = "Black Division",
        basePolicy = "event_only",
        minimumWorldDays = 60,
        defaultDisposition = "hostile",
        loadoutTheme = "black_division",
        objectives = { "recover_knox_vials" },
        persistsAfterEvent = false,
    },
    scavengers = {
        displayName = "Scavengers",
        basePolicy = "event_only",
        minimumWorldDays = 7,
        defaultDisposition = "neutral",
        loadoutTheme = "scavenger",
        objectives = { "scavenge_world", "scavenge_base" },
        persistsAfterEvent = true,
        bossEnabled = false,
    },
    pmc = {
        displayName = "PMC",
        basePolicy = "event_only",
        minimumWorldDays = 14,
        defaultDisposition = "neutral",
        loadoutTheme = "pmc",
        objectives = { "contract_follow", "contract_guard", "contract_raid" },
        persistsAfterEvent = false,
        contractEligible = true,
    },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function valid(definition)
    if type(definition) ~= "table" or type(definition.displayName) ~= "string"
        or definition.displayName == "" or #definition.displayName > 64
        or (definition.basePolicy ~= "event_only" and definition.basePolicy ~= "optional")
        or type(definition.minimumWorldDays) ~= "number" or definition.minimumWorldDays < 0
        or (definition.defaultDisposition ~= "neutral" and definition.defaultDisposition ~= "hostile")
        or type(definition.loadoutTheme) ~= "string" or definition.loadoutTheme == ""
        or type(definition.objectives) ~= "table" or #definition.objectives == 0
        or type(definition.persistsAfterEvent) ~= "boolean" then return false end
    local seen = {}
    for _, objective in ipairs(definition.objectives) do
        if type(objective) ~= "string" or objective == "" or seen[objective] then return false end
        seen[objective] = true
    end
    return true
end

function EventFactions.ids()
    local ids = {}; for id in pairs(DEFINITIONS) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function EventFactions.get(id)
    local definition = type(id) == "string" and DEFINITIONS[id] or nil
    return definition ~= nil and copy(definition) or nil
end

function EventFactions.allowsObjective(id, objective)
    local definition = type(id) == "string" and DEFINITIONS[id] or nil
    if definition == nil or type(objective) ~= "string" then return false end
    for _, candidate in ipairs(definition.objectives) do if candidate == objective then return true end end
    return false
end

function EventFactions.isWorldAgeEligible(id, worldAgeHours)
    local definition = type(id) == "string" and DEFINITIONS[id] or nil
    local hours = tonumber(worldAgeHours)
    return definition ~= nil and hours ~= nil and hours == hours and hours >= definition.minimumWorldDays * 24
end

function EventFactions.bindExistingFaction(factionId, policyId, sourceEventId, worldAgeHours)
    local definition = EventFactions.get(policyId)
    if definition == nil then return nil, "unknown_event_faction" end
    return KnoxPersistence.bindFactionEventIdentity(factionId, policyId, definition.displayName,
        sourceEventId, definition.basePolicy, worldAgeHours)
end

for id, definition in pairs(DEFINITIONS) do
    assert(type(id) == "string" and id:match("^[a-z][a-z0-9_]*$") and valid(definition),
        "Invalid Knox event faction policy: " .. tostring(id))
end

return EventFactions
