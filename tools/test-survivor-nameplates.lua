local root = arg[1] or "."
require = function(name)
    if name == "KS_SurvivorNames" then
        return dofile(root .. "/mod/42/media/lua/client/KS_SurvivorNames.lua")
    end
end
local callbacks, draws = {}, {}
Events = { OnPreUIDraw = { Add = function(f) callbacks.draw = f end },
    OnGameStart = { Add = function(f) callbacks.reset = f end } }
local visible, enabled, dead, alpha, z, client = true, true, false, 1, 0, false
local npc = {
    getCurrentSquare = function() return { getZ = function() return z end,
        getX = function() return 10 end, getY = function() return 10 end } end,
    getX = function() return 10 end, getY = function() return 10 end, getZ = function() return z end,
    isDead = function() return dead end, getAlpha = function() return alpha end,
    getOffsetX = function() return 0 end, getOffsetY = function() return 0 end,
    setShowTag = function() end,
}
local player = { getCurrentSquare = function() return {
    getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end,
} end, getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end,
    CanSee = function() return visible end }
getSpecificPlayer = function() return player end
getNumActivePlayers = function() return 1 end
isClient = function() return client end
KnoxSettings = { showSurvivorNameplates = function() return enabled end,
    survivorNameplateDistance = function() return 24 end, allowSurvivorPlayerCombat = function() return false end }
KnoxSurvivorRuntime = { activeIds = function() return { "test" } end, getCharacter = function() return npc end }
KnoxPersistence = { getSurvivorIdentity = function() return { forename = "Jamie", surname = "Miller" } end,
    ensurePlayerId = function() return "player" end,
    getSurvivorAffiliation = function() return { kind = "player", ownerId = "player" } end }
IsoCamera = { getScreenLeft = function() return 0 end, getScreenTop = function() return 0 end,
    getScreenWidth = function() return 800 end, getScreenHeight = function() return 600 end,
    getOffX = function() return 0 end, getOffY = function() return 0 end }
IsoUtils = { XToScreen = function() return 400 end, YToScreen = function() return 350 end }
Core = { getTileScale = function() return 2 end }
getCore = function() return { getZoom = function() return 1 end } end
UIFont = { Small = 1 }
getTextManager = function() return { MeasureStringX = function() return 80 end,
    getFontHeight = function() return 14 end, DrawStringCentre = function(_, font, x, y, name, r, g, b, a)
        draws[#draws + 1] = { name = name, r = r, g = g, a = a, y = y }
    end } end
local names = dofile(root .. "/mod/42/media/lua/client/KS_SurvivorNameplates.lua")
names.update(15) callbacks.draw()
assert(#draws == 2 and draws[2].name == "Jamie Miller" and draws[2].g > draws[2].r)
alpha = .4 draws = {} callbacks.draw() assert(draws[2].a == .4, "name follows native fade")
for _, mode in ipairs({ "hidden", "dead", "floor", "disabled", "client" }) do
    visible, dead, z, enabled, client = mode ~= "hidden", mode == "dead", mode == "floor" and 1 or 0,
        mode ~= "disabled", mode == "client"
    draws = {} callbacks.draw() assert(#draws == 0, "must suppress " .. mode)
end
enabled, client, visible, dead, z = true, false, true, false, 0
callbacks.reset() draws = {} callbacks.draw() assert(#draws == 0)
print("Nameplates PASS single_player_draw=true los=true fade=true floor=true native_client_no_duplicate=true")
