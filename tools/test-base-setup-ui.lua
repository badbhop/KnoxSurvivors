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
assert(not string.find(notebook, 'self.baseView:createChildren()', 1, true)
    and not string.find(notebook, 'self.crewView:createChildren()', 1, true)
    and not string.find(notebook, 'self.workView:createChildren()', 1, true)
    and not string.find(notebook, 'self.missionsView:createChildren()', 1, true)
    and not string.find(notebook, 'self.worldView:createChildren()', 1, true),
    "vanilla addView lifecycle must create each tab's controls exactly once")
assert(string.find(notebook, 'math.floor(760*scale)', 1, true)
    and string.find(notebook, 'getFontHeight(UIFont.Small) / 14', 1, true)
    and string.find(notebook, 'left+(sw-width)/2', 1, true)
    and string.find(notebook, 'top+(sh-height)/2', 1, true),
    "Notebook must scale font-relatively within a viewport-clamped centered size")
assert(string.find(notebook, 'function Window:fitToPlayerViewport', 1, true)
    and string.find(notebook, 'self:setWidth(width)', 1, true)
    and string.find(notebook, 'self:setHeight(height)', 1, true),
    "reopened Notebook must refit after resolution, window-mode, or split-screen changes")
assert(string.find(notebook, 'local function trimText', 1, true)
    and string.find(notebook, 'drawListText', 1, true),
    "long player-facing rows must be clipped inside their list")
assert(string.find(notebook, 'Security: ', 1, true)
    and string.find(notebook, 'guardPosts', 1, true)
    and string.find(notebook, 'patrolRoutes', 1, true)
    and string.find(notebook, 'activeGuard', 1, true)
    and string.find(notebook, 'activePatrol', 1, true),
    "Base tab must expose compact guard and patrol coverage")
assert(string.find(notebook, 'local function workStatusFor', 1, true)
    and string.find(notebook, 'Now: ', 1, true)
    and string.find(notebook, 'KnoxOrderCatalog.label(work.taskType', 1, true)
    and string.find(notebook, 'work.offscreen == true', 1, true)
    and string.find(notebook, 'taskLabel = "Resting"', 1, true),
    "Crew tab must show each survivor's live task, job and schedule state")
assert(string.find(notebook, 'KnoxBaseJobs.settlementSummary', 1, true)
    and string.find(notebook, 'taskRowText(t, now)', 1, true)
    and string.find(notebook, 'reserve.missing', 1, true),
    "Base tab must show authoritative shortages and blocked task detail")
for _, tab in ipairs({ '"Base"', '"Crew"', '"Missions"', '"World"' }) do
    assert(string.find(notebook, tab, 1, true), "Notebook must expose all management tabs")
end
assert(not string.find(notebook, 'local ResidentsView', 1, true)
    and not string.find(notebook, 'local PrioritiesView', 1, true)
    and not string.find(notebook, 'local SurvivorsView', 1, true)
    and not string.find(notebook, 'local FactionsView', 1, true),
    "split roster/priority/survivor/faction tabs must be unified, not duplicated")
assert(string.find(notebook, 'KnoxBaseTerritorySelector.start', 1, true),
    "boundary editing must use the existing selector")
assert(string.find(notebook, 'KnoxBaseZoneSelector.start', 1, true),
    "work areas must use the existing selector")
assert(string.find(notebook, 'KnoxCompanionService.sendToBase', 1, true)
    and string.find(notebook, 'KnoxBasePicker', 1, true),
    "party recall must use the shared service boundary with a base choice when several homes exist")
assert(string.find(notebook, 'KnoxPersistence.getAwayTeams', 1, true),
    "Notebook must list real persisted teams separately from unloaded survivors")
assert(string.find(notebook, 'getAwayTeamProgress', 1, true)
    and string.find(notebook, 'remainingHours', 1, true)
    and string.find(notebook, 'statusLabel', 1, true),
    "Notebook mission rows must show durable status and remaining time")
assert(string.find(notebook, 'Right-click a container at home > Use for', 1, true),
    "Notebook must direct physical storage assignment through the world context menu")
assert(string.find(notebook, '"Cancel"', 1, true)
    and string.find(notebook, '"Resume"', 1, true)
    and string.find(notebook, 'KnoxPersistence.cancelBaseTask', 1, true)
    and string.find(notebook, 'KnoxPersistence.resumeBaseTask', 1, true)
    and string.find(notebook, 'function BaseView:onAssignTask', 1, true),
    "Base tab must allow safe cancellation, resume and assignment of base tasks")
assert(string.find(notebook, 'self.basePicker', 1, true)
    and string.find(notebook, 'notebookBaseId', 1, true)
    and string.find(notebook, 'Security: no guard posts', 1, true),
    "Base tab must switch between multiple homes with readable workforce and security lines")
assert(string.find(notebook, 'KnoxSurvivorViewModel.getSurvivor', 1, true)
    and string.find(notebook, 'KnoxPersistence.getFactions', 1, true)
    and string.find(notebook, 'KnoxPersistence.getFactionRelationship', 1, true),
    "Notebook must expose durable survivor, faction, and relation records")
