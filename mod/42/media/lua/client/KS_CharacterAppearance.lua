local KnoxCharacterAppearance = rawget(_G, "KnoxCharacterAppearance") or {}
_G.KnoxCharacterAppearance = KnoxCharacterAppearance

local function wear(bridge, fullType)
    local success, result = pcall(function()
        return bridge:wearTestNpcItem(fullType)
    end)
    return success and string.find(tostring(result), "WORN", 1, true) == 1, result
end

-- Uses the same default definitions and probability rule as B42's character creator.
function KnoxCharacterAppearance.randomizeNewTestSurvivor(bridge)
    if ClothingSelectionDefinitions == nil or ClothingSelectionDefinitions.default == nil then
        return false, "character_creator_definitions_unavailable"
    end

    local female = bridge:isTestNpcFemale()
    local definition = female
        and ClothingSelectionDefinitions.default.Female
        or ClothingSelectionDefinitions.default.Male
    local worn = 0
    for _, selection in pairs(definition) do
        local chance = selection.chance
        if (chance == nil or ZombRand(100) < chance) and #selection.items > 0 then
            local fullType = selection.items[ZombRand(0, #selection.items) + 1]
            local success, result = wear(bridge, fullType)
            if not success then
                return false, result
            end
            worn = worn + 1
        end
    end

    -- A restrained extra roll gives some survivors plausible carried capacity at origin.
    local bag = "none"
    local testConfig = rawget(_G, "KnoxDevTests")
    local forceStarterBag = testConfig ~= nil and testConfig.forceStarterBag == true
    if forceStarterBag or ZombRand(100) < 15 then
        bag = ZombRand(4) == 0 and "Base.Bag_DuffelBagTINT" or "Base.Bag_Schoolbag"
        local success, result = wear(bridge, bag)
        if not success then
            return false, result
        end
        worn = worn + 1
    end

    return true,
        "gender=" .. (female and "female" or "male")
            .. " worn=" .. tostring(worn)
            .. " bag=" .. bag
end
