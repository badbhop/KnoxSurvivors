local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local empty = list({})
local police = {
    getType = function() return "base:policeofficer" end,
    getCost = function() return -4 end,
    getGrantedTraits = function() return empty end,
}
local balancingTrait = {
    getType = function() return "base:slowreader" end,
    getCost = function() return -4 end,
    getGrantedTraits = function() return empty end,
    isFree = function() return false end,
    isDisabledInMultiplayer = function() return false end,
    isMutuallyExclusive = function() return false end,
}
CharacterProfessionDefinition = { getProfessions = function() return list({ police }) end }
CharacterTraitDefinition = {
    getTraits = function() return list({ balancingTrait }) end,
    getCharacterTraitDefinition = function(id)
        return id == "base:slowreader" and balancingTrait or nil
    end,
}
isMultiplayer = function() return false end

local data = {}
ModData = { getOrCreate = function(key) data[key] = data[key] or {} return data[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 24 end } end

require "KS_Persistence"
local Capabilities = require "KS_SurvivorCapabilities"
local profile, evidence = Capabilities.generate("ks-police-1", "base:policeofficer")
assert(profile ~= nil and evidence == "generated_preferred", tostring(evidence))
assert(profile.professionId == "base:policeofficer" and profile.unspentPoints >= 0
    and profile.unspentPoints <= 3, "preferred profession must still use balanced vanilla points")
local missing, missingEvidence = Capabilities.generate("ks-police-2", "base:missing")
assert(missing == nil and string.find(missingEvidence, "preferred_profession_missing", 1, true),
    "unknown preferred profession fails explicitly")

assert(KnoxPersistence.setRecord("ks-police-3", "record"))
local persisted = assert(Capabilities.ensure("ks-police-3", nil, true, "base:policeofficer"))
assert(persisted.professionId == "base:policeofficer")
local existing = assert(Capabilities.ensure("ks-police-3", nil, true, "base:missing"))
assert(existing.professionId == "base:policeofficer",
    "first materialization policy cannot rewrite an existing capability profile")

print("survivor capability tests passed")
