local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local Origins = require "KS_SurvivorOrigins"

assert(Origins.normalizeProfessionId("PoliceOfficer") == "base:policeofficer")
assert(Origins.normalizeProfessionId(" BASE:Doctor ") == "base:doctor")
assert(Origins.normalizeProfessionId("not a profession!") == nil)

assert(Origins.classifyRooms({ "livingroom", "policeGunStorage" }) == "law_enforcement")
assert(Origins.classifyRooms({ "security" }) == "private_security")
assert(Origins.classifyRooms({ "medicaloffice", "armystorage" }) == "military",
    "higher-confidence context wins independently of room iteration order")
assert(Origins.classifyRooms({ "armystorage", "medicaloffice" }) == "military")
assert(Origins.classifyRooms({ "militarylocker" }) == "generic",
    "container names cannot classify a building")
assert(Origins.classifyRooms({ "ModdedTraumaCenter" }) == "generic",
    "unknown modded room names fail closed")

local merged = Origins.mergeProfessionCandidate({ "doctor", "base:doctor" }, "nurse")
assert(#merged == 2 and merged[1] == "base:doctor" and merged[2] == "base:nurse",
    "spawn profession candidates normalize, deduplicate, and sort")
assert(Origins.contextForProfessionCandidates({ "doctor", "nurse" }) == "medical")
assert(Origins.contextForProfessionCandidates({ "doctor", "policeofficer" }) == "generic",
    "ambiguous shared spawn coordinates do not claim a facility context")

assert(Origins.facilityAffinity("base:doctor", "medical") == 1)
assert(Origins.facilityAffinity("base:doctor", "law_enforcement") == 0)
assert(Origins.jobPreference("base:mechanics") == "repair")
assert(Origins.jobPreference("base:chef") == "cooking")
assert(Origins.jobPreference("base:rancher") == "farming")
assert(Origins.jobPreference("base:securityguard") == "guard")
assert(Origins.jobPreference("base:carpenter") == "woodwork")
assert(Origins.jobPreference("mod:mechanic") == nil,
    "modded professions require an explicit policy mapping")

local absent = Origins.sanitizeMetadata({ x = 1, y = 2 }, true)
assert(absent.context == nil and absent.professionCandidates == nil,
    "old origins receive no retroactive inference")
local invalid = Origins.sanitizeMetadata({ context = "secret_lab",
    professionCandidates = { "base:doctor" }, buildingId = "5" }, true)
assert(invalid.context == "generic" and invalid.professionCandidates == nil
    and invalid.buildingId == nil, "invalid metadata sanitizes to generic")
local valid = Origins.sanitizeMetadata({ context = "medical",
    professionCandidates = { "nurse", "base:doctor", "nurse" }, buildingId = "42" }, true)
assert(valid.context == "medical" and #valid.professionCandidates == 2
    and valid.buildingId == "42", "valid metadata remains bounded and canonical")

print("Survivor origins PASS aliases=true priority=true fallback=true affinity=true sanitation=true")
