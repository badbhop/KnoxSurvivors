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
require "KS_BaseStorage"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"
require "KS_BaseHighlights"
require "KS_BaseZoneSelector"
require "KS_BaseTerritorySelector"
require "KS_CompanionService"
require "KS_SurvivorCard"
require "KS_ActivityFeed"

local Notebook = rawget(_G, "KnoxSurvivorNotebook") or {}
_G.KnoxSurvivorNotebook = Notebook

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorNotebookWindow")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10

local ZONE_TYPES = {
    { label = "Guard Area", kind = "guard" },
    { label = "Patrol Area", kind = "patrol" },
    { label = "Farming Area", kind = "farming" },
    { label = "Woodcutting Area", kind = "woodcutting" },
    { label = "Log Processing Area", kind = "log_processing" },
    { label = "Corpse Drop Area", kind = "corpse" },
    { label = "Animal Care Area", kind = "animal_care" },
    { label = "Repair Area", kind = "repair" },
    { label = "Defense Construction Area", kind = "construction" },
    { label = "General Work Area", kind = "general" },
}
local ZONE_COLORS = {
    guard = { r=0.85, g=0.20, b=0.20 }, patrol = { r=0.85, g=0.55, b=0.15 },
    farming = { r=0.20, g=0.70, b=0.20 }, woodcutting = { r=0.55, g=0.35, b=0.15 },
    log_processing = { r=0.60, g=0.42, b=0.18 }, corpse = { r=0.55, g=0.55, b=0.55 },
    animal_care = { r=0.85, g=0.70, b=0.10 }, repair = { r=0.20, g=0.50, b=0.85 },
    construction = { r=0.70, g=0.40, b=0.85 }, general = { r=0.52, g=0.52, b=0.75 },
}
local BASE_JOB_CHOICES = {
    { label="Automatic", value="auto" }, { label="Guard", value="guard" },
    { label="Patrol", value="patrol" }, { label="Farming", value="farming" },
    { label="Woodwork", value="woodwork" }, { label="Hauling", value="hauling" },
    { label="Animal Care", value="animal_care" }, { label="Repair", value="repair" },
}
local function zoneSize(z)
    if not z or not z.x1 then return nil,nil,nil end
    local w=math.abs(tonumber(z.x2)-tonumber(z.x1))+1
    local h=math.abs(tonumber(z.y2)-tonumber(z.y1))+1
    return w,h,w*h
end

-- Base panel
local BaseView = ISPanelJoypad:derive("KnoxNotebookBaseView")
function BaseView:initialise() ISPanelJoypad.initialise(self) end
function BaseView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y=UI_BORDER_SPACING
    self.infoLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",1,1,1,1,UIFont.Small); self.infoLabel:initialise(); self:addChild(self.infoLabel)
    y=y+FONT_HGT_SMALL+4
    self.boundaryLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.6,0.6,0.8,1,UIFont.Small); self.boundaryLabel:initialise(); self:addChild(self.boundaryLabel)
    y=y+FONT_HGT_SMALL+6
    self.helpLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"",0.62,0.62,0.60,1,UIFont.NewSmall); self.helpLabel:initialise(); self:addChild(self.helpLabel)
    y=y+FONT_HGT_SMALL+UI_BORDER_SPACING
    self.showHighlights=ISTickBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,"",self,BaseView.onToggleHighlights)
    self.showHighlights:initialise(); self.showHighlights:addOption("Show Highlights"); self:addChild(self.showHighlights)
    self.editBoundaryBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Edit Boundary",self,BaseView.onEditBoundary); self.editBoundaryBtn:initialise(); self.editBoundaryBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.editBoundaryBtn)
    y=y+BUTTON_HGT+6
    self.zoneHeading=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Work Areas",1,1,1,1,UIFont.Small); self.zoneHeading:initialise(); self:addChild(self.zoneHeading)
    y=y+FONT_HGT_SMALL+4
    self.zoneList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*6)
    self.zoneList:initialise(); self.zoneList:instantiate(); self.zoneList.itemheight=BUTTON_HGT; self.zoneList.font=UIFont.NewSmall; self.zoneList.doDrawItem=BaseView.drawZone; self.zoneList.drawBorder=true; self:addChild(self.zoneList)
    y=self.zoneList:getBottom()+UI_BORDER_SPACING
    self.zonePicker=ISComboBox:new(UI_BORDER_SPACING,y,190,BUTTON_HGT,self,nil); self.zonePicker:initialise()
    for _,d in ipairs(ZONE_TYPES) do self.zonePicker:addOption(d.label) end; self.zonePicker.selected=1; self:addChild(self.zonePicker)
    self.addAreaBtn=ISButton:new(self.zonePicker:getRight()+6,y,100,BUTTON_HGT,"Add Area",self,BaseView.onAddArea); self.addAreaBtn:initialise(); self.addAreaBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.addAreaBtn)
    self.removeBtn=ISButton:new(self.width-UI_BORDER_SPACING-118,y,118,BUTTON_HGT,"Remove Selected",self,BaseView.onRemove); self.removeBtn:initialise(); self.removeBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.removeBtn)
