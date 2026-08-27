local rootPath = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local setup = read(rootPath .. "/mod/42/media/lua/client/KS_BaseSetup.lua")
assert(string.find(setup, 'require "ISUI/ISComboBox"', 1, true),
    "Base Setup must use the vanilla combo box")
assert(string.find(setup, 'local TABS = { "Overview", "Residents", "Work Areas", "Storage", "Tasks" }', 1, true),
    "Base Setup must expose the core management tabs")
assert(string.find(setup, 'KnoxBaseTerritorySelector.start', 1, true),
    "boundary editing must use the existing selector")
assert(string.find(setup, 'KnoxBaseZoneSelector.start', 1, true),
    "work areas must use the existing selector")
assert(string.find(setup, 'KnoxCompanionService.sendToBase', 1, true),
    "party recall must use the companion service")

local context = read(rootPath .. "/mod/42/media/lua/client/KS_BaseContextMenu.lua")
assert(string.find(context, 'require "KS_BaseSetup"', 1, true),
    "world base menu must load Base Setup")
assert(string.find(context, '"Open Base Setup"', 1, true),
    "world base menu must expose Base Setup")

local party = read(rootPath .. "/mod/42/media/lua/client/KS_PartyCommands.lua")
assert(string.find(party, 'require "KS_BaseSetup"', 1, true),
    "party menu must load Base Setup")
assert(string.find(party, 'KnoxBaseSetup.show', 1, true),
    "party menu must be able to open Base Setup")

local notebook = read(rootPath .. "/mod/42/media/lua/client/KS_SurvivorNotebook.lua")
assert(string.find(notebook, '"Residents", "Away"', 1, true),
    "Notebook must distinguish residents and unloaded survivors")
assert(string.find(notebook, 'KnoxPersistence.getAwayTeams', 1, true),
    "Notebook must list real persisted teams separately from unloaded survivors")
assert(string.find(notebook, 'Scout results do not create items.', 1, true),
    "Notebook must not imply away missions generate free resources")

print("Base setup UI PASS tabs=true selectors=true menu_wiring=true notebook=true")