assert(string.find(notebook, '"Set Job"', 1, true)
    and string.find(notebook, 'KnoxCompanionService.issueOrder', 1, true)
    and not string.find(notebook, 'KnoxPersistence.setBaseJobPreference', 1, true),
    "Crew tab must use the canonical order boundary for base-job preferences")
assert(string.find(notebook, 'self.showHighlights.enable=false', 1, true),
    "Build 42 tick boxes must not use the ISButton-only setEnable method")
assert(string.find(notebook, 'self.jobPicker:setEnabled', 1, true),
    "Build 42 combo boxes must use setEnabled")
assert(string.find(notebook, 'KnoxOrderCatalog.basePreferenceOrder', 1, true),
    "Notebook job picker must use the shared base-preference catalogue")

local context = read(rootPath .. "/mod/42/media/lua/client/KS_BaseContextMenu.lua")
assert(not string.find(context, 'require "KS_BaseSetup"', 1, true),
    "retired Base Setup window must not be loaded")
assert(string.find(context, '"Open Base Management"', 1, true),
    "world base menu must open unified Base Management")
assert(string.find(context, 'KnoxSurvivorNotebook.show', 1, true),
    "world base menu must route to the Notebook")
assert(string.find(context, '"Move Home Base Here"', 1, true)
    and string.find(context, 'KnoxBaseManager.movePlayerBase', 1, true)
    and string.find(context, 'ISModalDialog:new', 1, true),
    "claiming another building must use a confirmation-backed base relocation")

local survivorContext = read(rootPath .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua")
assert(string.find(survivorContext, 'KnoxOrderCatalog.label("follow")', 1, true),
    "base residents expose Follow for temporary companion activation")
assert(string.find(survivorContext, "residentInventoryLabel", 1, true),
    "base residents expose the same native inventory access as companions")

local baseManager = read(rootPath .. "/mod/42/media/lua/client/KS_BaseManager.lua")
assert(string.find(baseManager, 'KnoxSurvivorRuntime.notifyDutyChanged', 1, true),
    "faction base creation must notify active residents of the duty handoff")
assert(not string.find(baseManager, 'ensureFactionZone(base, "construction"', 1, true),
    "construction areas retired: no defense-construction work area generated")
local establishPlayer = baseManager:match(
    "function BaseManager%.establishPlayerBase.-function BaseManager%.movePlayerBase"
)
local movePlayer = baseManager:match(
    "function BaseManager%.movePlayerBase.-function BaseManager%.ensureFactionBase"
)
assert(establishPlayer ~= nil and not establishPlayer:find("ensureFactionZones", 1, true)
    and movePlayer ~= nil and not movePlayer:find("ensureFactionZones", 1, true),
    "player base establish/move must not create automatic work areas")
assert(not notebook:find('label = "Repair Area"', 1, true)
    and not notebook:find('label = "General Work Area"', 1, true),
    "redundant repair/general overlays must not be offered as player work areas")
assert(not string.find(baseManager, 'findAnimalCareSquare', 1, true)
    and not string.find(baseManager, 'IsoFeedingTrough', 1, true),
    "animal care retired (vanilla zones later)")
assert(string.find(baseManager, 'discarded-stale-faction-base', 1, true),
    "faction base restoration must reject a stale record owned by another domain")
assert(not string.find(baseManager, "KnoxToolCupboard.designate", 1, true),
    "NPC bases no longer designate a central cupboard (typed storages only)")
assert(not string.find(baseManager, "local function nextMissing()", 1, true),
    "category storage discovery is retired")
assert(string.find(baseManager, 'ensureFactionZone(base, "log_processing"', 1, true),
    "new bases must receive a dedicated log-processing work area")
assert(string.find(baseManager, 'residentCount >= 4', 1, true)
    and string.find(baseManager, 'countZoneType(base, "guard") < 2', 1, true)
    and string.find(baseManager, '"Outer Watch"', 1, true),
    "larger bases must receive a second deterministic guard post")
assert(string.find(baseManager, 'residentCount >= 6', 1, true)
    and string.find(baseManager, 'countZoneType(base, "patrol") < 2', 1, true)
    and string.find(baseManager, '"Outer Patrol"', 1, true),
    "established bases must receive a second deterministic patrol route")

local party = read(rootPath .. "/mod/42/media/lua/client/KS_PartyCommands.lua")
assert(not string.find(party, 'require "KS_BaseSetup"', 1, true),
    "party menu must not load the retired Base Setup window")
assert(string.find(party, 'KnoxSurvivorNotebook.show', 1, true),
    "party menu must open unified Base Management")
assert(string.find(party, '"Survival Orders"', 1, true)
    and string.find(party, 'areaDirective("find_food"', 1, true)
    and string.find(party, 'areaDirective("find_water"', 1, true)
    and string.find(party, 'areaDirective("find_medical"', 1, true),
    "party menu must expose bounded survival missions")

print("Base management UI PASS notebook=true selectors=true menu_wiring=true")