end
function BaseView:drawZone(y,item,alt)
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28)
    if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.28,0.45,0.42,0.36) end
    local color=ZONE_COLORS[item.item and item.item.type] or ZONE_COLORS.general
    self:drawRect(0,y,4,self.itemheight-1,0.9,color.r,color.g,color.b)
    self:drawText(item.text or "", 10, y+2, 1,1,1,a, self.font); return y+self.itemheight
end
function BaseView:populate(playerNum)
    self.playerNum=playerNum
    local p=getSpecificPlayer(playerNum); local pid=p and KnoxPersistence.ensurePlayerId(p) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if not base then
        self.infoLabel.name="No home base — right-click inside a building to establish one."
        self.boundaryLabel.name=""; self.helpLabel.name="Once established, set its boundary and work areas here."
        self.zoneList:clear(); self.zoneList:addItem("none","No base established"); self.showHighlights:setSelected(1,false)
        self.showHighlights:setEnable(false); self.editBoundaryBtn:setEnable(false); self.addAreaBtn:setEnable(false); self.removeBtn:setEnable(false); return
    end
    local residents=KnoxPersistence.getBaseResidentIds(base.id)
    local zones=0; for _ in pairs(base.zones or {}) do zones=zones+1 end
    local queued,claimed=0,0; for _,t in pairs(base.tasks or {}) do if t.state=="queued" then queued=queued+1 elseif t.state=="claimed" then claimed=claimed+1 end end
    self.infoLabel.name=(base.name or "Home Base") .. "  |  Residents: " .. #residents .. "  |  Zones: " .. zones .. "  |  Tasks: " .. queued .. " queued, " .. claimed .. " active"
    local area=base.territory or base.home or {}
    self.boundaryLabel.name="Boundary: " .. tostring(area.minX or "?") .. "," .. tostring(area.minY or "?") .. " to " .. tostring(area.maxX or "?") .. "," .. tostring(area.maxY or "?") .. "  (all floors)"
    self.showHighlights:setSelected(1, KnoxBaseHighlights.isEnabled(playerNum))
    self.helpLabel.name="Storage is assigned by right-clicking a container inside the base."
    self.showHighlights:setEnable(true); self.editBoundaryBtn:setEnable(true); self.addAreaBtn:setEnable(true); self.removeBtn:setEnable(self.zoneList.selected and self.zoneList.selected > 0)
    self.zoneList:clear()
    local list={}; for _,z in pairs(base.zones or {}) do if z and z.enabled~=false then list[#list+1]=z end end
    table.sort(list, function(a,b) if tostring(a.type)==tostring(b.type) then return tostring(a.label or a.type) < tostring(b.label or b.type) end return tostring(a.type) < tostring(b.type) end)
    if #list==0 then self.zoneList:addItem("none","No work areas — pick a type and Add Area, then drag rectangle") else
        for _,z in ipairs(list) do local w,h,total=zoneSize(z); local sz=w and ("  " .. w .. "x" .. h .. " (" .. total .. ")  at " .. z.x1 .. "," .. z.y1) or ""; self.zoneList:addItem(z.label or z.type, "  " .. tostring(z.label or z.type) .. " [" .. tostring(z.type) .. "]" .. sz); self.zoneList.items[#self.zoneList.items].item={type=z.type, id=z.id} end
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
    if base then local removed=KnoxPersistence.removeBaseZone(base.id, it.item.id); if removed then KnoxActivityFeed.event("Work area removed."); self:populate(win.playerNum) end end
end
function BaseView:prerender()
    ISPanelJoypad.prerender(self)
    if self.removeBtn and self.zoneList then
        local item=self.zoneList.selected and self.zoneList.items[self.zoneList.selected] or nil
        self.removeBtn:setEnable(item ~= nil and item.item ~= nil and item.item.id ~= nil)
    end
end
function BaseView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Residents panel
local ResidentsView = ISPanelJoypad:derive("KnoxNotebookResidentsView")
function ResidentsView:initialise() ISPanelJoypad.initialise(self) end
function ResidentsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,self.height-UI_BORDER_SPACING*2-BUTTON_HGT-UI_BORDER_SPACING)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self.list.joypadParent=self; self:addChild(self.list)
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,110,BUTTON_HGT,"View Card",self,ResidentsView.onView); self.viewBtn:initialise(); self.viewBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.viewBtn)
    self.sendHomeBtn=ISButton:new(self.viewBtn:getRight()+UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,120,BUTTON_HGT,"Send Party Home",self,ResidentsView.onSendHome); self.sendHomeBtn:initialise(); self.sendHomeBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.sendHomeBtn)
    self.jobPicker=ISComboBox:new(self.sendHomeBtn:getRight()+UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,125,BUTTON_HGT,self,nil); self.jobPicker:initialise(); for _,choice in ipairs(BASE_JOB_CHOICES) do self.jobPicker:addOption(choice.label) end; self.jobPicker.selected=1; self:addChild(self.jobPicker)
    self.setJobBtn=ISButton:new(self.jobPicker:getRight()+6,self.list:getBottom()+UI_BORDER_SPACING,95,BUTTON_HGT,"Set Job",self,ResidentsView.onSetJob); self.setJobBtn:initialise(); self.setJobBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.setJobBtn)
