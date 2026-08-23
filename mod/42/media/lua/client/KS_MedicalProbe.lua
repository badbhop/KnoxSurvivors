require "TimedActions/ISApplyBandage"
require "TimedActions/ISTimedActionQueue"

local TAG = "[KnoxSurvivors][TestLab]"
local MAX_TEST_TICKS = 900
local STATUS_INTERVAL_TICKS = 60
local MEDICAL_GATE_KEY = "medical_self_bandage_v1"

local KnoxNpcApplyBandage = ISApplyBandage:derive("KnoxNpcApplyBandage")

-- The stock action updates the selected local player's health panel. Knox NPCs
-- have no local-player UI slot, so retain its animation/sound while keeping the
-- action's progress entirely on the NPC body.
function KnoxNpcApplyBandage:isValid()
    return self.item ~= nil
        and self.character:getInventory():contains(self.item)
        and self.bodyPart:HasInjury()
        and not self.bodyPart:bandaged()
end

function KnoxNpcApplyBandage:waitToStart()
    return false
end

function KnoxNpcApplyBandage:update()
    if self.item ~= nil then
        self.item:setJobDelta(self:getJobDelta())
    end
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function KnoxNpcApplyBandage:start()
    ISApplyBandage.start(self)
    self.knoxBandageAnimationRequested = true
end

function KnoxNpcApplyBandage:stop()
    self:stopSound()
    if self.item ~= nil then
        self.item:setJobDelta(0.0)
    end
    self.bodyPart:setManipulatingUsername(nil)
    ISBaseTimedAction.stop(self)
end

function KnoxNpcApplyBandage:complete()
    local bandageLife = self.item:getBandagePower()
    self.character:getBodyDamage():SetBandaged(
        self.bodyPart:getIndex(),
        true,
        bandageLife,
        self.item:isAlcoholic(),
        self.item:getFullType()
    )
    self.character:getInventory():Remove(self.item)
    self.bodyPart:setManipulatingUsername(nil)
    return true
end

function KnoxNpcApplyBandage:perform()
    self:stopSound()
    if self.item ~= nil then
        self.item:setJobDelta(0.0)
    end
    self.bodyPart:setManipulatingUsername(nil)
    ISBaseTimedAction.perform(self)
end

function KnoxNpcApplyBandage:new(character, item, bodyPart)
    return ISApplyBandage.new(self, character, character, item, bodyPart, true)
end

local ticks = 0
local phase = "IDLE"
local npc = nil
local bodyPart = nil
local bandage = nil
local action = nil
local actionObserved = false
local update

local function report(status, reason, evidence)
    print(
        TAG
            .. " RESULT scenario=medical status="
            .. tostring(status)
            .. " reason="
            .. tostring(reason)
            .. " evidence="
            .. tostring(evidence or "none")
    )
end

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function squareForRecord(bridge, record)
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record),
            bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not success then
        return nil, x
    end
    return getCell():getGridSquare(x, y, z), tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function restoreSurvivor(bridge)
    local persistence = rawget(_G, "KnoxPersistence")
    local record = persistence ~= nil and persistence.getTestRecord() or nil
    if record == nil then
        return false, "missing_persistent_survivor"
    end
    local square, location = squareForRecord(bridge, record)
    if square == nil then
        return false, "saved_square_not_loaded location=" .. tostring(location)
    end
    local success, result = pcall(function()
        return bridge:restoreTestNpcRecord(record, square)
    end)
    return success and string.find(tostring(result), "RESTORED", 1, true) == 1, result
end

local function mostUrgentInjury(character)
    local parts = character:getBodyDamage():getBodyParts()
    local fallback = nil
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        if part:HasInjury() then
            fallback = fallback or part
            if part:bleeding() and not part:bandaged() then
                return part
            end
        end
    end
    return fallback
end

local function fail(reason, evidence)
    report("FAIL", reason, evidence)
    phase = "FINISHED"
    stop()
end

