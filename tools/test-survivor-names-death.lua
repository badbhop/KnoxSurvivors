package.path = "mod/42/media/lua/client/?.lua;" .. package.path
local Names = require "KS_SurvivorNames"
local character = { getDescriptor = function() return {
    getForename = function() return "Amy" end,
    getSurname = function() return "Price" end,
} end }
local identity = { forename = "KS-SURVIVOR-WORLD-12", surname = "" }
local _, _, name = Names.resolve("KS-SURVIVOR-WORLD-12", identity, character)
assert(name == "Amy Price", "body human name replaces internal placeholder")
assert(identity.forename == "KS-SURVIVOR-WORLD-12", "presentation must not rewrite saved identities")
_, _, name = Names.resolve("KS-SURVIVOR-WORLD-12", identity, nil)
assert(name == "Survivor", "unloaded placeholder must never leak")
_, _, name = Names.resolve("id", { forename = " Morgan ", surname = "Reed" }, character)
assert(name == "Morgan Reed", "persisted human identity wins")
_, _, name = Names.resolve("id", {}, { getDescriptor = function() error("detached") end })
assert(name == "Survivor", "detached body is safe")

-- Exercise the production death transition with a failed corpse attempt, a
-- successful retry, and an already-dead record restored from the save.
local file = assert(io.open("mod/42/media/lua/client/KS_SurvivorAutonomy.lua", "r"))
local source = file:read("*a"); file:close()
local body = assert(source:match("local function retireDeadSurvivor%b()%s*(.-)\nend%s*\n%s*local function retireDeadControllers"))
local alive, announcements, corpseAttempts = true, 0, 0
KnoxPersistence = {
    isSurvivorAlive = function() return alive end,
    markSurvivorDead = function() alive = false; return true end,
}
KnoxActivityFeed = { survivorDied = function(id, actor)
    assert(id == "id" and actor == character); announcements = announcements + 1
end }
KnoxSurvivorRuntime = { unregister = function() end }
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
local compile = loadstring or load
local retire = assert(compile("local controllers = {}; local TAG = 'test'; local function removeActiveId() end; return function(bridge,id,controller) " .. body .. " end"))()
local bridge = {
    retireNpcAsCorpse = function() corpseAttempts = corpseAttempts + 1
        return corpseAttempts == 1 and "CORPSE_FAILED retry" or "CORPSE_CREATED"
    end,
    getNpcCharacter = function() return character end,
}
local controller = { character = character, shutdown = function() end }
retire(bridge, "id", controller)
retire(bridge, "id", controller)
retire(bridge, "id", controller)
assert(announcements == 1, "cleanup retries and persisted dead records must not announce again")
print("Survivor names/death PASS")
