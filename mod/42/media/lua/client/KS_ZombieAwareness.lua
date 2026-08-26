local ZombieAwareness = rawget(_G, "KnoxZombieAwareness") or {}
_G.KnoxZombieAwareness = ZombieAwareness

-- Off-slot IsoPlayer shells cannot use IsoPlayer.updateLOS because it writes into
-- local-player lighting. This module supplies only the missing discovery/perception
-- edge; zombie locomotion, attack state, animation, hit rolls, and damage stay vanilla.
local AWARENESS_RADIUS_SQUARED = 20 * 20
local SWITCH_MARGIN = 1.0
local NPC_INTERCEPT_RADIUS = 3.0
local REPORT_COOLDOWN_TICKS = 1800
local CLOSE_ATTACK_REFRESH_RADIUS_SQUARED = 2.25 * 2.25
local CLOSE_ATTACK_REFRESH_TICKS = 6
local ACTIVE_TARGET_REFRESH_TICKS = 30
local TARGET_MEMORY_TICKS = 180
local lastFailureReport = -REPORT_COOLDOWN_TICKS
local closeCombatReports = setmetatable({}, { __mode = "k" })
local closeCombatTargets = setmetatable({}, { __mode = "k" })
local targetMemory = setmetatable({}, { __mode = "k" })

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

local function playerTarget(target)
    if target == nil or getSpecificPlayer == nil then
        return false
    end
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for index = 0, math.max(0, tonumber(count) or 1) - 1 do
        if getSpecificPlayer(index) == target then
            return true
        end
    end
    return false
end

local function reportFailure(ticks, result)
    if ticks - lastFailureReport >= REPORT_COOLDOWN_TICKS then
        lastFailureReport = ticks
        print("[KnoxSurvivors][ZombieAwareness] perception_failed=" .. tostring(result))
    end
end

local function directZombie(bridge, zombie, id, ticks)
    local success, result = pcall(function()
        return tostring(bridge:directZombieAtNpc(id, zombie))
    end)
    if not success
        or string.find(result or "", "ZOMBIE_DIRECTED status=", 1, true) ~= 1 then
        reportFailure(ticks, result)
    elseif string.find(result, "status=attack-transition", 1, true) ~= nil
        or string.find(result, "status=blocked-close", 1, true) ~= nil then
        local lastReport = closeCombatReports[zombie] or -REPORT_COOLDOWN_TICKS
        if ticks - lastReport >= 300 then
            closeCombatReports[zombie] = ticks
            print("[KnoxSurvivors][ZombieAwareness] " .. result)
        end
    end
    return success, result
end

local function rememberTarget(zombie, id, ticks, directed)
    local memory = targetMemory[zombie]
    if memory == nil then
        memory = {}
        targetMemory[zombie] = memory
    end
    memory.id = id
    memory.lastSeen = ticks
    if directed then
        memory.lastDirected = ticks
    end
    return memory
end

local function rememberedNpc(controllers, memory, ticks)
    if memory == nil or memory.id == nil
        or ticks - (memory.lastSeen or -TARGET_MEMORY_TICKS - 1) > TARGET_MEMORY_TICKS then
        return nil
    end
    local controller = controllers ~= nil and controllers[memory.id] or nil
    local npc = controller ~= nil and controller.character or nil
    return validNpc(npc) and npc or nil
end

