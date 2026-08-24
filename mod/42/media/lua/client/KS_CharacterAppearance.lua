local KnoxCharacterAppearance = rawget(_G, "KnoxCharacterAppearance") or {}
_G.KnoxCharacterAppearance = KnoxCharacterAppearance

local function wear(bridge, id, fullType, replaceExisting)
    local success, result = pcall(function()
        if id == nil then
            return bridge:wearTestNpcItem(fullType)
        end
        if replaceExisting and bridge.dressNpcItem ~= nil then
            return bridge:dressNpcItem(id, fullType)
        end
        return bridge:wearNpcItem(id, fullType)
    end)
    return success and string.find(tostring(result), "WORN", 1, true) == 1, result
end

-- Uses the same default definitions and probability rule as B42's character creator.
function KnoxCharacterAppearance.randomizeNewTestSurvivor(bridge)
    return KnoxCharacterAppearance.randomizeNewSurvivor(bridge, nil)
end

local function dressDefinitions(bridge, id, definition, female, replaceExisting)
    if definition == nil then
        return true, 0
    end
    local genderDefinition = female and definition.Female
        or (definition.Male or definition.Female)
    if genderDefinition == nil then
        return true, 0
    end
    local worn = 0
    for _, selection in pairs(genderDefinition) do
        local chance = selection.chance
        if (chance == nil or ZombRand(100) < chance) and #selection.items > 0 then
            local fullType = selection.items[ZombRand(0, #selection.items) + 1]
            local success, result = wear(bridge, id, fullType, replaceExisting)
            if not success then
                return false, result
            end
            worn = worn + 1
        end
    end
    return true, worn
end

local function traitDefinition(id)
    local traits = CharacterTraitDefinition.getTraits()
    for index = 0, traits:size() - 1 do
        local definition = traits:get(index)
        if definition ~= nil and tostring(definition:getType()) == id then
            return definition
        end
    end
    return nil
end

function KnoxCharacterAppearance.randomizeNewSurvivor(bridge, id, capabilities)
    if ClothingSelectionDefinitions == nil or ClothingSelectionDefinitions.default == nil then
        return false, "character_creator_definitions_unavailable"
    end

    local female
    if id == nil then
        female = bridge:isTestNpcFemale()
    else
        female = bridge:isNpcFemale(id)
    end
    local success, worn = dressDefinitions(
        bridge,
        id,
        ClothingSelectionDefinitions.default,
        female,
        false
    )
    if not success then
        return false, worn
    end

    local professionId = capabilities ~= nil and capabilities.professionId or nil
    local professionKey = professionId ~= nil
        and string.match(professionId, "([^:]+)$")
        or nil
    local professionDefinition = professionKey ~= nil
        and ClothingSelectionDefinitions[professionKey]
        or nil
    local professionOk, professionWorn = dressDefinitions(
        bridge,
        id,
        professionDefinition,
        female,
        true
    )
    if not professionOk then
        return false, professionWorn
    end
    worn = worn + professionWorn

    if TraitClothingSelectionDefinitions ~= nil then
        for _, traitId in ipairs(capabilities ~= nil and capabilities.traitIds or {}) do
            local trait = traitDefinition(traitId)
            local definition = trait ~= nil
                and TraitClothingSelectionDefinitions[trait:getType()]
                or nil
            local traitOk, traitWorn = dressDefinitions(
                bridge,
                id,
                definition,
                female,
                true
            )
            if not traitOk then
                return false, traitWorn
            end
            worn = worn + traitWorn
        end
    end

    -- A restrained extra roll gives some survivors plausible carried capacity at origin.
    local bag = "none"
    local testConfig = rawget(_G, "KnoxDevTests")
    local forceStarterBag = testConfig ~= nil and testConfig.forceStarterBag == true
    if forceStarterBag or ZombRand(100) < 15 then
        bag = ZombRand(4) == 0 and "Base.Bag_DuffelBagTINT" or "Base.Bag_Schoolbag"
        local success, result = wear(bridge, id, bag, false)
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
