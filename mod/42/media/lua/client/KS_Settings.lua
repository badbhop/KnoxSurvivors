local Settings = rawget(_G, "KnoxSettings") or {}
_G.KnoxSettings = Settings

local DEFAULTS = {
    Enabled = true,
    WorldPopulation = 16,
    MaxActiveSurvivors = 8,
    PopulationRefillDays = 3,
    MinimumSpawnDistance = 60,
    CompanionLimit = 4,
    AllowNPCFactions = true,
    AllowHostileEncounters = true,
    ShowCompanionHUD = true,
    ShowActivityFeed = true,
    EnableDeveloperTools = false,
    DeveloperScenario = 1,
    DeveloperSpawnDistance = 10,
    AllowDestructiveDeveloperTests = false,
    ShowDeveloperDiagnostics = true,
}

local SCENARIOS = {
    [1] = "none",
    [2] = "single",
    [3] = "companion",
    [4] = "group",
    [5] = "faction",
    [6] = "faction_base",
}

local function values()
    local sandbox = rawget(_G, "SandboxVars")
    local configured = type(sandbox) == "table" and sandbox.KnoxSurvivors or nil
    return type(configured) == "table" and configured or DEFAULTS
end

local function value(name)
    local configured = values()[name]
    if configured ~= nil then
        return configured
    end
    return DEFAULTS[name]
end

local function integer(name, minimum, maximum)
    local number = math.floor(tonumber(value(name)) or DEFAULTS[name])
    return math.max(minimum, math.min(maximum, number))
end

function Settings.enabled()
    return value("Enabled") ~= false
end

function Settings.worldPopulation()
    return integer("WorldPopulation", 0, 64)
end

function Settings.maxActiveSurvivors()
    return integer("MaxActiveSurvivors", 1, 16)
end

function Settings.populationRefillDays()
    return integer("PopulationRefillDays", 1, 30)
end

function Settings.minimumSpawnDistance()
    return integer("MinimumSpawnDistance", 25, 150)
end

function Settings.companionLimit()
    return integer("CompanionLimit", 1, 12)
end

function Settings.allowNPCFactions()
    return value("AllowNPCFactions") ~= false
end

function Settings.allowHostileEncounters()
    return value("AllowHostileEncounters") ~= false
end

function Settings.showCompanionHUD()
    return Settings.enabled() and value("ShowCompanionHUD") ~= false
end

function Settings.showActivityFeed()
    return Settings.enabled() and value("ShowActivityFeed") ~= false
end

function Settings.developerToolsEnabled()
    return Settings.enabled() and value("EnableDeveloperTools") == true
end

function Settings.developerScenario()
    return SCENARIOS[integer("DeveloperScenario", 1, 6)] or "none"
end

function Settings.developerSpawnDistance()
    return integer("DeveloperSpawnDistance", 6, 30)
end

function Settings.allowDestructiveDeveloperTests()
    return Settings.developerToolsEnabled()
        and value("AllowDestructiveDeveloperTests") == true
end

function Settings.showDeveloperDiagnostics()
    return Settings.developerToolsEnabled()
        and value("ShowDeveloperDiagnostics") ~= false
end

return Settings
