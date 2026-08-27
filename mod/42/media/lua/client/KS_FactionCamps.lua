require "KS_Persistence"

local Camps = rawget(_G, "KnoxFactionCamps") or {}
_G.KnoxFactionCamps = Camps

local function safehouseOccupied(building)
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil or SafeHouse == nil then return false end
    local success, safehouse = pcall(function()
        return SafeHouse.getSafehouseOverlapping(
            definition:getX(), definition:getY(),
            definition:getX() + definition:getW(), definition:getY() + definition:getH()
        )
    end)
    return success and safehouse ~= nil
end

local function locationFor(character)
    local square = character ~= nil and character:getCurrentSquare() or nil
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    if square == nil or definition == nil or safehouseOccupied(building) then
        return nil
    end
    return {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        buildingId = tostring(definition:getID()), name = "Temporary Shelter",
    }
end

-- Called at the low-frequency population reconciliation boundary.  A camp is
-- only formed when the current faction leader is physically present in an
-- unclaimed building; it never teleports members or claims territory.
function Camps.reconcile(controllers, activeIds, worldAgeHours)
    for _, id in ipairs(activeIds or {}) do
        local faction = KnoxPersistence.getFactionForSurvivor(id)
        local controller = controllers ~= nil and controllers[id] or nil
        if faction ~= nil and faction.kind == "npc" and faction.homeBase == nil
            and faction.leaderId == id and controller ~= nil
            and controller.state ~= "COMBAT" and controller.state ~= "STOPPED" then
            local location = locationFor(controller.character)
            if location ~= nil then
                local camp, result = KnoxPersistence.createFactionCamp(
                    faction.id, location, worldAgeHours
                )
                if camp ~= nil and result == "created" then
                    print("[KnoxSurvivors][Camps] established faction=" .. tostring(faction.id)
                        .. " camp=" .. tostring(camp.id)
                        .. " building=" .. tostring(camp.buildingId))
                elseif camp ~= nil then
                    KnoxPersistence.touchFactionCamp(faction.id, worldAgeHours)
                end
            end
        end
    end
end

return Camps