end
function ResidentsView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text,10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function ResidentsView:populate(playerNum)
    self.playerNum=playerNum; self.list:clear(); self.ids={}
    local snaps=KnoxSurvivorViewModel.getForPlayer(playerNum) or {}
    local pl=getSpecificPlayer(playerNum); local pid=pl and KnoxPersistence.ensurePlayerId(pl) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    for _,s in ipairs(snaps) do self.list:addItem(s.displayName, s.displayName .. "  |  " .. (s.professionLabel or "Survivor") .. "  |  " .. (s.orderLabel or "") .. "  |  " .. (s.activity or "")); self.ids[#self.ids+1]=s.id end
    if base then for _,id in ipairs(KnoxPersistence.getBaseResidentIds(base.id)) do
        local dup=false; for _,e in ipairs(self.ids) do if e==id then dup=true break end end
        if not dup then local ident=KnoxPersistence.getSurvivorIdentity(id) or {}; local duty=KnoxPersistence.getSurvivorDuty(id) or {}; local prof=KnoxPersistence.getSurvivorCapabilities(id) or {}; local name=tostring(ident.forename or "").." "..tostring(ident.surname or ""); local profLabel=KnoxSurvivorCapabilities.professionLabel(prof) or "Survivor"; self.list:addItem(name, name .. "  |  Base  |  Job: " .. tostring(duty.jobPreference or "auto") .. "  |  " .. profLabel); self.ids[#self.ids+1]=id end
    end end
    if #self.ids==0 then self.list:addItem("none","No residents — recruit companions"); self.ids={} end
end
function ResidentsView:onView() if self.list.selected>0 and self.ids[self.list.selected] then KnoxSurvivorCard.show(self.playerNum, self.ids[self.list.selected]) end end
function ResidentsView:onSendHome() local p=getSpecificPlayer(self.playerNum); if not p then return end; for _,s in ipairs(KnoxSurvivorViewModel.getForPlayer(self.playerNum) or {}) do if KnoxCompanionService.sendToBase(p, s.id) then end end end
function ResidentsView:onSetJob()
    local id=self.ids[self.list.selected or 0]; local player=getSpecificPlayer(self.playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    local duty=id and KnoxPersistence.getSurvivorDuty(id) or nil; local base=playerId and KnoxBaseManager.getForOwner("player",playerId) or nil
    local choice=BASE_JOB_CHOICES[self.jobPicker.selected or 1]
    if id == nil or duty == nil or base == nil or duty.mode ~= "base" or duty.baseId ~= base.id or choice == nil then return end
    local now=getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    if KnoxPersistence.setBaseJobPreference(id,playerId,base.id,choice.value,now) then
        KnoxActivityFeed.event("Base job preference set to " .. string.lower(choice.label) .. ".")
        self:populate(self.playerNum)
    end
end
function ResidentsView:prerender()
    ISPanelJoypad.prerender(self); local id=self.ids and self.ids[self.list.selected or 0] or nil; local duty=id and KnoxPersistence.getSurvivorDuty(id) or nil
    self.viewBtn:setEnable(id~=nil); local resident=duty ~= nil and duty.mode == "base"; self.jobPicker:setEnable(resident); self.setJobBtn:setEnable(resident)
end
function ResidentsView:onJoypadDown(b,jd) if b==Joypad.AButton and self.list.selected>0 then self:onView() end; ISPanelJoypad.onJoypadDown(self,b,jd) end
function ResidentsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Work panel: tasks + storage
local WorkView = ISPanelJoypad:derive("KnoxNotebookWorkView")
function WorkView:initialise() ISPanelJoypad.initialise(self) end
function WorkView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y=UI_BORDER_SPACING
    self.taskLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Task Queue",1,1,1,1,UIFont.Small); self.taskLabel:initialise(); self:addChild(self.taskLabel)
    y=y+FONT_HGT_SMALL+4
    self.taskList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*6)
    self.taskList:initialise(); self.taskList:instantiate(); self.taskList.itemheight=BUTTON_HGT; self.taskList.font=UIFont.NewSmall; self.taskList.doDrawItem=self.drawTask; self.taskList.drawBorder=true; self:addChild(self.taskList)
    y=self.taskList:getBottom()+6
    self.cancelTaskBtn=ISButton:new(UI_BORDER_SPACING,y,132,BUTTON_HGT,"Cancel Selected",self,WorkView.onCancelTask)
    self.cancelTaskBtn:initialise(); self.cancelTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.cancelTaskBtn)
    self.resumeTaskBtn=ISButton:new(self.cancelTaskBtn:getRight()+6,y,132,BUTTON_HGT,"Resume Selected",self,WorkView.onResumeTask)
    self.resumeTaskBtn:initialise(); self.resumeTaskBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.resumeTaskBtn)
    y=y+BUTTON_HGT+UI_BORDER_SPACING
    self.storageLabel=ISLabel:new(UI_BORDER_SPACING,y,BUTTON_HGT,"Storage",1,1,1,1,UIFont.Small); self.storageLabel:initialise(); self:addChild(self.storageLabel)
    y=y+FONT_HGT_SMALL+4
    self.storageList=ISScrollingListBox:new(UI_BORDER_SPACING,y,self.width-UI_BORDER_SPACING*2,BUTTON_HGT*5)
    self.storageList:initialise(); self.storageList:instantiate(); self.storageList.itemheight=BUTTON_HGT; self.storageList.font=UIFont.NewSmall; self.storageList.doDrawItem=self.drawStorage; self.storageList.drawBorder=true; self:addChild(self.storageList)
