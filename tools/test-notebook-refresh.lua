local root = arg[1] or "."
local file = assert(io.open(root .. "/mod/42/media/lua/client/KS_SurvivorNotebook.lua"))
local source = file:read("*a"); file:close()
Window = {}
local methods = assert(source:match("(function Window:refreshContent%(.-)\nfunction Window:onJoypadDown"))
assert(loadstring(methods))()
local now = 0
getTimestampMs = function() return now end
ISCollapsableWindowJoypad = { prerender = function() end }
local list = {items = {{knoxKey = "a"}, {knoxKey = "b"}}, selected = 2,
    getYScroll = function() return -30 end, setYScroll = function(self, value) self.scroll = value end}
local calls = 0
local active = { list = list, populate = function(self)
    calls = calls + 1
    self.list.items = {{knoxKey = "b"}, {knoxKey = "a"}}
end }
local window = setmetatable({playerNum = 0, panel = {getActiveView = function() return active end},
    isVisible = function() return true end}, {__index = Window})
window:prerender()
assert(calls == 1 and list.selected == 1 and list.scroll == -30, "refresh must preserve selected identity and scroll")
for i = 1, 100 do window:prerender() end
assert(calls == 1, "render frames must not repeatedly refresh")
now = 2000; window:prerender(); assert(calls == 2)
local otherCalls = 0
active = {populate = function() otherCalls = otherCalls + 1 end}
window:prerender(); assert(otherCalls == 1 and calls == 2, "switching tab only refreshes active page")
window.isCollapsed = true; now = 4000; window:prerender(); assert(otherCalls == 1)
assert(source:find("local CrewView", 1, true)
    and source:find("function CrewView:onCrewPriorityCell", 1, true)
    and source:find("function CrewView:onSelectTool", 1, true)
    and source:find("function CrewView:onPaintHour", 1, true)
    and source:find("function CrewView:onPresetColony", 1, true)
    and source:find("function CrewView:onPresetNight", 1, true)
    and source:find("function CrewView:onPresetClear", 1, true)
    and source:find("function CrewView:onSaveSchedule", 1, true)
    and source:find("Unsaved changes", 1, true)
    and source:find('self.panel:addView("Crew", self.crewView)', 1, true)
    and source:find("setBaseWorkPriorities", 1, true)
    and source:find("setBaseDutySchedule", 1, true),
    "crew tab must unite roster, priority cells and tool-painted hours with role and party controls")
assert(source:find("local WorldView", 1, true)
    and source:find("function WorldView:memberRole", 1, true)
    and source:find('self.panel:addView("World", self.worldView)', 1, true)
    and source:find("getFactionRelationship", 1, true),
    "world tab must merge factions and survivors with member roles")
assert(source:find("local function notebookBaseId", 1, true)
    and source:find("self.basePicker", 1, true)
    and source:find("refreshAllViews", 1, true),
    "base tabs must resolve a selected home across multiple bases")
assert(source:find("function MissionsView:onSupplyToParty", 1, true)
    and source:find("function MissionsView:onSupplyToBase", 1, true)
    and source:find("function MissionsView:onSupplyResume", 1, true)
    and source:find("KnoxBasePicker", 1, true),
    "missions must callback supply orders to party, base of choice, or duty")
assert(source:find("self.partyList", 1, true)
    and source:find("self.resList", 1, true)
    and source:find("Party — traveling with you", 1, true),
    "crew roster must separate party from residents")
assert(source:find("self.cardPortrait", 1, true)
    and source:find("function WorldView:factionHistory", 1, true)
    and source:find("function WorldView:factionStats", 1, true),
    "world factions need portrait cards, headcounts and conflict history")
do
    -- Lua resolves file-locals only forward: shared tables must be
    -- declared above every view method that reads them, or tabs resolve
    -- a nil global and die on open (the Crew __len crash).
    local crewAt = source:find("local CrewView", 1, true)
    assert(crewAt ~= nil, "crew view present")
    for _, name in ipairs({ "local PRIORITY_COLUMNS", "local PRIORITY_COLORS",
        "local SCHEDULE_TOOLS", "local SCHEDULE_COLORS",
        "local BASE_JOB_CHOICES", "local function workStatusFor" }) do
        local at = source:find(name, 1, true)
        assert(at ~= nil and at < crewAt, name .. " must precede CrewView")
    end
end

do
    -- Every player-facing window must scale font-relatively (same factor
    -- as the card) so high-DPI displays and big TVs keep proportions
    -- instead of clipping text inside fixed pixels.
    local function readUI(name)
        local file = assert(io.open(root .. "/mod/42/media/lua/client/" .. name, "r"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local hud = readUI("KS_CompanionHUD.lua")
    assert(hud:find("self.panelWidth = math.floor(188 * fontScale)", 1, true),
        "companion HUD width must scale with UI fonts")
    local picker = readUI("KS_BasePicker.lua")
    assert(picker:find("local width = math.floor(WIDTH * scale)", 1, true),
        "base picker must scale with UI fonts")
    local trade = readUI("KS_TradeUI.lua")
    assert(trade:find("math.floor(680*scale)", 1, true),
        "trade window must scale with UI fonts")
    local feed = readUI("KS_ActivityFeed.lua")
    assert(feed:find("math.floor(WINDOW_WIDTH * scale)", 1, true),
        "activity feed must scale with UI fonts")
    local card = readUI("KS_SurvivorCard.lua")
    assert(card:find("math.floor(WINDOW_WIDTH * scale)", 1, true),
        "survivor card resolution refits must keep the font scale factor")
end
print("Notebook refresh PASS selection=true scroll=true bounded=true activeOnly=true collapsed=true crew=true world=true")