function ZombieAwareness.update(controllers, orderedIds, ticks)
    if getCell() == nil then
        return
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.directZombieAtNpc == nil then
        return
    end

    -- The NPC shell has no LOS render channel of its own. Once a zombie is in the
    -- bite envelope, refresh only that small active set every tick so Build 42's
    -- bCanSeeTarget and targetSeenTime animation gates survive until collision.
    for zombie, entry in pairs(closeCombatTargets) do
        local id = type(entry) == "table" and entry.id or entry
        local controller = controllers ~= nil and controllers[id] or nil
        local npc = controller ~= nil and controller.character or nil
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        local npcSquare = npc ~= nil and npc:getCurrentSquare() or nil
        if zombie == nil or zombie:isDead() or not validNpc(npc)
            or zombieSquare == nil or npcSquare == nil
            or zombie:getTarget() ~= npc
            or zombieSquare:getZ() ~= npcSquare:getZ()
            or distanceSquared(zombieSquare, npcSquare) > CLOSE_ATTACK_REFRESH_RADIUS_SQUARED then
            closeCombatTargets[zombie] = nil
        elseif ticks >= (type(entry) == "table" and entry.nextRefresh or 0) then
            directZombie(bridge, zombie, id, ticks)
            closeCombatTargets[zombie] = {
                id = id,
                nextRefresh = ticks + CLOSE_ATTACK_REFRESH_TICKS,
            }
            rememberTarget(zombie, id, ticks, true)
        end
    end

    if ticks % 15 ~= 0 then
        return
    end
    local zombies = getCell():getZombieList()
    if zombies == nil or zombies:isEmpty() then
        return
    end

    for zombieIndex = 0, zombies:size() - 1 do
        local zombie = zombies:get(zombieIndex)
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and zombieSquare ~= nil then
            local currentTarget = zombie:getTarget()
            local currentNpcId = nil
            local nearestId = nil
            local nearestDistance = AWARENESS_RADIUS_SQUARED + 1

            for _, id in ipairs(orderedIds or {}) do
                local controller = controllers ~= nil and controllers[id] or nil
                local npc = controller ~= nil and controller.character or nil
                if validNpc(npc) then
                    npc:setZombiesDontAttack(false)
                    if currentTarget == npc then
                        currentNpcId = id
                    end
                    local npcSquare = npc:getCurrentSquare()
                    if npcSquare:getZ() == zombieSquare:getZ() then
                        local distance = distanceSquared(zombieSquare, npcSquare)
                        if distance <= AWARENESS_RADIUS_SQUARED and distance < nearestDistance then
                            nearestId = id
                            nearestDistance = distance
                        end
                    end
                end
            end

            local memory = targetMemory[zombie]
            local memoryNpc = rememberedNpc(controllers, memory, ticks)
            local memoryId = memoryNpc ~= nil and memory.id or nil

            local preferredId = rawget(_G, "KnoxCombatTestScenarios") ~= nil
                and KnoxCombatTestScenarios.preferredNpcId ~= nil
                and KnoxCombatTestScenarios.preferredNpcId(zombie) or nil
            local preferredController = preferredId ~= nil and controllers[preferredId] or nil
            if preferredController == nil or not validNpc(preferredController.character) then
                preferredId = nil
            end

            -- Keep a native zombie target stable. Memory is only a fallback when the
            -- engine has temporarily dropped the target; it never overrides a live
            -- player target merely because an NPC is nearby.
            local selectedId = preferredId or currentNpcId
            if selectedId == nil and currentTarget == nil then
                selectedId = memoryId
            end
            if selectedId == nil and nearestId ~= nil then
                if not validTarget(currentTarget) then
                    selectedId = nearestId
                elseif playerTarget(currentTarget) then
                    local targetSquare = currentTarget:getCurrentSquare()
                    if targetSquare ~= nil and targetSquare:getZ() == zombieSquare:getZ() then
                        local currentDistance = math.sqrt(distanceSquared(zombieSquare, targetSquare))
                        local npcDistance = math.sqrt(nearestDistance)
                        if npcDistance <= NPC_INTERCEPT_RADIUS
                            or npcDistance + SWITCH_MARGIN < currentDistance then
                            selectedId = nearestId
                        end
                    end
                end
            end

            if selectedId ~= nil then
                local controller = controllers[selectedId]
                local npc = controller ~= nil and controller.character or nil
                local sameNativeTarget = validNpc(npc) and zombie:getTarget() == npc
                local shouldRefresh = not sameNativeTarget
                if sameNativeTarget then
                    memory = memory or rememberTarget(zombie, selectedId, ticks, false)
                    memory.lastSeen = ticks
                    shouldRefresh = ticks - (memory.lastDirected or -ACTIVE_TARGET_REFRESH_TICKS)
                        >= ACTIVE_TARGET_REFRESH_TICKS
                end
                if shouldRefresh then
                    directZombie(bridge, zombie, selectedId, ticks)
                    rememberTarget(zombie, selectedId, ticks, true)
                else
                    rememberTarget(zombie, selectedId, ticks, false)
                end
                if validNpc(npc) and zombie:getTarget() == npc
                    and distanceSquared(zombieSquare, npc:getCurrentSquare())
                        <= CLOSE_ATTACK_REFRESH_RADIUS_SQUARED then
                    closeCombatTargets[zombie] = {
                        id = selectedId,
                        nextRefresh = ticks + CLOSE_ATTACK_REFRESH_TICKS,
                    }
                end
            elseif currentTarget == nil then
                targetMemory[zombie] = nil
                closeCombatTargets[zombie] = nil
            end
        end
    end
end

return ZombieAwareness
