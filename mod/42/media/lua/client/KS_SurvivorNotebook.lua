require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISTabPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "KS_Persistence"
require "KS_SurvivorViewModel"
require "KS_BaseManager"
require "KS_BaseTaskBoard"
require "KS_BaseJobs"
require "KS_BaseStorage"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"
require "KS_BaseHighlights"
require "KS_BaseZoneSelector"
require "KS_BaseTerritorySelector"
require "KS_CompanionService"
require "KS_SurvivorCard"
require "KS_ActivityFeed"
require "KS_OrderCatalog"
local UILayout = require "KS_SurvivorUILayout"

local Notebook = rawget(_G, "KnoxSurvivorNotebook") or {}
_G.KnoxSurvivorNotebook = Notebook

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorNotebookWindow")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10

local function trimText(font, value, availableWidth)
    local text = tostring(value or "")
    local width = math.max(8, tonumber(availableWidth) or 8)
    if getTextManager():MeasureStringX(font, text) <= width then return text end
    local suffix = "..."
    while #text > 0 and getTextManager():MeasureStringX(font, text .. suffix) > width do
        text = string.sub(text, 1, #text - 1)
    end
    return text .. suffix
end

local function drawListText(list, y, item, alpha)
    list:drawText(trimText(list.font, item.text or "", list:getWidth() - 20),
        10, y + 2, 1, 1, 1, alpha, list.font)
end

local function addRow(list, key, description)
    -- Vanilla addItem takes display text first, then the caller's data.
    -- Keep stable identity separately for selection across a refresh.
    local row = list:addItem(description, key, description)
    row.knoxKey = key
    return row
end

local ZONE_TYPES = {
    { label = "Guard Post", kind = "guard" },
    { label = "Patrol Area", kind = "patrol" },
    { label = "Farming Area", kind = "farming" },
    -- No cooking area: survivors cook at any powered stove or microwave in
    -- home territory automatically, and eat/drink on their own needs.
    { label = "Woodcutting Area", kind = "woodcutting" },
    { label = "Log Processing Area", kind = "log_processing" },
    { label = "Corpse Drop Area", kind = "corpse" },
}
local ZONE_COLORS = {
    guard = { r=0.85, g=0.20, b=0.20 }, patrol = { r=0.85, g=0.55, b=0.15 },
    farming = { r=0.20, g=0.70, b=0.20 }, woodcutting = { r=0.55, g=0.35, b=0.15 },
    log_processing = { r=0.60, g=0.42, b=0.18 }, corpse = { r=0.55, g=0.55, b=0.55 },
    cooking = { r=0.75, g=0.35, b=0.30 },
    repair = { r=0.20, g=0.50, b=0.85 },
    general = { r=0.52, g=0.52, b=0.75 },
}
-- Keep the Notebook's resident-role picker on the same catalogue used by the
-- context menu and party orders. This prevents a new base preference from
-- silently appearing in one UI but not the other.
local function baseJobChoices()
    local choices = {}
    for _, value in ipairs(KnoxOrderCatalog.basePreferenceOrder or {}) do
        local entry = KnoxOrderCatalog.basePreferences[value]
        if entry ~= nil then
            choices[#choices + 1] = {
                label = value == "hauling" and "Move Corpses"
                    or entry.label or value,
                value = value,
            }
        end
    end
    return choices
end
local BASE_JOB_CHOICES = baseJobChoices()
local function zoneSize(z)
    if not z or not z.x1 then return nil,nil,nil end
    local w=math.abs(tonumber(z.x2)-tonumber(z.x1))+1
    local h=math.abs(tonumber(z.y2)-tonumber(z.y1))+1
    return w,h,w*h
end

local function workStatusFor(base, survivorId)
    if base == nil or survivorId == nil then return nil end
    if KnoxPersistence.getBaseResidentWorkStatus ~= nil then
        return KnoxPersistence.getBaseResidentWorkStatus(survivorId, base.id)
    end
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.state == "claimed"
            and tostring(task.claimedBy or "") == tostring(survivorId) then
            return { state = "claimed", taskType = task.type }
        end
    end
    return { state = "idle" }
end

local RESOURCE_LABELS = {
    food="Food", water="Water", medical="Medical", weapons="Weapons",
    ammunition="Ammo", tools="Tools", building="Materials",
    farming="Farming", clothing="Clothing", junk="Junk", other="Other",
}

-- Duty-schedule strip. RimWorld rules: one assignment per hour, painted by
-- clicking. Sleep and recreation are no-work windows; work, patrol and
-- guard all work (patrol/guard bias election toward watch tasks). The
-- backend window list stays the sole persisted authority; the strip
-- expands windows to hours for display and compresses back on save
-- (see KnoxPersistence.dutyWindowsToHours/hoursToDutyWindows).
local SCHEDULE_ASSIGNMENT_LABELS = {
    sleep = "Sleep", work = "Work", patrol = "Patrol", guard = "Guard Duty",
    recreation = "Recreation", anything = "Anything",
}
-- Click cycles Sleep -> Work -> Patrol -> Guard Duty -> Recreation -> Anything.
local SCHEDULE_CYCLE = {
    sleep = "work", work = "patrol", patrol = "guard",
    guard = "recreation", recreation = "anything", anything = "sleep",
}
local SCHEDULE_COLORS = {
    sleep = { r = 0.22, g = 0.32, b = 0.78 },
    work = { r = 0.75, g = 0.50, b = 0.16 },
    patrol = { r = 0.95, g = 0.75, b = 0.25 },
    guard = { r = 0.85, g = 0.22, b = 0.22 },
    recreation = { r = 0.30, g = 0.70, b = 0.30 },
    anything = { r = 0.42, g = 0.42, b = 0.42 },
}

local function schedulePreviewText(draft)
    local windows = KnoxPersistence.hoursToDutyWindows ~= nil
        and KnoxPersistence.hoursToDutyWindows(draft) or nil
    if windows == nil then return "Anything around the clock" end
    local parts = {}
    for _, window in ipairs(windows) do
        parts[#parts + 1] = string.format("%02d-%02d %s",
            (tonumber(window.from) or 0) % 24, (tonumber(window.to) or 0) % 24,
            tostring(SCHEDULE_ASSIGNMENT_LABELS[window.assignment] or window.assignment))
    end
    return table.concat(parts, "  ·  ")
end

local function currentScheduleHour()
    local shelter = rawget(_G, "KnoxNightShelter")
    if shelter ~= nil and shelter.currentHour ~= nil then
        local ok, hour = pcall(function() return shelter.currentHour() end)
        if ok then return tonumber(hour) or 12 end
    end
    return 12
end

local function readableReason(value)
    local reason=tostring(value or "")
    if reason=="" then return nil end
    reason=string.gsub(reason,"_"," ")
    return string.upper(string.sub(reason,1,1))..string.sub(reason,2)
end

local function claimantName(survivorId)
    if survivorId==nil then return nil end
    local identity=KnoxPersistence.getSurvivorIdentity(survivorId) or {}
    local name=(tostring(identity.forename or "").." "..tostring(identity.surname or "")):gsub("^%s+",""):gsub("%s+$","")
    return name~="" and name or "Resident"
end

local function taskRowText(task, now)
    local taskKind=tostring(task.type or "task")
    local label=KnoxOrderCatalog.label(taskKind,taskKind)
    local state=tostring(task.state or "queued")
    local detail=state
    if state=="claimed" and task.claimedBy~=nil then
        detail="active: "..tostring(claimantName(task.claimedBy))
    elseif state=="blocked" then
        detail="blocked"
        local reason=readableReason(task.result or task.lastResult)
        if reason~=nil then detail=detail..": "..reason end
        local retryAt=tonumber(task.retryAtHours)
        if retryAt~=nil and retryAt>(tonumber(now) or 0) then
            detail=detail..string.format(" (retry %.1fh)",retryAt-(tonumber(now) or 0))
        end
    elseif state=="queued" then
        detail="waiting"
    end
    return label.." — "..detail.." — priority "..tostring(task.priority or 0)
end

-- Base panel
local BaseView = ISPanelJoypad:derive("KnoxNotebookBaseView")
function BaseView:initialise() ISPanelJoypad.initialise(self) end
function BaseView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y=UI_BORDER_SPACING
    self.infoLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.infoLabel:initialise(); self:addChild(self.infoLabel)
    y=y+FONT_HGT_SMALL+4
    self.boundaryLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.6,0.6,0.8,1,UIFont.Small,true); self.boundaryLabel:initialise(); self:addChild(self.boundaryLabel)
    y=y+FONT_HGT_SMALL+6
    self.helpLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.helpLabel:initialise(); self:addChild(self.helpLabel)
    y=y+FONT_HGT_SMALL+UI_BORDER_SPACING
    self.showHighlights=ISTickBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,"",self,BaseView.onToggleHighlights)
    self.showHighlights:initialise(); self.showHighlights:addOption("Show Highlights"); self:addChild(self.showHighlights)
    self.editBoundaryBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Edit Boundary",self,BaseView.onEditBoundary); self.editBoundaryBtn:initialise(); self.editBoundaryBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.editBoundaryBtn)
    y=y+BUTTON_HGT+6
    self.zoneHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Work Areas",1,1,1,1,UIFont.Small,true); self.zoneHeading:initialise(); self:addChild(self.zoneHeading)
    y=y+FONT_HGT_SMALL+4
    self.zoneList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*6)
    self.zoneList:initialise(); self.zoneList:instantiate(); self.zoneList.itemheight=BUTTON_HGT; self.zoneList.font=UIFont.NewSmall; self.zoneList.doDrawItem=BaseView.drawZone; self.zoneList.drawBorder=true; self:addChild(self.zoneList)
    y=self.zoneList:getBottom()+UI_BORDER_SPACING
    self.zonePicker=ISComboBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,self,nil); self.zonePicker:initialise()
    for _,d in ipairs(ZONE_TYPES) do self.zonePicker:addOption(d.label) end; self.zonePicker.selected=1; self:addChild(self.zonePicker)
    self.addAreaBtn=ISButton:new(self.zonePicker:getRight()+6,y,100,BUTTON_HGT,"Add Area",self,BaseView.onAddArea); self.addAreaBtn:initialise(); self.addAreaBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.addAreaBtn)
    self.removeBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Remove Selected",self,BaseView.onRemove); self.removeBtn:initialise(); self.removeBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.removeBtn)
    -- Hours and priorities moved to the Crew tab; the Base tab keeps
    -- boundary, areas and storage assignment guidance only.
    self.hintLabel=ISLabel:new(UI_BORDER_SPACING,y+BUTTON_HGT+10,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.hintLabel:initialise(); self.hintLabel.name="Set hours and work priorities per survivor in the Crew tab."; self:addChild(self.hintLabel)
end
function BaseView:drawZone(y,item,alt)
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28)
    if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.28,0.45,0.42,0.36) end
    local color=ZONE_COLORS[item.item and item.item.type] or ZONE_COLORS.general
    self:drawRect(0,y,4,self.itemheight-1,0.9,color.r,color.g,color.b)
    drawListText(self, y, item, a); return y+self.itemheight
