require "TimedActions/ISApplyBandage"
require "TimedActions/ISTimedActionQueue"

local MedicalActions = rawget(_G, "KnoxMedicalActions") or {}
_G.KnoxMedicalActions = MedicalActions

local KnoxNpcApplyBandage = ISApplyBandage:derive("KnoxNpcApplyBandage")

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
    return ISApplyBandage.complete(self)
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

function MedicalActions.queueBandage(character, item, bodyPart)
    if character == nil or item == nil or bodyPart == nil then
        return nil, "missing_treatment_input"
    end
    local action = KnoxNpcApplyBandage:new(character, item, bodyPart)
    ISTimedActionQueue.add(action)
    return action, "queued"
end

-- Survivor-to-survivor first aid: the same native bandage action with a
-- distinct doctor and patient. The engine owns approach validation,
-- animation, and bandage consumption; Lua only lines up a nearby bleeding
-- ally, a carried bandage, and adjacency. Constructor shape mirrors the
-- proven self-bandage path with only the patient swapped in.
local KnoxNpcAidBandage = ISApplyBandage:derive("KnoxNpcAidBandage")

function KnoxNpcAidBandage:isValid()
    return self.item ~= nil and self.patient ~= nil
        and self.character:getInventory():contains(self.item)
        and self.bodyPart:HasInjury()
        and not self.bodyPart:bandaged()
end

function KnoxNpcAidBandage:waitToStart()
    return false
end

function KnoxNpcAidBandage:new(doctor, patient, item, bodyPart)
    local action = ISApplyBandage.new(self, doctor, patient, item, bodyPart, true)
    action.patient = patient
    return action
end

function MedicalActions.findBandageItem(doctor)
    if doctor == nil or doctor.getInventory == nil then
        return nil
    end
    local inventory = doctor:getInventory()
    if inventory == nil or inventory.getItems == nil then
        return nil
    end
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil and item.isCanBandage ~= nil then
            local ok, usable = pcall(function()
                return item:isCanBandage() and not item:isBroken()
            end)
            if ok and usable then
                return item
            end
        end
    end
    return nil
end

function MedicalActions.queueAidBandage(doctor, patient, item, bodyPart)
    if doctor == nil or patient == nil or item == nil or bodyPart == nil then
        return nil, "missing_aid_input"
    end
    if doctor == patient then
        return MedicalActions.queueBandage(doctor, item, bodyPart)
    end
    local action = nil
    local ok, result = pcall(function()
        return KnoxNpcAidBandage:new(doctor, patient, item, bodyPart)
    end)
    if not ok or result == nil then
        return nil, "aid_action_unavailable"
    end
    action = result
    ISTimedActionQueue.add(action)
    return action, "queued"
end

function MedicalActions.mostUrgentInjury(character)
    if character == nil then
        return nil
    end
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

return MedicalActions