update = function()
    ticks = ticks + 1
    if ticks > MAX_TEST_TICKS then
        fail("timeout", "phase=" .. tostring(phase))
        return
    end

    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getSpecificPlayer(0)
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end

    if phase == "WAIT_START" then
        local restored, result = restoreSurvivor(bridge)
        if not restored then
            if string.find(tostring(result), "saved_square_not_loaded", 1, true) ~= nil then
                return
            end
            fail("survivor_restore_failed", tostring(result))
            return
        end
        npc = bridge:getTestNpcCharacterForAction()
        if npc == nil then
            fail("npc_character_unavailable", tostring(result))
            return
        end
        print(TAG .. " survivor=" .. tostring(result))

        local persistence = rawget(_G, "KnoxPersistence")
        if persistence.isDevGateComplete(MEDICAL_GATE_KEY) then
            report("SKIP", "already_passed", "next=needs_food_water")
            phase = "FINISHED"
            stop()
            return
        end
        if not persistence.isDevGateComplete("health_reload_v1") then
            fail("health_reload_prerequisite_missing", "run_health_scenario_first=true")
            return
        end

        bodyPart = mostUrgentInjury(npc)
        if bodyPart == nil then
            fail("no_saved_injury", "health=" .. tostring(bridge:getTestNpcHealth()))
            return
        end
        bandage = npc:getInventory():getFirstTypeRecurse("Base.Bandage")
        if bandage == nil then
            fail("no_bandage_in_inventory", "loot_gate_item_missing=true")
            return
        end
        action = KnoxNpcApplyBandage:new(npc, bandage, bodyPart)
        ISTimedActionQueue.add(action)
        actionObserved = action.action ~= nil and npc:getCharacterActions():contains(action.action)
        print(
            TAG
                .. " medical-action=QUEUED injury="
                .. tostring(bodyPart:getType())
                .. " item="
                .. tostring(bandage:getFullType())
                .. " durationTicks="
                .. tostring(action.maxTime)
                .. " actionObserved="
                .. tostring(actionObserved)
                .. " animationRequested="
                .. tostring(action.knoxBandageAnimationRequested == true)
        )
        phase = "TREATING"
        return
    end

    if phase ~= "TREATING" then
        return
    end

    if not npc:getCharacterActions():isEmpty() then
        actionObserved = true
    end
    if bodyPart:bandaged() and not npc:getInventory():contains(bandage) then
        if not actionObserved then
            fail("treatment_without_timed_action", tostring(bodyPart:getType()))
            return
        end
        local persistence = rawget(_G, "KnoxPersistence")
        local saved, record = persistence.captureActiveTestSurvivor()
        if not saved then
            fail("post_medical_save_failed", tostring(record))
            return
        end
        persistence.markDevGateComplete("medical")
        persistence.markDevGateComplete(MEDICAL_GATE_KEY)
        report(
            "PASS",
            "self_bandaged_and_saved",
            "injury=" .. tostring(bodyPart:getType())
                .. " actionObserved=" .. tostring(actionObserved)
                .. " animationRequested="
                .. tostring(action.knoxBandageAnimationRequested == true)
                .. " bandaged=" .. tostring(bodyPart:bandaged())
                .. " bleeding=" .. tostring(bodyPart:bleeding())
                .. " inventoryItems=" .. tostring(npc:getInventory():getItems():size())
                .. " next=needs_food_water"
        )
        phase = "FINISHED"
        stop()
        return
    end

    if action ~= nil
        and not ISTimedActionQueue.hasAction(action)
        and npc:getCharacterActions():isEmpty() then
        fail(
            "medical_action_ended_without_bandage",
            "bandaged=" .. tostring(bodyPart:bandaged())
                .. " inventoryContainsItem=" .. tostring(npc:getInventory():contains(bandage))
        )
        return
    end

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(
            TAG
                .. " medical-status=TREATING actionObserved="
                .. tostring(actionObserved)
                .. " bandaged="
                .. tostring(bodyPart:bandaged())
        )
    end
end

local function onGameStart()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "medical" then
        return
    end
    print(TAG .. " START auto=true scenario=medical clearsLoadedZombies=false sandboxOverrides=false")
    ticks = 0
    phase = "WAIT_START"
    npc = nil
    bodyPart = nil
    bandage = nil
    action = nil
    actionObserved = false
    stop()
    Events.OnTick.Add(update)
end

local function onMainMenuEnter()
    if npc ~= nil and action ~= nil and ISTimedActionQueue.hasAction(action) then
        ISTimedActionQueue.clear(npc)
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil then
        persistence.captureActiveTestSurvivor()
    end
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