end
function BaseView:populate(playerNum)
    self.playerNum=playerNum
    local p=getSpecificPlayer(playerNum); local pid=p and KnoxPersistence.ensurePlayerId(p) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if not base then
        self.infoLabel.name=trimText(UIFont.Small,
            "No home base — right-click inside a building to establish one.", self.width-UI_BORDER_SPACING*2)
        self.boundaryLabel.name=""; self.helpLabel.name=trimText(UIFont.NewSmall,
            "Once established, set its boundary and work areas here.", self.width-UI_BORDER_SPACING*2)
        self.zoneList:clear(); addRow(self.zoneList,"none","No base established"); self.showHighlights:setSelected(1,false)
        -- ISTickBox exposes `enable` directly in Build 42; setEnable belongs
        -- to ISButton only.
        self.showHighlights.enable=false; self.editBoundaryBtn:setEnable(false); self.addAreaBtn:setEnable(false); self.removeBtn:setEnable(false)
        return
    end
    local residents=KnoxPersistence.getBaseResidentIds(base.id)
    local zones=0
    for _, zone in pairs(base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false then
            zones=zones+1
        end
    end
    local queued,claimed=0,0
    for _,t in pairs(base.tasks or {}) do
        if t.state=="queued" then queued=queued+1
        elseif t.state=="claimed" then
            claimed=claimed+1
        end
    end
    local security = KnoxBaseJobs ~= nil and KnoxBaseJobs.securityCoverage ~= nil
        and KnoxBaseJobs.securityCoverage(base)
        or { guardPosts=0, patrolRoutes=0, activeGuard=0, activePatrol=0,
            staffed=0, available=0, required=0, understaffed=0 }
    local workforce = KnoxBaseJobs ~= nil and KnoxBaseJobs.workforceSummary ~= nil
        and KnoxBaseJobs.workforceSummary(base)
        or { residents=#residents, working=claimed, resting=0, idle=0 }
    self.infoLabel.name=trimText(UIFont.Small, (base.name or "Home Base")
        .. "  |  Residents: " .. #residents .. "  |  Zones: " .. zones
        .. "  |  Tasks: " .. queued .. " queued, " .. claimed .. " active"
        .. "  |  Workforce: " .. tostring(workforce.working or 0) .. " working, "
        .. tostring(workforce.idle or 0) .. " idle, " .. tostring(workforce.resting or 0) .. " resting"
        .. "  |  Security: " .. security.activeGuard .. "/" .. security.guardPosts .. " guard, "
        .. security.activePatrol .. "/" .. security.patrolRoutes .. " patrol"
        .. " (" .. security.staffed .. "/" .. security.required .. " staffed)",
        self.width-UI_BORDER_SPACING*2)
    local area=base.territory or base.home or {}
    self.boundaryLabel.name=trimText(UIFont.Small,
        "Boundary: " .. tostring(area.minX or "?") .. "," .. tostring(area.minY or "?")
            .. " to " .. tostring(area.maxX or "?") .. "," .. tostring(area.maxY or "?")
            .. "  (all floors)", self.width-UI_BORDER_SPACING*2)
    self.showHighlights:setSelected(1, KnoxBaseHighlights.isEnabled(playerNum))
    self.helpLabel.name=trimText(UIFont.NewSmall,
        "Storage is assigned by right-clicking a container inside the base.",
        self.width-UI_BORDER_SPACING*2)
    self.showHighlights.enable=true; self.editBoundaryBtn:setEnable(true); self.addAreaBtn:setEnable(true); self.removeBtn:setEnable(self.zoneList.selected and self.zoneList.selected > 0)
    self.zoneList:clear()
    local list={}; for _,z in pairs(base.zones or {}) do if z and z.enabled~=false then list[#list+1]=z end end
    table.sort(list, function(a,b) if tostring(a.type)==tostring(b.type) then return tostring(a.label or a.type) < tostring(b.label or b.type) end return tostring(a.type) < tostring(b.type) end)
    if #list==0 then addRow(self.zoneList,"none","No work areas — pick a type and Add Area, then drag rectangle") else
        for _,z in ipairs(list) do local w,h,total=zoneSize(z); local sz=w and ("  " .. w .. "x" .. h .. " (" .. total .. ")  at " .. z.x1 .. "," .. z.y1) or ""; addRow(self.zoneList,z.id, "  " .. tostring(z.label or z.type) .. " [" .. tostring(z.type) .. "]" .. sz); self.zoneList.items[#self.zoneList.items].item={type=z.type, id=z.id} end
    end
end
function BaseView:getWindow() return self:getParent():getParent() end
function BaseView:onToggleHighlights(_, selected) KnoxBaseHighlights.setEnabled(self:getWindow().playerNum or self.playerNum or 0, selected == true) end
function BaseView:onEditBoundary()
    local win=self:getWindow(); local pl=getSpecificPlayer(win.playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if base and pl and KnoxBaseTerritorySelector and KnoxBaseTerritorySelector.start(pl, base.id) then win:setVisible(false) end
end
function BaseView:onAddArea()
    local win=self:getWindow(); local pl=getSpecificPlayer(win.playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil; local def=ZONE_TYPES[self.zonePicker.selected or 1]
    if base and pl and def and KnoxBaseZoneSelector and KnoxBaseZoneSelector.start(pl, base.id, def.kind, def.label) then win:setVisible(false) end
end
function BaseView:onRemove()
    local index=self.zoneList.selected or 0; local it=index>0 and self.zoneList.items[index] or nil
    if not it or not it.item or not it.item.id then return end
    local win=self:getWindow(); local pl=getSpecificPlayer(win.playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if base then local removed=KnoxPersistence.removeBaseZone(base.id, it.item.id); if removed then KnoxBaseHighlights.refresh(win.playerNum); KnoxActivityFeed.event("Work area removed."); self:populate(win.playerNum) end end
end
function BaseView:prerender()
    ISPanelJoypad.prerender(self)
    if self.removeBtn and self.zoneList then
        local item=self.zoneList.selected and self.zoneList.items[self.zoneList.selected] or nil
        self.removeBtn:setEnable(item ~= nil and item.item ~= nil and item.item.id ~= nil)
    end
end
function BaseView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Crew panel: the RimWorld work tab. Roster on top; the selected survivor
-- gets a priority row (Auto > 1 > 2 > 3 > 4 > Never per work group) and a
-- 24-hour schedule strip below, plus role and party controls. Priorities
-- and hours save immediately; job roles still apply where automatic.
local CrewView = ISPanelJoypad:derive("KnoxNotebookCrewView")
function CrewView:initialise() ISPanelJoypad.initialise(self) end
function CrewView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y = UI_BORDER_SPACING
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self.list.joypadParent=self; self:addChild(self.list)
    y = self.list:getBottom() + 6
    self.priorityLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.priorityLabel:initialise(); self.priorityLabel.name="Work Priorities"; self:addChild(self.priorityLabel)
    y = y + FONT_HGT_SMALL + 4
    local cellW = math.max(40, math.floor((self.width - UI_BORDER_SPACING * 2 - (#PRIORITY_COLUMNS - 1) * 4) / #PRIORITY_COLUMNS))
    self.crewCells = {}
    for index, col in ipairs(PRIORITY_COLUMNS) do
        local btn = ISButton:new(UI_BORDER_SPACING + (index - 1) * (cellW + 4), y, cellW, BUTTON_HGT,
            col.label .. ":A", self, CrewView.onCrewPriorityCell)
        btn:initialise(); btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }; self:addChild(btn)
        btn.knoxGroup = col.key
        self.crewCells[col.key] = btn
    end
    y = y + BUTTON_HGT + 6
    self.scheduleLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small,true); self.scheduleLabel:initialise(); self:addChild(self.scheduleLabel)
    y = y + FONT_HGT_SMALL + 4
    self.scheduleHourBtns = {}
    local stripW = self.width - UI_BORDER_SPACING * 2
    local hourW = math.max(20, math.floor((stripW - 11 * 2) / 12))
    for row = 0, 1 do
        for col = 0, 11 do
            local hour = row * 12 + col
            local btn = ISButton:new(UI_BORDER_SPACING + col * (hourW + 2), y + row * (BUTTON_HGT + 2),
                hourW, BUTTON_HGT, string.format("%02d", hour), self, CrewView.onCycleHour)
            btn:initialise(); btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
            btn.knoxHour = hour
            self:addChild(btn)
            self.scheduleHourBtns[hour + 1] = btn
        end
    end
    y = y + 2 * BUTTON_HGT + 2 + 6
    self.saveScheduleBtn=ISButton:new(UI_BORDER_SPACING,y,120,BUTTON_HGT,"Save Hours",self,CrewView.onSaveSchedule); self.saveScheduleBtn:initialise(); self.saveScheduleBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.saveScheduleBtn)
    self.resetScheduleBtn=ISButton:new(self.saveScheduleBtn:getRight()+6,y,110,BUTTON_HGT,"Use Anything",self,CrewView.onResetSchedule); self.resetScheduleBtn:initialise(); self.resetScheduleBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.resetScheduleBtn)
    self.resetPrioritiesBtn=ISButton:new(self.resetScheduleBtn:getRight()+6,y,120,BUTTON_HGT,"Auto Priorities",self,CrewView.onResetPriorities); self.resetPrioritiesBtn:initialise(); self.resetPrioritiesBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.resetPrioritiesBtn)
    y = y + BUTTON_HGT + 4
    self.scheduleStatus=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall,true); self.scheduleStatus:initialise(); self:addChild(self.scheduleStatus)
    y = y + FONT_HGT_SMALL + 4
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,y,95,BUTTON_HGT,"View Card",self,CrewView.onView); self.viewBtn:initialise(); self.viewBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.viewBtn)
    self.joinPartyBtn=ISButton:new(self.viewBtn:getRight()+6,y,95,BUTTON_HGT,"Join Party",self,CrewView.onJoinParty); self.joinPartyBtn:initialise(); self.joinPartyBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.joinPartyBtn)
    self.sendHomeBtn=ISButton:new(self.joinPartyBtn:getRight()+6,y,120,BUTTON_HGT,"Send Party Home",self,CrewView.onSendHome); self.sendHomeBtn:initialise(); self.sendHomeBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.sendHomeBtn)
    self.jobPicker=ISComboBox:new(self.sendHomeBtn:getRight()+6,y,125,BUTTON_HGT,self,nil); self.jobPicker:initialise(); for _,choice in ipairs(BASE_JOB_CHOICES) do self.jobPicker:addOption(choice.label) end; self.jobPicker.selected=1; self:addChild(self.jobPicker)
    self.setJobBtn=ISButton:new(self.jobPicker:getRight()+6,y,80,BUTTON_HGT,"Set Job",self,CrewView.onSetJob); self.setJobBtn:initialise(); self.setJobBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.setJobBtn)
