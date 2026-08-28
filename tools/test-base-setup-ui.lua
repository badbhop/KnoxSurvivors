local rootPath = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local notebook = read(rootPath .. "/mod/42/media/lua/client/KS_SurvivorNotebook.lua")
assert(string.find(notebook, 'require "ISUI/ISCollapsableWindowJoypad"', 1, true),
    "Notebook must use the vanilla collapsable window pattern")
assert(string.find(notebook, 'self.baseView:createChildren()', 1, true)
    and string.find(notebook, 'self.residentsView:createChildren()', 1, true)
    and string.find(notebook, 'self.workView:createChildren()', 1, true)
    and string.find(notebook, 'self.missionsView:createChildren()', 1, true)
    and string.find(notebook, 'self.survivorsView:createChildren()', 1, true)
    and string.find(notebook, 'self.factionsView:createChildren()', 1, true),
    "Notebook tab controls must be created before the tab is populated")
for _, tab in ipairs({ '"Base"', '"Residents"', '"Work"', '"Missions"', '"Survivors"', '"Factions"' }) do
    assert(string.find(notebook, tab, 1, true), "Notebook must expose all management tabs")
end
assert(string.find(notebook, 'KnoxBaseTerritorySelector.start', 1, true),
    "boundary editing must use the existing selector")
assert(string.find(notebook, 'KnoxBaseZoneSelector.start', 1, true),
    "work areas must use the existing selector")
assert(string.find(notebook, 'KnoxCompanionService.sendToBase', 1, true),
    "party recall must use the companion service")
assert(string.find(notebook, 'KnoxPersistence.getAwayTeams', 1, true),
    "Notebook must list real persisted teams separately from unloaded survivors")
assert(string.find(notebook, 'getAwayTeamProgress', 1, true)
    and string.find(notebook, 'remainingHours', 1, true)
    and string.find(notebook, 'statusLabel', 1, true),
    "Notebook mission rows must show durable status and remaining time")
assert(string.find(notebook, 'Storage is assigned by right-clicking a container inside the base.', 1, true),
    "Notebook must direct physical storage assignment through the world context menu")
assert(string.find(notebook, '"Cancel Selected"', 1, true)
    and string.find(notebook, '"Resume Selected"', 1, true)
    and string.find(notebook, 'KnoxPersistence.cancelBaseTask', 1, true)
    and string.find(notebook, 'KnoxPersistence.resumeBaseTask', 1, true),
    "Work tab must allow safe cancellation and resume of unclaimed base tasks")
assert(string.find(notebook, 'KnoxSurvivorViewModel.getSurvivor', 1, true)
    and string.find(notebook, 'KnoxPersistence.getFactions', 1, true)
    and string.find(notebook, 'KnoxPersistence.getFactionRelationship', 1, true),
    "Notebook must expose durable survivor, faction, and relation records")
assert(string.find(notebook, '"Set Job"', 1, true)
    and string.find(notebook, 'KnoxPersistence.setBaseJobPreference', 1, true),
    "Residents tab must expose the persisted base-job preference control")

local context = read(rootPath .. "/mod/42/media/lua/client/KS_BaseContextMenu.lua")
assert(not string.find(context, 'require "KS_BaseSetup"', 1, true),
    "retired Base Setup window must not be loaded")
assert(string.find(context, '"Open Base Management"', 1, true),
    "world base menu must open unified Base Management")
assert(string.find(context, 'KnoxSurvivorNotebook.show', 1, true),
    "world base menu must route to the Notebook")

local party = read(rootPath .. "/mod/42/media/lua/client/KS_PartyCommands.lua")
assert(not string.find(party, 'require "KS_BaseSetup"', 1, true),
    "party menu must not load the retired Base Setup window")
assert(string.find(party, 'KnoxSurvivorNotebook.show', 1, true),
    "party menu must open unified Base Management")

print("Base management UI PASS notebook=true selectors=true menu_wiring=true")
