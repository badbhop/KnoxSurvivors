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
    and source:find("function CrewView:onCycleHour", 1, true)
    and source:find("function CrewView:onSaveSchedule", 1, true)
    and source:find('self.panel:addView("Crew", self.crewView)', 1, true)
    and source:find("setBaseWorkPriorities", 1, true)
    and source:find("setBaseDutySchedule", 1, true),
    "crew tab must unite roster, priority cells and the hours strip with role and party controls")
assert(source:find("local WorldView", 1, true)
    and source:find("function WorldView:memberRole", 1, true)
    and source:find('self.panel:addView("World", self.worldView)', 1, true)
    and source:find("getFactionRelationship", 1, true),
    "world tab must merge factions and survivors with member roles")
print("Notebook refresh PASS selection=true scroll=true bounded=true activeOnly=true collapsed=true crew=true world=true")
