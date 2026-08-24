local ZombieAwareness = rawget(_G, "KnoxZombieAwareness") or {}
_G.KnoxZombieAwareness = ZombieAwareness

local AWARENESS_RADIUS_SQUARED = 24 * 24
local REPORT_COOLDOWN_TICKS = 1800
local lastFailureReport = -REPORT_COOLDOWN_TICKS

local function validNpc(character)
    return character ~= nil
        and character:getCurrentSquare() ~= nil
        and not character:isDead()
end

local function validTarget(target)
    if target == nil then
        return false
    end
    local success, square, dead = pcall(function()
        return target:getCurrentSquare(), target:isDead()
    end)
    return success and square ~= nil and dead ~= true
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

-- Knox shells deliberately skip IsoPlayer.updateLOS(): running that method from an
-- off-slot player writes to a local player's visibility channel. Vanilla normally
-- calls TestZombieSpotPlayer from updateLOS, so reproduce only that discovery edge.
-- The engine still owns sight, hearing, target selection, and attack behavior.
function ZombieAwareness.update(controllers, orderedIds, ticks)
    if ticks % 30 ~= 0 or getCell() == nil then
        return
    end
    local zombies = getCell():getZombieList()
    if zombies == nil or zombies:isEmpty() then
        return
    end
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        local currentTarget = zombie ~= nil and zombie:getTarget() or nil
        if zombie == nil or zombie:isDead() or zombieSquare == nil then
            -- skip
        else
            local currentValid = validTarget(currentTarget)
            local currentIsPlayer = false
            local currentPlayerDist2 = nil
            if currentValid then
                local ct = getNumActivePlayers and getNumActivePlayers() or 1
                for pIdx = 0, math.max(0, tonumber(ct) or 1) - 1 do
                    local p = getSpecificPlayer(pIdx)
                    if p ~= nil and currentTarget == p then
                        currentIsPlayer = true
                        local psq = p:getCurrentSquare()
                        if psq ~= nil and psq:getZ() == zombieSquare:getZ() then
                            currentPlayerDist2 = distanceSquared(zombieSquare, psq)
                        end
                        break
                    end
                end
            end
            -- Find nearest valid NPC within awareness radius
            local nearestId = nil
            local nearestNpc = nil
            local nearestDistance = AWARENESS_RADIUS_SQUARED + 1
            for _, id in ipairs(orderedIds or {}) do
                local controller = controllers ~= nil and controllers[id] or nil
                local npc = controller ~= nil and controller.character or nil
                if validNpc(npc) then
                    npc:setZombiesDontAttack(false)
                    local npcSquare = npc:getCurrentSquare()
                    if npcSquare ~= nil and zombieSquare:getZ() == npcSquare:getZ() then
                        local distance = distanceSquared(zombieSquare, npcSquare)
                        if distance <= AWARENESS_RADIUS_SQUARED and distance < nearestDistance then
                            nearestId = id
                            nearestNpc = npc
                            nearestDistance = distance
                        end
                    end
                end
            end
            local shouldRetarget = false
            if not currentValid and nearestNpc ~= nil then
                shouldRetarget = true
            elseif currentIsPlayer and nearestNpc ~= nil and currentPlayerDist2 ~= nil then
                -- Player is current target but NPC is at least 3 tiles closer (9 dist2) - let zombie switch to nearer survivor
                if nearestDistance + 9 < currentPlayerDist2 then
                    shouldRetarget = true
                end
            elseif currentValid and not currentIsPlayer and nearestNpc ~= nil then
                -- Current is another survivor, keep it (preserve) unless new NPC is much closer (5 tiles)
                -- To avoid thrashing, only switch if significantly closer
                local currentDist2 = nil
                if currentTarget ~= nil and currentTarget:getCurrentSquare() ~= nil then
                    local ctsq = currentTarget:getCurrentSquare()
                    if ctsq:getZ() == zombieSquare:getZ() then
                        currentDist2 = distanceSquared(zombieSquare, ctsq)
                    end
                end
                if currentDist2 ~= nil and nearestDistance + 25 < currentDist2 then
                    shouldRetarget = true
                end
            end
            if shouldRetarget and nearestNpc ~= nil then
                local success, err = pcall(function()
                    nearestNpc:TestZombieSpotPlayer(zombie)
                    if not validTarget(zombie:getTarget()) or zombie:getTarget() ~= nearestNpc then
                        local bridge = rawget(_G, "KnoxJavaBridge")
                        if bridge ~= nil and bridge.directZombieAtNpc ~= nil then
                            local result = tostring(bridge:directZombieAtNpc(nearestId, zombie))
                            if string.find(result, "ZOMBIE_DIRECTED", 1, true) ~= 1 then
                                error(result)
                            end
                        end
                    end
                end)
                if not success and ticks - lastFailureReport >= REPORT_COOLDOWN_TICKS then
                    lastFailureReport = ticks
                    print("[KnoxSurvivors][ZombieAwareness] failed=" .. tostring(err))
                end
            end
        end
    end
end

return ZombieAwareness
