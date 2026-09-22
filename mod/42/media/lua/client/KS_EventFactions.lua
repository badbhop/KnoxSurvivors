require "KS_Persistence"

local EventFactions = rawget(_G, "KnoxEventFactions") or {}
_G.KnoxEventFactions = EventFactions

-- Policy only. These definitions grant no actors, items, skills, accuracy,
-- health or hostility. Later event instances must use ordinary Knox survivors.
--
-- Behavior fields:
--   persistsAfterEvent=false patrols (police/military/scientists) arrive, work
--     their objective and leave the county instead of settling a base.
--   hostilePatrol marks patrols that shoot on sight (military). Deserters are
--     exempt individually via the survivor deserter flag.
--   deserters lets one member desert after the event and become recruitable.
--   cureCarrier lets scientists rarely carry the Knox cure (a real renamed
--     medical item, no custom item definition).
--   schedulerWeight/partySize drive the automatic patrol scheduler; scientists
--     are rare by weight and late by minimumWorldDays.
--   disabled keeps Black Division (custom-gear faction) out of scheduling.
local DEFINITIONS = {
    police = {
        displayName = "Police",
        basePolicy = "optional",
        minimumWorldDays = 1,
        defaultDisposition = "neutral",
        loadoutTheme = "police",
        professionId = "base:policeofficer",
        objectives = { "secure_area", "assist" },
        persistsAfterEvent = false,
        partySize = { 3, 4 },
        schedulerWeight = 4,
    },
    scientists = {
        displayName = "Scientists",
        basePolicy = "event_only",
        minimumWorldDays = 14,
        defaultDisposition = "neutral",
        loadoutTheme = "science",
        professionId = "base:doctor",
        appearanceItems = { "Base.JacketLong_Doctor" },
        objectives = { "research", "recover_research" },
        persistsAfterEvent = false,
        partySize = { 2, 2 },
        schedulerWeight = 1,
        cureCarrier = true,
    },
    military = {
        displayName = "Military",
        basePolicy = "event_only",
        minimumWorldDays = 14,
        defaultDisposition = "hostile",
        loadoutTheme = "military",
        professionId = "base:veteran",
        appearanceItems = {
            "Base.Hat_Army",
            "Base.Jacket_ArmyCamoGreen",
            "Base.Trousers_CamoGreen",
            "Base.Shoes_ArmyBoots",
        },
        objectives = { "secure_area", "recover_resource" },
        persistsAfterEvent = false,
        hostilePatrol = true,
        deserters = true,
        partySize = { 4, 5 },
        schedulerWeight = 2,
    },
    black_division = {
        displayName = "Black Division",
        basePolicy = "event_only",
        minimumWorldDays = 60,
        defaultDisposition = "hostile",
        loadoutTheme = "black_division",
        objectives = { "recover_knox_vials" },
        persistsAfterEvent = false,
        disabled = true,
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
        or (definition.professionId ~= nil and (type(definition.professionId) ~= "string"
            or not definition.professionId:match("^[a-z][a-z0-9_]*:[a-z][a-z0-9_]*$")))
        or (definition.appearanceItems ~= nil and type(definition.appearanceItems) ~= "table")
        or type(definition.objectives) ~= "table" or #definition.objectives == 0
        or type(definition.persistsAfterEvent) ~= "boolean" then return false end
    if definition.appearanceItems ~= nil then
        if #definition.appearanceItems == 0 or #definition.appearanceItems > 8 then return false end
        for _, fullType in ipairs(definition.appearanceItems) do
            if type(fullType) ~= "string"
                or not fullType:match("^[A-Za-z][A-Za-z0-9_]*%.[A-Za-z][A-Za-z0-9_]*$") then
                return false
            end
        end
    end
    local seen = {}
    for _, objective in ipairs(definition.objectives) do
        if type(objective) ~= "string" or objective == "" or seen[objective] then return false end
        seen[objective] = true
    end
    if definition.disabled ~= nil and definition.disabled ~= true
        and definition.disabled ~= false then return false end
    if definition.hostilePatrol ~= nil and definition.hostilePatrol ~= true
        and definition.hostilePatrol ~= false then return false end
    if definition.deserters ~= nil and definition.deserters ~= true
        and definition.deserters ~= false then return false end
    if definition.cureCarrier ~= nil and definition.cureCarrier ~= true
        and definition.cureCarrier ~= false then return false end
    if definition.schedulerWeight ~= nil then
        if type(definition.schedulerWeight) ~= "number"
            or definition.schedulerWeight < 1
            or definition.schedulerWeight % 1 ~= 0 then return false end
    end
    if definition.partySize ~= nil then
        if type(definition.partySize) ~= "table"
            or type(definition.partySize[1]) ~= "number"
            or type(definition.partySize[2]) ~= "number"
            or definition.partySize[1] < 2 or definition.partySize[2] > 6
            or definition.partySize[1] > definition.partySize[2] then return false end
    end
    return true
end

function EventFactions.ids()
    local ids = {}; for id in pairs(DEFINITIONS) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function EventFactions.isDisabled(id)
    local definition = type(id) == "string" and DEFINITIONS[id] or nil
    return definition ~= nil and definition.disabled == true
end

-- Policies the automatic patrol scheduler may pick, weighted by
-- schedulerWeight (scientists rare, police common). Disabled policies and
-- policies without a weight never schedule automatically.
function EventFactions.automaticPolicies()
    local ids = {}
    for id, definition in pairs(DEFINITIONS) do
        if definition.disabled ~= true and type(definition.schedulerWeight) == "number" then
            ids[#ids + 1] = id
        end
    end
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

-- First materialization may consume this policy once.  The event remains an
-- ordinary faction/population identity; this lookup creates no gear or body and
-- returns a defensive copy so appearance code cannot mutate faction state.
function EventFactions.materializationPolicy(survivorId)
    local origin = KnoxPersistence.getSurvivorOrigin(survivorId)
    if type(origin) ~= "table" or origin.source ~= "knox_event" then return nil end
    local faction = KnoxPersistence.getFactionForSurvivor(survivorId)
    local identity = type(faction) == "table" and faction.eventIdentity or nil
    local definition = type(identity) == "table" and DEFINITIONS[identity.policyId] or nil
    return definition ~= nil and copy(definition) or nil
end

function EventFactions.bindExistingFaction(factionId, policyId, sourceEventId, worldAgeHours)
    local definition = EventFactions.get(policyId)
    if definition == nil then return nil, "unknown_event_faction" end
    return KnoxPersistence.bindFactionEventIdentity(factionId, policyId, definition.displayName,
        sourceEventId, definition.basePolicy, worldAgeHours)
end

function EventFactions.createEntry(policyId, sourceEventId, origins, worldAgeHours)
    local definition = EventFactions.get(policyId)
    if definition == nil then return nil, "unknown_event_faction" end
    if not EventFactions.isWorldAgeEligible(policyId, worldAgeHours) then
        return nil, "event_faction_too_early"
    end
    return KnoxPersistence.createEventFactionPopulation(policyId, definition.displayName,
        sourceEventId, definition.basePolicy, origins, worldAgeHours)
end

for id, definition in pairs(DEFINITIONS) do
    assert(type(id) == "string" and id:match("^[a-z][a-z0-9_]*$") and valid(definition),
        "Invalid Knox event faction policy: " .. tostring(id))
end

return EventFactions