end
function WorkView:drawTask(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text or "",10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function WorkView:drawStorage(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text or "",10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function WorkView:populate(playerNum)
    self.playerNum=playerNum; self.taskList:clear(); self.storageList:clear()
    local p=getSpecificPlayer(playerNum); local pid=p and KnoxPersistence.ensurePlayerId(p) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if not base then self.taskList:addItem("none","No base"); self.storageList:addItem("none","No base"); self.taskLabel.name="No base"; self.storageLabel.name="No base"; return end
    local queued,claimed=0,0; for _,t in pairs(base.tasks or {}) do if t.state=="queued" then queued=queued+1 elseif t.state=="claimed" then claimed=claimed+1 end end
    self.taskLabel.name="Task Queue: " .. queued .. " queued | " .. claimed .. " active"
    local tasks={}; for _,t in pairs(base.tasks or {}) do tasks[#tasks+1]=t end
    table.sort(tasks, function(a,b) local ap=tonumber(a.priority) or 0; local bp=tonumber(b.priority) or 0; if ap==bp then return tostring(a.id) < tostring(b.id) end return ap>bp end)
    if #tasks==0 then self.taskList:addItem("none","No work waiting — mark work areas") else for _,t in ipairs(tasks) do
        self.taskList:addItem(t.type or "task", tostring(t.type or "task") .. " — " .. tostring(t.state) .. (t.claimedBy and " (assigned)" or "") .. " prio " .. tostring(t.priority or 0))
        self.taskList.items[#self.taskList.items].item=t
    end end
    local summary=KnoxBaseStorage.summarize(base); self.storageLabel.name="Storage: " .. tostring(#(KnoxBaseStorage.policies(base) or {})) .. " policies  |  Loaded: " .. tostring(summary.loadedPolicies)
    local labels={food="Food",water="Water",medical="Medical",weapons="Weapons",ammunition="Ammo",tools="Tools",building="Building",farming="Farming",clothing="Clothing",other="Other"}
    local any=false
    for _,cat in ipairs(KnoxBaseStorage.RESOURCE_CATEGORIES) do local c=tonumber(summary.totals[cat]) or 0; if c>0 then self.storageList:addItem(cat, tostring(labels[cat] or cat) .. ": " .. c); any=true end end
    local other=tonumber(summary.totals.other) or 0; if other>0 then self.storageList:addItem("other","Other: "..other); any=true end
    if not any then self.storageList:addItem("none","No supplies in loaded containers") end
    if summary.unavailablePolicies>0 then self.storageList:addItem("warn", tostring(summary.unavailablePolicies) .. " container(s) outside loaded area") end
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
        KnoxActivityFeed.event("Base task cancelled: " .. tostring(task.type or "work") .. ".")
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
        KnoxActivityFeed.event("Base task resumed: " .. tostring(task.type or "work") .. ".")
        self:populate(self.playerNum)
    end
end
function WorkView:prerender()
    ISPanelJoypad.prerender(self)
    local entry=self.taskList and self.taskList.selected and self.taskList.items[self.taskList.selected] or nil
    local task=entry and entry.item or nil
    if self.cancelTaskBtn then self.cancelTaskBtn:setEnable(task ~= nil and task.state ~= "claimed" and task.state ~= "cancelled") end
    if self.resumeTaskBtn then self.resumeTaskBtn:setEnable(task ~= nil and task.state == "cancelled") end
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
function MissionsView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text or "",10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function MissionsView:populate(playerNum)
    self.playerNum = playerNum
    self.list:clear()
    local teams = KnoxPersistence.getAwayTeams and KnoxPersistence.getAwayTeams() or {}
    local now = 0
    local gameTime = rawget(_G, "getGameTime")
    if gameTime ~= nil then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and tonumber(value) ~= nil then now = tonumber(value) end
    end
    local count = 0
    for id, team in pairs(teams) do
        if team ~= nil then
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
            self.list:addItem(id, text)
        end
    end
    if count == 0 then self.list:addItem("none", "No active missions") end
    for _, id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        if KnoxPersistence.isSurvivorAlive(id) and KnoxSurvivorRuntime.getCharacter(id) == nil then
            local aff = KnoxPersistence.getSurvivorAffiliation(id) or {}
            local duty = KnoxPersistence.getSurvivorDuty(id) or {}
            if aff.kind == "player" or duty.mode == "base" then
                local ident = KnoxPersistence.getSurvivorIdentity(id) or {}
                local name = tostring(ident.forename or "") .. " " .. tostring(ident.surname or "")
                self.list:addItem(name, name .. " | "
                    .. (duty.mode == "base" and "resident" or "companion") .. " | stored")
            end
        end
    end
end
function MissionsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Known survivors are deliberately separate from the party/base roster.  This
-- lets a player find someone encountered earlier without implying they are a
-- recruitable companion or currently loaded in the cell.
local SurvivorsView = ISPanelJoypad:derive("KnoxNotebookSurvivorsView")
function SurvivorsView:initialise() ISPanelJoypad.initialise(self) end
function SurvivorsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,self.height-UI_BORDER_SPACING*2-BUTTON_HGT-UI_BORDER_SPACING)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
    self.viewBtn=ISButton:new(UI_BORDER_SPACING,self.list:getBottom()+UI_BORDER_SPACING,110,BUTTON_HGT,"View Card",self,SurvivorsView.onView)
    self.viewBtn:initialise(); self.viewBtn.borderColor={r=0.7,g=0.7,b=0.7,a=0.5}; self:addChild(self.viewBtn)
end
function SurvivorsView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text or "",10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function SurvivorsView:populate(playerNum)
    self.playerNum=playerNum; self.list:clear(); self.ids={}
    for _,id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        local snap=KnoxSurvivorViewModel.getSurvivor(id,playerNum)
        if snap ~= nil then
            local life=snap.alive and (snap.loaded and "loaded" or "stored") or "dead"
            local text=tostring(snap.displayName or "Survivor") .. " | " .. tostring(snap.roleLabel or "Survivor") .. " | " .. tostring(snap.activity or life) .. " | " .. life
            self.list:addItem(id,text); self.list.items[#self.list.items].item={id=id}; self.ids[#self.ids+1]=id
        end
    end
    if #self.ids==0 then self.list:addItem("none","No survivor records yet") end
end
function SurvivorsView:onView() local index=self.list.selected or 0; local id=self.ids[index]; if id ~= nil then KnoxSurvivorCard.show(self.playerNum,id) end end
function SurvivorsView:prerender() ISPanelJoypad.prerender(self); if self.viewBtn then self.viewBtn:setEnable(self.ids ~= nil and self.ids[self.list.selected or 0] ~= nil) end end
function SurvivorsView:onJoypadDown(b,jd) if b==Joypad.AButton and self.list.selected>0 then self:onView() end; ISPanelJoypad.onJoypadDown(self,b,jd) end
function SurvivorsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

local FactionsView = ISPanelJoypad:derive("KnoxNotebookFactionsView")
function FactionsView:initialise() ISPanelJoypad.initialise(self) end
function FactionsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list=ISScrollingListBox:new(UI_BORDER_SPACING,UI_BORDER_SPACING,self.width-UI_BORDER_SPACING*2,self.height-UI_BORDER_SPACING*2)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
end
function FactionsView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text or "",10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function FactionsView:populate(playerNum)
    self.playerNum=playerNum; self.list:clear()
    local player=getSpecificPlayer(playerNum); local playerId=player and KnoxPersistence.ensurePlayerId(player) or nil
    local playerFaction=playerId and KnoxPersistence.getPlayerFaction ~= nil and KnoxPersistence.getPlayerFaction(playerId) or nil
    local factions={}; for _,faction in pairs(KnoxPersistence.getFactions() or {}) do if faction ~= nil then factions[#factions+1]=faction end end
    table.sort(factions,function(a,b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
    for _,faction in ipairs(factions) do
        local base=faction.homeBaseId and KnoxPersistence.getBase(faction.homeBaseId) or nil
        local camp=KnoxPersistence.getFactionCamp ~= nil and KnoxPersistence.getFactionCamp(faction.id) or nil
        local home=base ~= nil and ("Base: " .. tostring(base.name or base.id)) or (camp ~= nil and ("Shelter: " .. tostring(camp.name or camp.id)) or "No home yet")
        local kind=faction.kind == "player" and "Player faction" or "NPC faction"
        local relation=""
        if playerFaction ~= nil and faction.id ~= playerFaction.id then
            local saved=KnoxPersistence.getFactionRelationship ~= nil and KnoxPersistence.getFactionRelationship(playerFaction.id,faction.id) or nil
            relation=" | " .. tostring(saved and saved.disposition or "neutral")
        end
        self.list:addItem(faction.id,tostring(faction.name or faction.id) .. " | " .. kind .. " | " .. tostring(#(faction.memberIds or {})) .. " members | " .. home .. relation)
    end
    if #factions==0 then self.list:addItem("none","No factions have formed yet") end
end
function FactionsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false); self.collapseButton:setVisible(false)
    local th=self:titleBarHeight(); local rh=self:resizeWidgetHeight()
    self.panel=ISTabPanel:new(0, th, self.width, self.height-th-rh)
    self.panel:initialise(); self.panel.tabPadX=10; self.panel.equalTabWidth=false
    self.panel:setAnchorRight(true); self.panel:setAnchorBottom(true); self:addChild(self.panel)
    self.baseView=BaseView:new(0, 8, self.panel.width, self.panel.height-8); self.baseView:initialise(); self.baseView:createChildren(); self.panel:addView("Base", self.baseView)
    self.residentsView=ResidentsView:new(0, 8, self.panel.width, self.panel.height-8); self.residentsView:initialise(); self.residentsView:createChildren(); self.panel:addView("Residents", self.residentsView)
    self.workView=WorkView:new(0, 8, self.panel.width, self.panel.height-8); self.workView:initialise(); self.workView:createChildren(); self.panel:addView("Work", self.workView)
    self.missionsView=MissionsView:new(0, 8, self.panel.width, self.panel.height-8); self.missionsView:initialise(); self.missionsView:createChildren(); self.panel:addView("Missions", self.missionsView)
    self.survivorsView=SurvivorsView:new(0, 8, self.panel.width, self.panel.height-8); self.survivorsView:initialise(); self.survivorsView:createChildren(); self.panel:addView("Survivors", self.survivorsView)
    self.factionsView=FactionsView:new(0, 8, self.panel.width, self.panel.height-8); self.factionsView:initialise(); self.factionsView:createChildren(); self.panel:addView("Factions", self.factionsView)
end

function Window:refreshContent()
    if self.baseView then self.baseView:populate(self.playerNum) end
    if self.residentsView then self.residentsView:populate(self.playerNum) end
    if self.workView then self.workView:populate(self.playerNum) end
    if self.missionsView then self.missionsView:populate(self.playerNum) end
    if self.survivorsView then self.survivorsView:populate(self.playerNum) end
    if self.factionsView then self.factionsView:populate(self.playerNum) end
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
    local rawW,rawH=640,520; local sw=getPlayerScreenWidth(playerNum); local sh=getPlayerScreenHeight(playerNum)
    local width=math.min(rawW, math.max(1, sw-20)); local height=math.min(rawH, math.max(1, sh-20))
    local left=getPlayerScreenLeft(playerNum); local top=getPlayerScreenTop(playerNum)
    local window=ISCollapsableWindowJoypad:new(left+(sw-width)/2, top+(sh-height)/2, width, height)
    setmetatable(window,self); self.__index=self
    window.playerNum=playerNum; window.backgroundColor={r=0.06,g=0.06,b=0.06,a=0.94}; window.borderColor={r=0.28,g=0.28,b=0.28,a=0.95}
    window:setTitle("Knox Survivors"); window:setResizable(false); return window
end

function Notebook.show(playerNum)
    playerNum=tonumber(playerNum) or 0
    if Notebook.window==nil then Notebook.window=Window:new(playerNum); Notebook.window:initialise(); Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:addToUIManager()
    else Notebook.window.playerNum=playerNum; Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:setVisible(true); Notebook.window:bringToTop() end
    Notebook.window:refreshContent(); return Notebook.window
end
function Notebook.toggle(playerNum) if Notebook.window~=nil and Notebook.window:isVisible() then Notebook.window:setVisible(false) else Notebook.show(playerNum) end end
Events.OnMainMenuEnter.Add(function() if Notebook.window~=nil then Notebook.window:removeFromUIManager(); Notebook.window=nil end end)
return Notebook
