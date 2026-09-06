require "KS_Settings"
require "KS_Persistence"
local SpouseStart = {}
KnoxSpouseStart = SpouseStart

function SpouseStart.update(player, activate)
    if player == nil or player:getCurrentSquare() == nil or player:isDead() then return false end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    if playerId == nil then return false end
    local data = player:getModData().KnoxSurvivors
    if data.spouseStart == nil then
        -- Opening an established save must not silently manufacture a spouse.
        if not KnoxSettings.spawnWithSpouse() or player:getHoursSurvived() > 0.1 then
            data.spouseStart = { status = "skipped" }
            return false
        end
        data.spouseStart = { status = "pending", id = "ks-spouse-" .. playerId }
    end
    local start = data.spouseStart
    if start.status ~= "pending" or not KnoxSettings.spawnWithSpouse() then return false end
    local record = KnoxPersistence.getRecord(start.id)
    if record ~= nil and not KnoxPersistence.isSurvivorAlive(start.id) then
        start.status = "deceased"
        return false
    end
    local origin, square = player:getCurrentSquare(), nil
    local cell = getCell()
    if cell == nil then return false end
    if record == nil then
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    local candidate = cell:getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                    local occupants = candidate ~= nil and candidate.getMovingObjects ~= nil
                        and candidate:getMovingObjects() or nil
                    if square == nil and candidate ~= nil and candidate:canStand()
                        and (occupants == nil or occupants:size() == 0)
                        and not origin:isSomethingTo(candidate) then square = candidate end
                end
            end
        end
        if square == nil then return false end
    end
    -- The caller reuses normal capture/restore and registry ownership. Persist
    -- the stable reservation first; retries never select a second identity.
    if not activate(start.id, square, record) then return false end
    local now = getGameTime():getWorldAgeHours()
    local assigned = KnoxPersistence.setPlayerCompanion(start.id, playerId, "follow", now)
    if not assigned then return false end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, start.id)
    relation.trust = 90
    relation.meetings = math.max(1, relation.meetings or 0)
    relation.firstMetHours = relation.firstMetHours or now
    start.status = "complete"
    return true
end

return SpouseStart
