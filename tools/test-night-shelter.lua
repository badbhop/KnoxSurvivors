local root = arg[1] or "."
require = function() return true end
local shelter = dofile(root .. "/mod/42/media/lua/client/KS_NightShelter.lua")

local hour = 12
getTimeOfDay = function() return hour end
assert(shelter.isNight() == false)
for _, h in ipairs({ 0, 3, 6, 20, 21, 23 }) do
    hour = h
    assert(shelter.isNight() == true, "hour " .. h .. " must read as night")
end
for _, h in ipairs({ 7, 12, 19 }) do
    hour = h
    assert(shelter.isNight() == false, "hour " .. h .. " must read as day")
end
hour = 23

local function square(x, y, room, residential)
    local building = nil
    if residential ~= nil then
        building = { isResidential = function() return residential end }
    end
    return {
        getX = function() return x end, getY = function() return y end, getZ = function() return 0 end,
        canStand = function() return true end,
        getRoom = function() return room end,
        getBuilding = function() return building end,
    }
end
local home = square(0, 0, { id = "room" }, true)
local shed = square(20, 0, { id = "room" }, false)
local street = square(2, 0, nil, nil)
local currentOutdoor = square(6, 0, nil, nil)
local cells = {
    ["0,0,0"] = home, ["20,0,0"] = shed, ["2,0,0"] = street, ["6,0,0"] = currentOutdoor,
}
getCell = function()
    return { getGridSquare = function(_, x, y, z) return cells[x .. "," .. y .. "," .. z] end }
end

assert(shelter.isSheltered({ getCurrentSquare = function() return home end }) == true)
assert(shelter.isSheltered({ getCurrentSquare = function() return street end }) == false)
assert(shelter.isSheltered({}) == false)

-- Nearest roof wins; a house beats a closer street and a farther shed.
local picked = shelter.findShelter({ getCurrentSquare = function() return currentOutdoor end }, 24)
assert(picked == home, "night shelter must prefer the nearest house")
local farOnly = shelter.findShelter({ getCurrentSquare = function() return currentOutdoor end }, 2)
assert(farOnly == nil, "no roof in range must fall back to roaming")

-- A temporary group may use an ordinary refuge, but must not select an
-- established base merely because it happens to be closer.
KnoxPersistence = {
    getBaseAtSquare = function(x, y)
        return x == 0 and y == 0 and { id = "claimed-base" } or nil
    end,
}
local unclaimed = shelter.findShelter(
    { getCurrentSquare = function() return currentOutdoor end },
    24,
    shelter.isUnclaimedTemporaryShelter
)
assert(unclaimed == shed,
    "temporary groups must skip claimed territory when selecting a night refuge")

print("Night shelter PASS hours=true indoor=true nearest-house=true group-filter=true")
