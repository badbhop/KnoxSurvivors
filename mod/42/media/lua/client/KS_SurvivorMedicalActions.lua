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
