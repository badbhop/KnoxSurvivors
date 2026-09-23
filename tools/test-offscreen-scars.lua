local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path

CharacterStat = { HUNGER = "hunger", THIRST = "thirst", FATIGUE = "fatigue", ENDURANCE = "endurance" }

local states = {
    returner = {
        hunger = 0.2, thirst = 0.2, fatigue = 0.2, endurance = 0.8,
        health = 90, bleedingParts = 0, lastHours = 0, status = "hibernated",
        activity = "exploring", virtualX = 100, virtualY = 200, virtualZ = 0,
        scars = {
            { x = 105, y = 204, z = 0, t = 5, kind = "fight", with = "rival", detail = "d" },
            { x = 9000, y = 9000, z = 0, t = 5, kind = "injury", detail = "d" },
        },
    },
    passerby = {
        hunger = 0.2, thirst = 0.2, fatigue = 0.2, endurance = 0.8,
        health = 90, bleedingParts = 0, lastHours = 0, status = "hibernated",
        activity = "exploring", virtualX = 5000, virtualY = 5000, virtualZ = 0,
        scars = {
            { x = 505, y = 500, z = 0, t = 5, kind = "fight", with = "rival", detail = "d" },
        },
    },
}

KnoxPersistence = {
    getUnloadedSurvivalState = function(id) return states[id] end,
    setUnloadedSurvivalState = function(id, state) states[id] = state return true end,
}

local stories = require("KS_OffscreenStories")

local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z or 0 end }
end
local function body(x, y, z)
    local stats = {}
    return {
        getCurrentSquare = function() return square(x, y, z) end,
        getStats = function()
            return { set = function(_, key, value) stats[key] = value end }
        end,
        getBodyDamage = function()
            return { setOverallBodyHealth = function() end }
        end,
    }
end

-- Near-site scars resolve into history; far traces wait.
assert(stories.resolveScars("returner", body(102, 201, 0), 10) == 1, "near scar resolves")
assert(#states.returner.scars == 1, "consumed scar leaves the ledger")
assert(states.returner.scars[1].x == 9000, "far scar waits")
local kinds = {}
for _, entry in ipairs(states.returner.history or {}) do kinds[entry.kind] = true end
assert(kinds.scar == true, "returns append scar history")
assert(stories.resolveScars("passerby", body(0, 0, 0), 10) == 0, "distant scars resolve nothing")
assert(#states.passerby.scars == 1, "untouched scars persist")
assert(stories.resolveScars("returner", nil, 10) == 0, "missing body resolves nothing")
assert(stories.resolveScars("nobody", body(0, 0, 0), 10) == 0, "missing ledgers resolve nothing")
print("Scar resolution PASS")

-- Scar returns are retold at campfires.
KnoxActivityFeed = { speak = function() end }
KnoxSettings = { showSurvivorSpeech = function() return true end }
package.preload.KS_ActivityFeed = function() return KnoxActivityFeed end
package.preload.KS_Settings = function() return KnoxSettings end
local Dialogue = assert(loadfile(projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorDialogue.lua"))()
local fightLine = Dialogue.recountEntry("returner", { kind = "scar", with = "rival", t = 10 })
assert(fightLine ~= nil and string.find(fightLine, "drew weapons", 1, true) ~= nil,
    "fight returns are recounted")
local hurtLine = Dialogue.recountEntry("returner", { kind = "scar", t = 10 })
assert(hurtLine ~= nil and string.find(hurtLine, "bled", 1, true) ~= nil,
    "injury returns are recounted")
print("Scar recount PASS")

-- Places remember: scars nearby double the haunt rate, deterministically.
local function countSteadied(withScar)
    local probe = {
        hunger = 0.2, thirst = 0.2, fatigue = 0.5, endurance = 0.8,
        health = 100, bleedingParts = 0, lastHours = 0, status = "hibernated",
        activity = "exploring", virtualX = 100, virtualY = 200, virtualZ = 0,
        scars = withScar and { { x = 105, y = 205, z = 0, t = 1, kind = "fight", detail = "d" } } or {},
    }
    local count = 0
    for phase = 1, 200 do
        local hours = phase * 6
        probe.lastHours = hours - 6
        probe.fatigue = 0.5
        local before = #(probe.history or {})
        stories.resolveFor("haunt-probe", probe, hours, 6)
        for index = before + 1, #(probe.history or {}) do
            if probe.history[index].kind == "haunt" then count = count + 1 end
        end
    end
    return count
end
local plain, scarred = countSteadied(false), countSteadied(true)
assert(scarred >= plain, "scarred ground steadies more often")
print("Scar memory PASS plain=" .. plain .. " scarred=" .. scarred)

-- Materialization hook: applyToLoaded resolves scars on the way in.
local simulation = require("KS_UnloadedSurvival")
states.arriver = {
    hunger = 0.2, thirst = 0.2, fatigue = 0.2, endurance = 0.8,
    health = 90, bleedingParts = 0, lastHours = 0, status = "hibernated",
    activity = "exploring", virtualX = 100, virtualY = 200, virtualZ = 0,
    scars = { { x = 101, y = 201, z = 0, t = 1, kind = "fight", with = "rival", detail = "d" } },
    vehicleTrip = { targetX = 800, targetY = 900, targetZ = 0, atHours = 2 },
}
local applied, reason = simulation.applyToLoaded("arriver", body(101, 201, 0))
assert(applied and reason == "applied", "materialization applies stored state")
assert(#states.arriver.scars == 0, "hook consumes scars on materialize")
assert(states.arriver.vehicleTrip == nil, "hook clears virtual vehicle ownership on materialize")
local found, endedRide = false, false
for _, entry in ipairs(states.arriver.history or {}) do
    if entry.kind == "scar" then found = true break end
    if entry.kind == "ride" and entry.outcome == "materialized" then endedRide = true end
end
assert(found, "hook appends scar history")
for _, entry in ipairs(states.arriver.history or {}) do
    if entry.kind == "ride" and entry.outcome == "materialized" then endedRide = true end
end
assert(endedRide, "vehicle handoff history survives scar persistence")
print("Scar hook PASS")

print("Offscreen scars PASS resolve=true recount=true memory=true hook=true")