end
function CrewView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight end
function CrewView:populate(playerNum)
    self.playerNum=playerNum; self.list:clear(); self.ids={}
    local snaps=KnoxSurvivorViewModel.getForPlayer(playerNum) or {}
    local pl=getSpecificPlayer(playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    for _,s in ipairs(snaps) do addRow(self.list,s.id, s.displayName .. "  |  " .. (s.professionLabel or "Survivor") .. "  |  " .. (s.orderLabel or "") .. "  |  " .. (s.activity or "")); self.ids[#self.ids+1]=s.id end
    if base then for _,id in ipairs(KnoxPersistence.getBaseResidentIds(base.id)) do
        local dup=false; for _,e in ipairs(self.ids) do if e==id then dup=true break end end
        if not dup then
            local ident=KnoxPersistence.getSurvivorIdentity(id) or {}
            local duty=KnoxPersistence.getSurvivorDuty(id) or {}
            local prof=KnoxPersistence.getSurvivorCapabilities(id) or {}
            local name=tostring(ident.forename or "").." "..tostring(ident.surname or "")
            local profLabel=KnoxSurvivorCapabilities.professionLabel(prof) or "Survivor"
            local work=workStatusFor(base, id)
            local taskLabel=work ~= nil and work.taskType ~= nil
                and KnoxOrderCatalog.label(work.taskType, work.taskType) or "Idle"
            local taskDetail = nil
            if work ~= nil and work.state == "claimed" and work.offscreen == true then
                taskLabel = taskLabel .. " (off-screen)"
            elseif work ~= nil and (work.state == "supply_order"
                or work.state == "supply_run") then
                taskLabel = "Supply run: " .. taskLabel
            elseif work ~= nil and work.state == "resting" then
                taskLabel = "Resting"
            elseif work ~= nil and work.state == "idle" and work.taskType ~= nil then
                taskDetail = "Last task: " .. taskLabel
            end
            local snapshot = KnoxSurvivorViewModel.getSurvivor ~= nil
                and KnoxSurvivorViewModel.getSurvivor(id, playerNum) or nil
            local currentStatus = snapshot ~= nil and snapshot.activity or taskLabel
            local currentLocation = snapshot ~= nil and snapshot.locationLabel or nil
            if taskDetail == nil and work ~= nil and work.taskType ~= nil
                and snapshot ~= nil and currentStatus ~= taskLabel then
                taskDetail = "Task: " .. taskLabel
            end
            local jobPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
                and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
                or duty.jobPreference
            addRow(self.list,id, name .. "  |  Base  |  Job: "
                .. KnoxOrderCatalog.label(jobPreference or "auto", "Automatic") .. "  |  " .. profLabel
                .. "  |  Now: " .. tostring(currentStatus)
                .. (currentLocation ~= nil and "  |  " .. tostring(currentLocation) or "")
                .. (taskDetail ~= nil and "  |  " .. taskDetail or ""))
            self.ids[#self.ids+1]=id
        end
    end end
    if #self.ids==0 then addRow(self.list,"none","No residents — recruit companions"); self.ids={} end
    self:paintCrewDetail()
end
function CrewView:onView() if self.list.selected>0 and self.ids[self.list.selected] then KnoxSurvivorCard.show(self.playerNum, self.ids[self.list.selected]) end end
function CrewView:onSendHome()
    local p = getSpecificPlayer(self.playerNum)
    if not p then return end
    for _, s in ipairs(KnoxSurvivorViewModel.getForPlayer(self.playerNum) or {}) do
        KnoxCompanionService.issueOrder(p, s.id, "return_to_base")
    end
end
function CrewView:onJoinParty()
    local id=self.ids[self.list.selected or 0]; local player=getSpecificPlayer(self.playerNum)
    if id == nil or player == nil then return end
    local changed, reason = KnoxCompanionService.recallToParty(player, id)
    if changed then
        self:populate(self.playerNum)
    elseif KnoxActivityFeed ~= nil then
        KnoxActivityFeed.event("Could not join party: " .. tostring(readableReason(reason) or "unavailable") .. ".")
    end
end
function CrewView:onSetJob()
    local id=self.ids[self.list.selected or 0]; local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    local duty=id and KnoxPersistence.getSurvivorDuty(id) or nil; local base=playerId and KnoxBaseManager.getForOwner("player",playerId) or nil
    local choice=BASE_JOB_CHOICES[self.jobPicker.selected or 1]
    if id == nil or duty == nil or base == nil or duty.mode ~= "base" or duty.baseId ~= base.id or choice == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    -- Keep the notebook on the same canonical order boundary as the context
    -- menu and party controls.  The companion service still validates that
    -- this is a resident of the player's base, persists the preference, and
    -- notifies the loaded controller; the notebook only owns presentation.
    local changed = KnoxCompanionService.issueOrder(
        player,
        id,
        choice.value
    )
    if changed then
        KnoxActivityFeed.event("Base job preference set to " .. string.lower(choice.label) .. ".")
        self:populate(self.playerNum)
    end
end

function CrewView:getWindow() return self:getParent():getParent() end

function CrewView:selectedCrewId()
    if self.ids == nil or #self.ids == 0 then return nil end
    return self.ids[self.list.selected or 1] or self.ids[1]
end

function CrewView:crewBase()
    local p = getSpecificPlayer(self.playerNum or 0)
    local pid = p ~= nil and KnoxPersistence.ensurePlayerId(p) or nil
    return pid ~= nil and KnoxBaseManager.getForOwner("player", pid) or nil
end

function CrewView:schedulePlayerAndBase()
    local win = self:getWindow()
    local playerNum = (win ~= nil and win.playerNum) or self.playerNum or 0
    local player = getSpecificPlayer(playerNum)
    local pid = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = pid ~= nil and KnoxBaseManager.getForOwner("player", pid) or nil
    return player, base, playerNum
end

-- Drafts are 24-entry hour arrays living on the view (never persisted)
-- until Save Hours compresses them to backend windows. A missing draft
-- expands the saved schedule, or the default rota for display only.
function CrewView:scheduleDraftFor(residentId)
    self.scheduleDrafts = self.scheduleDrafts or {}
    if residentId == nil then return nil end
    local draft = self.scheduleDrafts[residentId]
    if draft == nil then
        local saved = KnoxPersistence.getDutySchedule ~= nil
            and KnoxPersistence.getDutySchedule(residentId) or nil
        local source = saved
        if source == nil and KnoxPersistence.defaultDutySchedule ~= nil then
            source = KnoxPersistence.defaultDutySchedule()
        end
        draft = KnoxPersistence.dutyWindowsToHours ~= nil
            and KnoxPersistence.dutyWindowsToHours(source) or {}
        self.scheduleDrafts[residentId] = draft
    end
    return draft
end

function CrewView:paintScheduleStrip(draft)
    local now = currentScheduleHour() % 24
    for hour = 0, 23 do
        local btn = self.scheduleHourBtns ~= nil and self.scheduleHourBtns[hour + 1] or nil
        if btn ~= nil then
            local assignment = type(draft) == "table" and draft[hour + 1] or nil
            if SCHEDULE_COLORS[assignment] == nil then assignment = "anything" end
            local color = SCHEDULE_COLORS[assignment]
            btn.backgroundColor = { r = color.r, g = color.g, b = color.b, a = 0.85 }
            if hour == now and draft ~= nil then
                btn.borderColor = { r = 1, g = 1, b = 1, a = 0.95 }
            else
                btn.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
            end
            btn:setEnable(draft ~= nil)
        end
    end
end

function CrewView:crewDisplayName(residentId)
    local identity = KnoxPersistence.getSurvivorIdentity(residentId) or {}
    local name = (tostring(identity.forename or "") .. " "
        .. tostring(identity.surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Resident " .. tostring(residentId) end
    return name
end

function CrewView:paintCrewDetail()
    local id = self:selectedCrewId()
    local duty = id ~= nil and KnoxPersistence.getSurvivorDuty(id) or nil
    local base = self:crewBase()
    local resident = duty ~= nil and duty.mode == "base"
        and base ~= nil and duty.baseId == base.id
    -- Priority row for the selected survivor.
    local map = id ~= nil and KnoxPersistence.getWorkPriorities ~= nil
        and KnoxPersistence.getWorkPriorities(id) or nil
    for _, col in ipairs(PRIORITY_COLUMNS) do
        local btn = self.crewCells[col.key]
        local value = map ~= nil and map[col.key] or nil
        local title, color
        if value == false then
            title, color = "X", PRIORITY_COLORS.never
        elseif type(value) == "number" and PRIORITY_COLORS[value] ~= nil then
            title, color = tostring(value), PRIORITY_COLORS[value]
        else
            title, color = "A", PRIORITY_COLORS.auto
        end
        btn:setTitle(col.label .. ":" .. title)
        btn.backgroundColor = { r = color.r, g = color.g, b = color.b, a = 0.9 }
        btn:setEnable(resident)
    end
    -- Schedule strip for the selected resident.
    local draft = resident and self:scheduleDraftFor(id) or nil
    self:paintScheduleStrip(draft)
    if id == nil then
        self.scheduleLabel.name = "Schedule"
        self.scheduleStatus.name = ""
    else
        local hour = currentScheduleHour()
        local saved = KnoxPersistence.getDutySchedule ~= nil
            and KnoxPersistence.getDutySchedule(id) or nil
        local assignment = KnoxPersistence.scheduleAssignmentFor ~= nil
            and KnoxPersistence.scheduleAssignmentFor(saved, hour) or "anything"
        self.scheduleLabel.name = trimText(UIFont.Small,
            "Schedule — " .. self:crewDisplayName(id) .. "  (Now: "
            .. tostring(SCHEDULE_ASSIGNMENT_LABELS[assignment] or assignment) .. ")",
            self.width - UI_BORDER_SPACING * 2)
        if not resident then
            self.scheduleStatus.name = "Schedules and priorities apply to base residents."
        else
            local status = workStatusFor(base, id) or {}
            self.scheduleStatus.name = trimText(UIFont.NewSmall,
                (saved == nil and "Default rota (not saved). " or "Custom. ")
                .. schedulePreviewText(draft or {}) .. "  |  "
                .. "Task: " .. tostring(status.state or "idle")
                .. (status.taskType ~= nil and (" (" .. tostring(status.taskType) .. ")") or "")
                .. "  |  Job: " .. tostring(duty.jobPreference or "auto"),
                self.width - UI_BORDER_SPACING * 2)
        end
    end
    -- Role picker follows the selected resident's stored preference.
    if resident then
        local pref = KnoxOrderCatalog.normalizeBasePreference ~= nil
            and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
            or duty.jobPreference
        for index, choice in ipairs(BASE_JOB_CHOICES) do
            if choice.value == pref then self.jobPicker.selected = index; break end
        end
    end
end

function CrewView:onCrewPriorityCell(button)
    local group = button ~= nil and button.knoxGroup or nil
    local residentId = self:selectedCrewId()
    if group == nil or residentId == nil then return end
    local map = KnoxPersistence.getWorkPriorities ~= nil
        and KnoxPersistence.getWorkPriorities(residentId) or {}
    if type(map) ~= "table" then map = {} end
    local current = map[group]
    if current == nil then map[group] = 1
    elseif current == 1 then map[group] = 2
    elseif current == 2 then map[group] = 3
    elseif current == 3 then map[group] = 4
    elseif current == 4 then map[group] = false
    else map[group] = nil end
    local any = false
    for _, value in pairs(map) do if value ~= nil then any = true; break end end
    local player = getSpecificPlayer(self.playerNum or 0)
    local service = rawget(_G, "KnoxCompanionService")
    local ok = false
    if player ~= nil and service ~= nil and service.setBaseWorkPriorities ~= nil then
        ok = service.setBaseWorkPriorities(player, residentId, any and map or nil)
    end
    if ok then
        self:populate(self.playerNum or 0)
    else
        KnoxActivityFeed.event("Could not set work priority.")
    end
end

function CrewView:onResetPriorities()
    local player, base = self:schedulePlayerAndBase()
    local residentId = self:selectedCrewId()
    if player == nil or base == nil or residentId == nil then return end
    local service = rawget(_G, "KnoxCompanionService")
    local ok = false
    if service ~= nil and service.setBaseWorkPriorities ~= nil then
        ok = service.setBaseWorkPriorities(player, residentId, nil)
    end
    KnoxActivityFeed.event(ok and "Work priorities reset to automatic."
        or "Could not reset work priorities.")
    if ok then self:populate(self.playerNum or 0) end
end

function CrewView:onCycleHour(button)
    local hour = button ~= nil and tonumber(button.knoxHour) or nil
    if hour == nil or hour < 0 or hour > 23 then return end
    local residentId = self:selectedCrewId()
    local draft = self:scheduleDraftFor(residentId)
    if residentId == nil or draft == nil then return end
    local current = draft[hour + 1]
    if SCHEDULE_CYCLE[current] == nil then current = "anything" end
    draft[hour + 1] = SCHEDULE_CYCLE[current]
    self:paintCrewDetail()
end

function CrewView:onSaveSchedule()
    local player, base = self:schedulePlayerAndBase()
    if player == nil or base == nil then return end
    local residentId = self:selectedCrewId()
    local draft = self:scheduleDraftFor(residentId)
    if residentId == nil or draft == nil then return end
    -- All-anything compresses to nil: back to the default rota, unsaved.
    local windows = KnoxPersistence.hoursToDutyWindows ~= nil
        and KnoxPersistence.hoursToDutyWindows(draft) or nil
    local service = rawget(_G, "KnoxCompanionService")
    local ok = false
    if service ~= nil and service.setBaseDutySchedule ~= nil then
        ok = service.setBaseDutySchedule(player, residentId, windows)
    end
    KnoxActivityFeed.event(ok and "Schedule saved."
        or "Could not save schedule.")
    if ok then self:paintCrewDetail() end
end

function CrewView:onResetSchedule()
    local player, base = self:schedulePlayerAndBase()
    if player == nil or base == nil then return end
    local residentId = self:selectedCrewId()
    if residentId == nil then return end
    local service = rawget(_G, "KnoxCompanionService")
    local ok = false
    if service ~= nil and service.setBaseDutySchedule ~= nil then
        ok = service.setBaseDutySchedule(player, residentId, nil)
    end
    if ok and self.scheduleDrafts ~= nil then
        self.scheduleDrafts[residentId] = nil
    end
    KnoxActivityFeed.event(ok and "Schedule cleared — anything goes."
        or "Could not clear schedule.")
    if ok then self:paintCrewDetail() end
end
function CrewView:prerender()
    ISPanelJoypad.prerender(self)
    local id = self:selectedCrewId()
    local duty = id ~= nil and KnoxPersistence.getSurvivorDuty(id) or nil
    local base = self:crewBase()
    local resident = duty ~= nil and duty.mode == "base" and base ~= nil and duty.baseId == base.id
    self.viewBtn:setEnable(id ~= nil)
    self.joinPartyBtn:setEnable(resident)
    self.jobPicker:setEnabled(resident)
    self.setJobBtn:setEnable(resident)
    self.saveScheduleBtn:setEnable(resident)
    self.resetScheduleBtn:setEnable(resident)
    self.resetPrioritiesBtn:setEnable(resident)
end
function CrewView:onJoypadDown(b,jd) if b==Joypad.AButton and self.list.selected>0 then self:onView() end; ISPanelJoypad.onJoypadDown(self,b,jd) end
function CrewView:new(x,y,w,h)
    local o=ISPanelJoypad.new(self,x,y,w,h)
    o:noBackground()
    return o
end

-- Work panel: tasks + storage
local WorkView = ISPanelJoypad:derive("KnoxNotebookWorkView")
function WorkView:initialise() ISPanelJoypad.initialise(self) end
function WorkView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y=UI_BORDER_SPACING
    self.taskLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Task Queue",1,1,1,1,UIFont.Small,true); self.taskLabel:initialise(); self:addChild(self.taskLabel)
    y=y+FONT_HGT_SMALL+4
    self.taskList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*6)
    self.taskList:initialise(); self.taskList:instantiate(); self.taskList.itemheight=BUTTON_HGT; self.taskList.font=UIFont.NewSmall; self.taskList.doDrawItem=self.drawTask; self.taskList.drawBorder=true; self:addChild(self.taskList)
    y=self.taskList:getBottom()+6
    self.cancelTaskBtn=ISButton:new(UI_BORDER_SPACING,y,132,BUTTON_HGT,"Cancel Selected",self,WorkView.onCancelTask)
    self.cancelTaskBtn:initialise(); self.cancelTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.cancelTaskBtn)
    self.resumeTaskBtn=ISButton:new(self.cancelTaskBtn:getRight()+6,y,132,BUTTON_HGT,"Resume Selected",self,WorkView.onResumeTask)
    self.resumeTaskBtn:initialise(); self.resumeTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.resumeTaskBtn)
    self.residentPicker=ISComboBox:new(self.resumeTaskBtn:getRight()+6,y,180,BUTTON_HGT,self,nil); self.residentPicker:initialise(); self:addChild(self.residentPicker)
    self.assignTaskBtn=ISButton:new(self.residentPicker:getRight()+6,y,110,BUTTON_HGT,"Assign",self,WorkView.onAssignTask)
    self.assignTaskBtn:initialise(); self.assignTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.assignTaskBtn)
    y=y+BUTTON_HGT+UI_BORDER_SPACING
    self.storageLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Storage",1,1,1,1,UIFont.Small,true); self.storageLabel:initialise(); self:addChild(self.storageLabel)
    y=y+FONT_HGT_SMALL+4
    self.storageList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.storageList:initialise(); self.storageList:instantiate(); self.storageList.itemheight=BUTTON_HGT; self.storageList.font=UIFont.NewSmall; self.storageList.doDrawItem=self.drawStorage; self.storageList.drawBorder=true; self:addChild(self.storageList)
end
function WorkView:drawTask(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight end
function WorkView:drawStorage(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight end
function WorkView:populate(playerNum)
    self.playerNum=playerNum; self.taskList:clear(); self.storageList:clear()
    self.residentIds={}
    self.residentPicker:clear(); self.residentPicker.selected=1
    local p=getSpecificPlayer(playerNum); local pid=p and KnoxPersistence.ensurePlayerId(p) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if not base then self.residentPicker:addOption("No residents"); addRow(self.taskList,"none","No base"); addRow(self.storageList,"none","No base"); self.taskLabel.name="No base"; self.storageLabel.name="No base"; return end
    for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
        local identity=KnoxPersistence.getSurvivorIdentity(residentId) or {}
        local name=(tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then name="Resident " .. tostring(residentId) end
        self.residentIds[#self.residentIds+1]=residentId
        self.residentPicker:addOption(name)
    end
    if #self.residentIds == 0 then self.residentPicker:addOption("No residents") end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local settlement = KnoxBaseJobs ~= nil and KnoxBaseJobs.settlementSummary ~= nil
        and KnoxBaseJobs.settlementSummary(base, now) or nil
    local tasksSummary=settlement~=nil and settlement.tasks or {queued=0,claimed=0,blocked=0}
    local workforce=settlement~=nil and settlement.workforce or {working=0,idle=0,resting=0}
    self.taskLabel.name=trimText(UIFont.Small,
        "Work: " .. tostring(tasksSummary.queued or 0) .. " waiting | "
        .. tostring(tasksSummary.claimed or 0) .. " active | "
        .. tostring(tasksSummary.blocked or 0) .. " blocked"
        .. " | Workforce: " .. tostring(workforce.working or 0) .. " working, "
        .. tostring(workforce.idle or 0) .. " idle, "
        .. tostring(workforce.resting or 0) .. " resting",
        self.width-UI_BORDER_SPACING*2)
    local tasks={}; for _,t in pairs(base.tasks or {}) do tasks[#tasks+1]=t end
    table.sort(tasks, function(a,b) local ap=tonumber(a.priority) or 0; local bp=tonumber(b.priority) or 0; if ap==bp then return tostring(a.id) < tostring(b.id) end return ap>bp end)
    if #tasks==0 then addRow(self.taskList,"none","No work waiting — mark work areas") else for _,t in ipairs(tasks) do
        local taskKind = tostring(t.type or "task")
        addRow(self.taskList,t.id, taskRowText(t, now))
        self.taskList.items[#self.taskList.items].item=t
    end end
    local summary=settlement~=nil and settlement.storage or KnoxBaseStorage.summarize(base)
    local shortageCount=settlement~=nil and #(settlement.shortages or {}) or 0
    local stockState=settlement~=nil and settlement.stockKnown
        and (shortageCount>0 and (tostring(shortageCount).." shortage(s)") or "reserves covered")
        or "stock unavailable"
    self.storageLabel.name=trimText(UIFont.Small,
        "Storage: " .. tostring(#(KnoxBaseStorage.policies(base) or {}))
        .. " assigned | " .. stockState, self.width-UI_BORDER_SPACING*2)
    local any=false
    local assigned = KnoxBaseStorage.policies(base)
    if #assigned == 0 then addRow(self.storageList,"setup","Assign storage: right-click a container at home > Use for ...") end
    for _, policy in ipairs(assigned) do
        local resolved = KnoxBaseStorage.resolvePolicy(policy)
        local text = KnoxBaseStorage.label(policy) .. " (" .. tostring(policy.containerType) .. ") at "
            .. tostring(policy.x) .. ", " .. tostring(policy.y) .. ", floor " .. tostring(policy.z)
        if resolved == nil then text = text .. " — unavailable" end
        addRow(self.storageList,policy.key,text)
    end
    addRow(self.storageList,"food-help","Right-click a container at home > Use for Food, Tools, ...")
    local reserveByCategory={}
    for _,reserve in ipairs(settlement~=nil and settlement.reserves or {}) do reserveByCategory[reserve.category]=reserve end
    for _,cat in ipairs(KnoxBaseStorage.RESOURCE_CATEGORIES) do
        local c=tonumber(summary.totals[cat]) or 0
        local reserve=reserveByCategory[cat]
        if c>0 or reserve~=nil then
            local text=tostring(RESOURCE_LABELS[cat] or cat)..": "..tostring(c)
            if reserve~=nil then
                text=text.." / "..tostring(reserve.target)
                if reserve.missing>0 then text=text.." — needs "..tostring(reserve.missing) end
            end
            addRow(self.storageList,cat,text); any=true
        end
    end
    local other=tonumber(summary.totals.other) or 0; if other>0 then addRow(self.storageList,"other","Other: "..other); any=true end
    if not any then addRow(self.storageList,"none","No supplies in loaded containers") end
    if summary.unavailablePolicies>0 then addRow(self.storageList,"warn", tostring(summary.unavailablePolicies) .. " container(s) outside loaded area") end
end
function WorkView:onAssignTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    local residentId=self.residentIds and self.residentIds[self.residentPicker.selected or 0] or nil
    if task == nil or task.id == nil or task.state ~= "queued" or residentId == nil then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil then return end
    local base=KnoxBaseManager.getForOwner("player", playerId)
    if base == nil then return end
    local assigned,result=KnoxCompanionService.assignBaseTask(player, residentId, base.id, task.id)
    if assigned ~= nil and result == "claimed" then
        KnoxActivityFeed.event("Assigned " .. KnoxOrderCatalog.label(task.type, "work") .. " to the selected resident.")
        self:populate(self.playerNum)
    end
end
function WorkView:onCancelTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    if task == nil or task.id == nil or task.state == "claimed" or task.state == "cancelled" then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    local base=playerId and KnoxBaseManager.getForOwner("player",playerId) or nil
    if base == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local cancelled,result=KnoxPersistence.cancelBaseTask(base.id,task.id,now)
    if cancelled ~= nil and result == "cancelled" then
        KnoxActivityFeed.event("Base task cancelled: " .. KnoxOrderCatalog.label(task.type, "work") .. ".")
        self:populate(self.playerNum)
    end
end
function WorkView:onResumeTask()
    local index=self.taskList.selected or 0; local entry=index>0 and self.taskList.items[index] or nil; local task=entry and entry.item or nil
    if task == nil or task.id == nil or task.state ~= "cancelled" then return end
    local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    local base=playerId and KnoxBaseManager.getForOwner("player",playerId) or nil
    if base == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local resumed,result=KnoxPersistence.resumeBaseTask(base.id,task.id,now)
    if resumed ~= nil and result == "resumed" then
        KnoxActivityFeed.event("Base task resumed: " .. KnoxOrderCatalog.label(task.type, "work") .. ".")
        self:populate(self.playerNum)
    end
end
function WorkView:prerender()
    ISPanelJoypad.prerender(self)
    local entry=self.taskList and self.taskList.selected and self.taskList.items[self.taskList.selected] or nil
    local task=entry and entry.item or nil
    if self.cancelTaskBtn then self.cancelTaskBtn:setEnable(task ~= nil and task.state ~= "claimed" and task.state ~= "cancelled") end
    if self.resumeTaskBtn then self.resumeTaskBtn:setEnable(task ~= nil and task.state == "cancelled") end
    if self.assignTaskBtn then self.assignTaskBtn:setEnable(task ~= nil and task.state == "queued" and self.residentIds ~= nil and #self.residentIds > 0) end
    if self.residentPicker then self.residentPicker:setEnabled(task ~= nil and task.state == "queued" and self.residentIds ~= nil and #self.residentIds > 0) end
end
function WorkView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Missions panel
local MissionsView = ISPanelJoypad:derive("KnoxNotebookMissionsView")
function MissionsView:initialise() ISPanelJoypad.initialise(self) end
function MissionsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,self.height-UI_BORDER_SPACING*2)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
end
function MissionsView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight end
function MissionsView:populate(playerNum)
    self.playerNum = playerNum
    self.list:clear()
    local player = getSpecificPlayer(playerNum)
    local ownerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    if ownerId == nil then return end
    local teams = KnoxPersistence.getAwayTeams and KnoxPersistence.getAwayTeams() or {}
    local now = 0
    local gameTime = rawget(_G, "getGameTime")
    if gameTime ~= nil then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and tonumber(value) ~= nil then now = tonumber(value) end
    end
    local count = 0
    for id, team in pairs(teams) do
        if team ~= nil and team.ownerKind == "player" and team.ownerId == ownerId
            and team.state ~= "complete" and team.state ~= "blocked" then
            count = count + 1
            local progress = KnoxPersistence.getAwayTeamProgress ~= nil
                and KnoxPersistence.getAwayTeamProgress(id, now) or team
            local remaining = tonumber(progress.remainingHours) or 0
            local text = tostring(progress.missionType or "mission")
                .. " | " .. tostring(progress.statusLabel or progress.state or "unknown")
                .. " | " .. tostring(#(progress.memberIds or {})) .. " member(s)"
                .. " | " .. tostring(progress.destination and progress.destination.label or "unknown")
            if progress.state == "outbound" then
                text = text .. " | " .. string.format("%.1fh remaining", remaining)
            end
            addRow(self.list,id, text)
        end
    end
    if count == 0 then addRow(self.list,"none", "No active trips. Give work orders from Residents or a survivor's Orders menu.") end
    for _, id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        if KnoxPersistence.isSurvivorAlive(id) and KnoxSurvivorRuntime.getCharacter(id) == nil then
            local aff = KnoxPersistence.getSurvivorAffiliation(id) or {}
            local duty = KnoxPersistence.getSurvivorDuty(id) or {}
            if aff.kind == "player" and aff.ownerId == ownerId and duty.awayTeamId == nil then
                local snapshot = KnoxSurvivorViewModel.getSurvivor(id, playerNum)
                if snapshot ~= nil then
                    addRow(self.list,id, snapshot.displayName .. " | "
                        .. snapshot.roleLabel .. " | " .. snapshot.activity)
                end
            end
        end
    end
end
function MissionsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Work-priority columns and colors shared by the Crew tab: one column per
-- work group, click a cell to cycle Auto > 1 > 2 > 3 > 4 > Never.
-- 1 is done first. Manual numbers override job roles in the automatic
-- election; direct Assign and manual orders always work.
local PRIORITY_COLUMNS = {
    { key = "guard", label = "Guard" },
    { key = "patrol", label = "Patrol" },
    { key = "cooking", label = "Cook" },
    { key = "farming", label = "Farm" },
    { key = "woodwork", label = "Wood" },
    { key = "barricade", label = "Build" },
    { key = "hauling", label = "Haul" },
    { key = "repair", label = "Repair" },
}
local PRIORITY_COLORS = {
    auto = { r = 0.42, g = 0.42, b = 0.42 },
    [1] = { r = 0.85, g = 0.30, b = 0.12 },
    [2] = { r = 0.85, g = 0.52, b = 0.12 },
    [3] = { r = 0.78, g = 0.68, b = 0.22 },
    [4] = { r = 0.42, g = 0.52, b = 0.42 },
    never = { r = 0.16, g = 0.16, b = 0.16 },
}

-- World panel: everyone else. Non-player factions on top with standing and
-- home; the selected faction's members below with roles (leader, follower,
-- work role, drifter). Unaffiliated known survivors group under Drifters.
-- Read-only by design: standing moves through encounters, not buttons.
local WORLD_JOB_ROLES = {
    auto = "Worker", guard = "Guard", patrol = "Patrol", farming = "Farmer",
    cooking = "Cook", woodwork = "Woodcutter", barricade = "Builder",
    hauling = "Hauler", repair = "Repairer", rest = "Resting",
}

local WorldView = ISPanelJoypad:derive("KnoxNotebookWorldView")
function WorldView:initialise() ISPanelJoypad.initialise(self) end
function WorldView:createChildren()
    ISPanelJoypad.createChildren(self)
    local memberH = BUTTON_HGT * 7
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,self.height-UI_BORDER_SPACING*2-memberH-UI_BORDER_SPACING*2-BUTTON_HGT)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
    self.memberList=ISScrollingListBox:new(UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,memberH)
    self.memberList:initialise(); self.memberList:instantiate(); self.memberList.itemheight=BUTTON_HGT; self.memberList.font=UIFont.NewSmall; self.memberList.doDrawItem=self.drawEntry; self.memberList.drawBorder=true; self:addChild(self.memberList)
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,self.memberList:getBottom()+UI_BORDER_SPACING,110,BUTTON_HGT,"View Card",self,WorldView.onView); self.viewBtn:initialise(); self.viewBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.viewBtn)
end
function WorldView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; drawListText(self,y,item,a); return y+self.itemheight end

function WorldView:memberRole(faction, memberId)
    if faction ~= nil and tostring(faction.leaderId or "") == tostring(memberId) then
        return "Leader"
    end
    local duty = KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(memberId) or nil
    local mode = type(duty) == "table" and tostring(duty.mode or "") or ""
    if mode == "companion" then return "Follower" end
    if mode == "away" then return "Away team" end
    if mode == "base" then
        local pref = duty.jobPreference
        if KnoxOrderCatalog ~= nil and KnoxOrderCatalog.normalizeBasePreference ~= nil then
            pref = KnoxOrderCatalog.normalizeBasePreference(pref)
        end
        return WORLD_JOB_ROLES[tostring(pref or "auto")] or "Worker"
    end
    return "Drifter"
end

function WorldView:memberName(memberId)
    local identity = KnoxPersistence.getSurvivorIdentity(memberId) or {}
    local name = (tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = tostring(memberId) end
    return name
end

function WorldView:factionHome(faction)
    local base = faction.homeBaseId and KnoxPersistence.getBase(faction.homeBaseId) or nil
    local camp = KnoxPersistence.getFactionCamp ~= nil and KnoxPersistence.getFactionCamp(faction.id) or nil
    if base ~= nil then return "Base: " .. tostring(base.name or base.id) end
    if camp ~= nil then return "Shelter: " .. tostring(camp.name or camp.id) end
    return "No home yet"
end

function WorldView:populate(playerNum)
    self.playerNum = playerNum
    self.list:clear(); self.memberList:clear(); self.memberIds = {}
    local player = getSpecificPlayer(playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local playerFaction = playerId ~= nil and KnoxPersistence.getPlayerFaction ~= nil
        and KnoxPersistence.getPlayerFaction(playerId) or nil
    -- Non-player factions first, then unaffiliated known survivors.
    local factions = {}
    for _, faction in pairs(KnoxPersistence.getFactions() or {}) do
        if faction ~= nil and faction.kind ~= "player" then factions[#factions + 1] = faction end
    end
    table.sort(factions, function(a, b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
    local claimed = {}
    for _, faction in ipairs(factions) do
        for _, memberId in ipairs(faction.memberIds or {}) do claimed[tostring(memberId)] = true end
        local standing = "neutral"
        if playerFaction ~= nil and KnoxPersistence.getFactionRelationship ~= nil then
            local saved = KnoxPersistence.getFactionRelationship(playerFaction.id, faction.id)
            standing = tostring(saved and saved.disposition or "neutral")
        end
        addRow(self.list, faction.id, tostring(faction.name or faction.id)
            .. "  |  " .. standing .. "  |  " .. tostring(#(faction.memberIds or {})) .. " members"
            .. "  |  " .. self:factionHome(faction))
    end
    local drifters = {}
    for _, id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        local aff = KnoxPersistence.getSurvivorAffiliation ~= nil
            and KnoxPersistence.getSurvivorAffiliation(id) or {}
        if tostring(aff.kind or "") ~= "player" and claimed[tostring(id)] ~= true then
            local snap = KnoxSurvivorViewModel.getSurvivor ~= nil
                and KnoxSurvivorViewModel.getSurvivor(id, playerNum) or nil
            if snap ~= nil then drifters[#drifters + 1] = id end
        end
    end
    if #drifters > 0 then
        addRow(self.list, "drifters", "Drifters  |  unaffiliated  |  "
            .. tostring(#drifters) .. " known" .. "  |  —")
    end
    if #factions == 0 and #drifters == 0 then
        addRow(self.list, "none", "No other factions yet — survivors you meet will appear here")
    end
    self.factions = factions
    self.drifters = drifters
    self.playerFaction = playerFaction
    self:populateMembers()
end

function WorldView:selectedFaction()
    local selected = self.list.selected or 0
    local row = selected > 0 and self.list.items[selected] or nil
    local key = row ~= nil and tostring(row.knoxKey or "") or ""
    if key == "drifters" then return "drifters" end
    for _, faction in ipairs(self.factions or {}) do
        if faction ~= nil and tostring(faction.id) == key then return faction end
    end
    return (self.factions or {})[1]
end

function WorldView:populateMembers()
    self.memberList:clear(); self.memberIds = {}
    local faction = self:selectedFaction()
    if faction == nil then
        addRow(self.memberList, "none", "Select a faction above")
        return
    end
    local entries = {}
    if faction == "drifters" then
        for _, id in ipairs(self.drifters or {}) do entries[#entries + 1] = { id = id, faction = nil } end
    else
        local standing = "neutral"
        if self.playerFaction ~= nil and KnoxPersistence.getFactionRelationship ~= nil then
            local saved = KnoxPersistence.getFactionRelationship(self.playerFaction.id, faction.id)
            standing = tostring(saved and saved.disposition or "neutral")
        end
        addRow(self.memberList, "standing", "  " .. tostring(faction.name or faction.id)
            .. "  |  " .. standing .. "  |  " .. self:factionHome(faction))
        for _, id in ipairs(faction.memberIds or {}) do entries[#entries + 1] = { id = id, faction = faction } end
    end
    if #entries == 0 then
        addRow(self.memberList, "empty", "  No members recorded")
        return
    end
    local rows = {}
    for _, entry in ipairs(entries) do
        rows[#rows + 1] = { id = entry.id, name = self:memberName(entry.id),
            role = self:memberRole(entry.faction, entry.id) }
    end
    table.sort(rows, function(a, b)
        if a.role == "Leader" and b.role ~= "Leader" then return true end
        if b.role == "Leader" and a.role ~= "Leader" then return false end
        return a.name < b.name
    end)
    for _, row in ipairs(rows) do
        local text = "  " .. row.name .. "  |  " .. row.role
        local alive = KnoxPersistence.isSurvivorAlive ~= nil
            and KnoxPersistence.isSurvivorAlive(row.id) or nil
        if alive == false then
            text = text .. "  |  dead"
        else
            local snap = KnoxSurvivorViewModel.getSurvivor ~= nil
                and KnoxSurvivorViewModel.getSurvivor(row.id, self.playerNum) or nil
            if snap ~= nil and snap.activity ~= nil and tostring(snap.activity) ~= "" then
                text = text .. "  |  " .. tostring(snap.activity)
            end
        end
        addRow(self.memberList, row.id, text)
        self.memberIds[#self.memberIds + 1] = row.id
    end
end

function WorldView:onView()
    local index = self.memberList.selected or 0
    local row = index > 0 and self.memberList.items[index] or nil
    local key = row ~= nil and tostring(row.knoxKey or "") or ""
    if key ~= "" and key ~= "standing" and key ~= "empty" and key ~= "none" then
        KnoxSurvivorCard.show(self.playerNum, key)
    end
end
function WorldView:prerender()
    ISPanelJoypad.prerender(self)
    if self.viewBtn then
        local index = self.memberList.selected or 0
        local row = index > 0 and self.memberList.items[index] or nil
        local key = row ~= nil and tostring(row.knoxKey or "") or ""
        self.viewBtn:setEnable(key ~= "" and key ~= "standing" and key ~= "empty" and key ~= "none")
    end
end
function WorldView:onJoypadDown(b, jd)
    if b == Joypad.AButton and self.memberList.selected > 0 then self:onView() end
    ISPanelJoypad.onJoypadDown(self, b, jd)
end
function WorldView:new(x, y, w, h) local o = ISPanelJoypad.new(self, x, y, w, h); o:noBackground(); return o end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false); self.collapseButton:setVisible(false)
    local th=self:titleBarHeight(); local rh=self:resizeWidgetHeight()
    self.panel=ISTabPanel:new(0, th, self.width, self.height-th-rh)
    self.panel:initialise(); self.panel.tabPadX=10; self.panel.equalTabWidth=false
    self.panel:setAnchorRight(true); self.panel:setAnchorBottom(true); self:addChild(self.panel)
    -- ISTabPanel:addView adds the child and invokes createChildren once. Calling
    -- it here as well duplicates every label/list/button and breaks page layout.
    self.baseView=BaseView:new(0, 8, self.panel.width, self.panel.height-8); self.baseView:initialise(); self.panel:addView("Base", self.baseView)
    self.crewView=CrewView:new(0, 8, self.panel.width, self.panel.height-8); self.crewView:initialise(); self.panel:addView("Crew", self.crewView)
    self.workView=WorkView:new(0, 8, self.panel.width, self.panel.height-8); self.workView:initialise(); self.panel:addView("Work", self.workView)
    self.missionsView=MissionsView:new(0, 8, self.panel.width, self.panel.height-8); self.missionsView:initialise(); self.panel:addView("Away", self.missionsView)
    self.worldView=WorldView:new(0, 8, self.panel.width, self.panel.height-8); self.worldView:initialise(); self.panel:addView("World", self.worldView)
end

function Window:refreshContent()
    local view = self.panel and self.panel:getActiveView() or nil
    if view == nil or view.populate == nil then return end
    local saved = {}
    for _, field in ipairs({"list", "zoneList", "taskList", "storageList", "scheduleList"}) do
        local list = view[field]
        if list ~= nil then
            local row = list.items[list.selected or 0]
            saved[field] = { key = row and row.knoxKey, scroll = list:getYScroll() }
        end
    end
    local resident = view.residentIds and view.residentPicker
        and view.residentIds[view.residentPicker.selected or 0] or nil
    view:populate(self.playerNum)
    for field, state in pairs(saved) do
        local list = view[field]
        list.selected = 0
        for index, row in ipairs(list.items) do
            if state.key ~= nil and row.knoxKey == state.key then list.selected = index; break end
        end
        list:setYScroll(state.scroll)
    end
    if resident ~= nil and view.residentPicker ~= nil then
        view.residentPicker.selected = 0
        for index, id in ipairs(view.residentIds or {}) do
            if id == resident then view.residentPicker.selected = index; break end
        end
    end
    self.refreshedView = view
    self.nextRefreshAt = getTimestampMs() + 2000
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    if self.isCollapsed or not self:isVisible() then return end
    local active = self.panel and self.panel:getActiveView() or nil
    if active ~= self.refreshedView or getTimestampMs() >= (self.nextRefreshAt or 0) then
        self:refreshContent()
    end
end

function Window:onJoypadDown(button, joypadData)
    if button==Joypad.LBumper or button==Joypad.RBumper then
        if self.panel and self.panel.viewList and #self.panel.viewList>1 then
            local idx=self.panel:getActiveViewIndex()
            if button==Joypad.LBumper then idx= idx==1 and #self.panel.viewList or idx-1 else idx= idx==#self.panel.viewList and 1 or idx+1 end
            self.panel:activateView(self.panel.viewList[idx].name); setJoypadFocus(self.playerNum, self.panel:getActiveView()); return
        end
    end
    ISCollapsableWindowJoypad.onJoypadDown(self,button,joypadData)
end

function Window:new(playerNum)
    local rawW,rawH=760,600; local sw=getPlayerScreenWidth(playerNum); local sh=getPlayerScreenHeight(playerNum)
    local width=math.min(rawW, math.max(1, sw-40)); local height=math.min(rawH, math.max(1, sh-40))
    local left=getPlayerScreenLeft(playerNum); local top=getPlayerScreenTop(playerNum)
    local window=ISCollapsableWindowJoypad:new(left+(sw-width)/2, top+(sh-height)/2, width, height)
    setmetatable(window,self); self.__index=self
    window.playerNum=playerNum; window.backgroundColor={r=0.06,g=0.06,b=0.06,a=0.94}; window.borderColor={r=0.28,g=0.28,b=0.28,a=0.95}
    window:setTitle("Knox Survivors"); window:setResizable(false); return window
end

function Window:fitToPlayerViewport(playerNum)
    local sw, sh = getPlayerScreenWidth(playerNum), getPlayerScreenHeight(playerNum)
    local width = math.min(760, math.max(1, sw - 40))
    local height = math.min(600, math.max(1, sh - 40))
    self:setWidth(width)
    self:setHeight(height)
    self:setX(getPlayerScreenLeft(playerNum) + (sw - width) / 2)
    self:setY(getPlayerScreenTop(playerNum) + (sh - height) / 2)
end

function Notebook.show(playerNum)
    playerNum=tonumber(playerNum) or 0
    if Notebook.window==nil then Notebook.window=Window:new(playerNum); Notebook.window:initialise(); Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:addToUIManager()
    else Notebook.window.playerNum=playerNum; Notebook.window:fitToPlayerViewport(playerNum); Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:setVisible(true); Notebook.window:bringToTop() end
    Notebook.window:refreshContent(); return Notebook.window
end
function Notebook.toggle(playerNum) if Notebook.window~=nil and Notebook.window:isVisible() then Notebook.window:setVisible(false) else Notebook.show(playerNum) end end
Events.OnMainMenuEnter.Add(function() if Notebook.window~=nil then Notebook.window:removeFromUIManager(); Notebook.window=nil end end)
return Notebook
