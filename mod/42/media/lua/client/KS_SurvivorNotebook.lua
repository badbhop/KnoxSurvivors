require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISTabPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTickBox"
require "KS_Persistence"
require "KS_SurvivorViewModel"
require "KS_BaseManager"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"
require "KS_BaseHighlights"
require "KS_BaseSetup"
require "KS_SurvivorCard"

local Notebook = rawget(_G, "KnoxSurvivorNotebook") or {}
_G.KnoxSurvivorNotebook = Notebook

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorNotebookWindow")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10

local function clamp(v, mn, mx) return math.max(mn, math.min(mx, v)) end

-- Base panel: territory, highlights, work areas overview
local BaseView = ISPanelJoypad:derive("KnoxNotebookBaseView")
function BaseView:initialise() ISPanelJoypad.initialise(self) end
function BaseView:createChildren()
    ISPanelJoypad.createChildren(self)
    local y = UI_BORDER_SPACING
    self.infoLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT, "", 1,1,1,1, UIFont.Small)
    self.infoLabel:initialise(); self:addChild(self.infoLabel)
    y = y + FONT_HGT_SMALL + UI_BORDER_SPACING
    self.boundaryLabel = ISLabel:new(UI_BORDER_SPACING, y, BUTTON_HGT, "", 0.6,0.6,0.8,1, UIFont.Small)
    self.boundaryLabel:initialise(); self:addChild(self.boundaryLabel)
    y = y + FONT_HGT_SMALL + UI_BORDER_SPACING
    self.showHighlights = ISTickBox:new(UI_BORDER_SPACING, y, 200, BUTTON_HGT, "", self, BaseView.onToggleHighlights)
    self.showHighlights:initialise(); self.showHighlights:addOption(getText("IGUI_Knox_Highlights") or "Show Highlights")
    self:addChild(self.showHighlights)
    y = y + BUTTON_HGT + UI_BORDER_SPACING
    self.zoneList = ISScrollingListBox:new(UI_BORDER_SPACING, y, self.width - UI_BORDER_SPACING*2, BUTTON_HGT*6)
    self.zoneList:initialise(); self.zoneList:instantiate()
    self.zoneList.itemheight = BUTTON_HGT; self.zoneList.font = UIFont.NewSmall
    self.zoneList.doDrawItem = BaseView.drawZone; self.zoneList.drawBorder = true
    self:addChild(self.zoneList)
    y = self.zoneList:getBottom() + UI_BORDER_SPACING
    self.editBoundaryBtn = ISButton:new(UI_BORDER_SPACING, y, 110, BUTTON_HGT, getText("IGUI_Knox_EditBoundary") or "Edit Boundary", self, BaseView.onEditBoundary)
    self.editBoundaryBtn:initialise(); self:addChild(self.editBoundaryBtn)
    self.addAreaBtn = ISButton:new(self.editBoundaryBtn:getRight()+UI_BORDER_SPACING, y, 90, BUTTON_HGT, getText("IGUI_Knox_AddArea") or "Add Area", self, BaseView.onAddArea)
    self.addAreaBtn:initialise(); self:addChild(self.addAreaBtn)
    self.openSetupBtn = ISButton:new(self.addAreaBtn:getRight()+UI_BORDER_SPACING, y, 110, BUTTON_HGT, "Base Setup", self, BaseView.onOpenSetup)
    self.openSetupBtn:initialise(); self:addChild(self.openSetupBtn)
end
function BaseView:drawZone(y, item, alt)
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28)
    if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end
    self:drawText(item.text, 10, y+2, 1,1,1,a, self.font); return y+self.itemheight
end
function BaseView:populate(playerNum)
    self.playerNum = playerNum
    local player = getSpecificPlayer(playerNum)
    local pid = player and KnoxPersistence.ensurePlayerId(player) or nil
    local base = pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if not base then
        self.infoLabel.name = getText("IGUI_Knox_NoBase") or "No home base"
        self.boundaryLabel.name = ""
        self.zoneList:clear(); self.showHighlights:setSelected(1, false)
        return
    end
    local residents = KnoxPersistence.getBaseResidentIds(base.id)
    local zones=0; for _ in pairs(base.zones or {}) do zones=zones+1 end
    self.infoLabel.name = (base.name or "Home Base") .. "  |  Residents: " .. #residents .. "  |  Zones: " .. zones
    local area = base.territory or base.home or {}
    self.boundaryLabel.name = "Boundary: " .. tostring(area.minX or "?") .. "," .. tostring(area.minY or "?") .. " to " .. tostring(area.maxX or "?") .. "," .. tostring(area.maxY or "?")
    self.showHighlights:setSelected(1, KnoxBaseHighlights.isEnabled(playerNum))
    self.zoneList:clear()
    local list={}
    for _,z in pairs(base.zones or {}) do if z and z.enabled~=false then list[#list+1]=z end end
    table.sort(list, function(a,b) return tostring(a.label or a.type) < tostring(b.label or b.type) end)
    for _,z in ipairs(list) do self.zoneList:addItem(z.label or z.type, "  " .. tostring(z.label or z.type) .. "  [" .. tostring(z.type) .. "]") end
    if #list==0 then self.zoneList:addItem("none", "No work areas — Add Area below") end
end
function BaseView:onToggleHighlights(index, selected) KnoxBaseHighlights.toggle(self.parent:getParent().playerNum or self.playerNum or 0) end
function BaseView:onEditBoundary()
    local win=self:getParent():getParent(); local pn=win.playerNum
    local p=getSpecificPlayer(pn); local pid=p and KnoxPersistence.ensurePlayerId(p) or nil
    local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    if base and p then if KnoxBaseTerritorySelector then KnoxBaseTerritorySelector.start(p, base.id) end end
end
function BaseView:onAddArea() local win=self:getParent():getParent(); KnoxBaseSetup.show(win.playerNum) end
function BaseView:onOpenSetup() local win=self:getParent():getParent(); KnoxBaseSetup.show(win.playerNum) end
function BaseView:prerender() ISPanelJoypad.prerender(self) end
function BaseView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Residents panel: ISScrollingListBox like Safehouse
local ResidentsView = ISPanelJoypad:derive("KnoxNotebookResidentsView")
function ResidentsView:initialise() ISPanelJoypad.initialise(self) end
function ResidentsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list = ISScrollingListBox:new(UI_BORDER_SPACING, UI_BORDER_SPACING, self.width-UI_BORDER_SPACING*2, self.height-UI_BORDER_SPACING*2-BUTTON_HGT-UI_BORDER_SPACING)
    self.list:initialise(); self.list:instantiate()
    self.list.itemheight = BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self.list.joypadParent=self
    self:addChild(self.list)
    self.viewBtn = ISButton:new(UI_BORDER_SPACING, self.list:getBottom()+UI_BORDER_SPACING, 110, BUTTON_HGT, getText("IGUI_char_Info") or "View Card", self, ResidentsView.onView)
    self.viewBtn:initialise(); self:addChild(self.viewBtn)
end
function ResidentsView:drawEntry(y,item,alt)
    local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28)
    if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end
    self:drawText(item.text, 10, y+2, 1,1,1,a, self.font); return y+self.itemheight
end
function ResidentsView:populate(playerNum)
    self.playerNum=playerNum; self.list:clear(); self.ids={}
    local snapshots=KnoxSurvivorViewModel.getForPlayer(playerNum) or {}
    local player=getSpecificPlayer(playerNum); local pid=player and KnoxPersistence.ensurePlayerId(player) or nil
    local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    for _,s in ipairs(snapshots) do
        local txt=s.displayName .. "  |  " .. (s.professionLabel or "Survivor") .. "  |  " .. (s.orderLabel or "") .. "  |  " .. (s.activity or "")
        self.list:addItem(txt, txt); self.ids[#self.ids+1]=s.id
    end
    if base then
        local rids=KnoxPersistence.getBaseResidentIds(base.id)
        for _,id in ipairs(rids) do
            local already=false; for _,eid in ipairs(self.ids) do if eid==id then already=true break end end
            if not already then
                local ident=KnoxPersistence.getSurvivorIdentity(id) or {}
                local duty=KnoxPersistence.getSurvivorDuty(id) or {}
                local name=tostring(ident.forename or "").." "..tostring(ident.surname or "")
                local txt=name .. "  |  Base  |  Job: " .. tostring(duty.jobPreference or "auto")
                self.list:addItem(txt, txt); self.ids[#self.ids+1]=id
            end
        end
    end
    if #self.ids==0 then self.list:addItem("none","No residents — recruit companions"); self.ids[1]=nil end
end
function ResidentsView:onView()
    if self.list.selected>0 and self.ids[self.list.selected] then KnoxSurvivorCard.show(self.playerNum, self.ids[self.list.selected]) end
end
function ResidentsView:prerender() ISPanelJoypad.prerender(self) if self.list.selected>0 and self.ids[self.list.selected] then self.viewBtn.enable=true else self.viewBtn.enable=false end end
function ResidentsView:onJoypadDown(b, jd) if b==Joypad.AButton and self.list.selected>0 then self:onView() end; ISPanelJoypad.onJoypadDown(self,b,jd) end
function ResidentsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Work panel: zones + tasks
local WorkView = ISPanelJoypad:derive("KnoxNotebookWorkView")
function WorkView:initialise() ISPanelJoypad.initialise(self) end
function WorkView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.zoneList = ISScrollingListBox:new(UI_BORDER_SPACING, UI_BORDER_SPACING, self.width-UI_BORDER_SPACING*2, BUTTON_HGT*5)
    self.zoneList:initialise(); self.zoneList:instantiate(); self.zoneList.itemheight=BUTTON_HGT; self.zoneList.font=UIFont.NewSmall; self.zoneList.doDrawItem=self.drawZone; self.zoneList.drawBorder=true; self:addChild(self.zoneList)
    self.taskList = ISScrollingListBox:new(UI_BORDER_SPACING, self.zoneList:getBottom()+UI_BORDER_SPACING, self.width-UI_BORDER_SPACING*2, BUTTON_HGT*5)
    self.taskList:initialise(); self.taskList:instantiate(); self.taskList.itemheight=BUTTON_HGT; self.taskList.font=UIFont.NewSmall; self.taskList.doDrawItem=self.drawTask; self.taskList.drawBorder=true; self:addChild(self.taskList)
    self.sendHomeBtn = ISButton:new(UI_BORDER_SPACING, self.taskList:getBottom()+UI_BORDER_SPACING, 120, BUTTON_HGT, getText("IGUI_Knox_SendHome") or "Send Party Home", self, WorkView.onSendHome)
    self.sendHomeBtn:initialise(); self:addChild(self.sendHomeBtn)
end
function WorkView:drawZone(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text,10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function WorkView:drawTask(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text,10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function WorkView:populate(playerNum)
    self.playerNum=playerNum
    local p=getSpecificPlayer(playerNum); local pid=p and KnoxPersistence.ensurePlayerId(p) or nil; local base=pid and KnoxBaseManager.getForOwner("player", pid) or nil
    self.zoneList:clear(); self.taskList:clear()
    if not base then self.zoneList:addItem("none","No base"); self.taskList:addItem("none","No base"); return end
    local zones={}; for _,z in pairs(base.zones or {}) do if z then zones[#zones+1]=z end end
    table.sort(zones, function(a,b) return tostring(a.type)<tostring(b.type) end)
    if #zones==0 then self.zoneList:addItem("none","No work areas") else for _,z in ipairs(zones) do self.zoneList:addItem(z.label or z.type, tostring(z.label or z.type).." ["..tostring(z.type).."]") end end
    local queued,claimed=0,0; for _,t in pairs(base.tasks or {}) do if t.state=="queued" then queued=queued+1 elseif t.state=="claimed" then claimed=claimed+1 end end
    self.taskList:addItem("header","Tasks: " .. queued .. " queued | " .. claimed .. " active")
    for _,t in pairs(base.tasks or {}) do self.taskList:addItem(t.type or "task", tostring(t.type or "task").." — "..tostring(t.state)) end
    if self.taskList:size()<=1 then self.taskList:addItem("none","No tasks — mark work areas") end
end
function WorkView:onSendHome()
    local p=getSpecificPlayer(self.playerNum); if not p then return end
    local base=KnoxBaseManager.getForOwner("player", KnoxPersistence.ensurePlayerId(p))
    if not base then return end
    local moved=0; for _,id in ipairs(KnoxSurvivorViewModel.getForPlayer(self.playerNum) or {}) do end
    -- use companion service for actual send
    if KnoxCompanionService and KnoxCompanionService.sendToBase then
        for _,s in ipairs(KnoxSurvivorViewModel.getForPlayer(self.playerNum) or {}) do if KnoxCompanionService.sendToBase(p, s.id) then moved=moved+1 end end
    end
end
function WorkView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

-- Missions panel
local MissionsView = ISPanelJoypad:derive("KnoxNotebookMissionsView")
function MissionsView:initialise() ISPanelJoypad.initialise(self) end
function MissionsView:createChildren()
    ISPanelJoypad.createChildren(self)
    self.list = ISScrollingListBox:new(UI_BORDER_SPACING, UI_BORDER_SPACING, self.width-UI_BORDER_SPACING*2, self.height-UI_BORDER_SPACING*2)
    self.list:initialise(); self.list:instantiate(); self.list.itemheight=BUTTON_HGT; self.list.font=UIFont.NewSmall; self.list.doDrawItem=self.drawEntry; self.list.drawBorder=true; self:addChild(self.list)
end
function MissionsView:drawEntry(y,item,alt) local a=0.9; self:drawRectBorder(0,y,self:getWidth(),self.itemheight-1,a,0.28,0.28,0.28); if self.selected==item.index then self:drawRect(0,y,self:getWidth(),self.itemheight-1,0.3,0.7,0.35,0.15) end; self:drawText(item.text,10,y+2,1,1,1,a,self.font); return y+self.itemheight end
function MissionsView:populate(playerNum)
    self.playerNum=playerNum; self.list:clear()
    local teams=KnoxPersistence.getAwayTeams and KnoxPersistence.getAwayTeams() or {}; local c=0
    for _,t in pairs(teams) do if t then c=c+1; self.list:addItem(t.id, tostring(t.id) .. " | " .. tostring(t.missionType) .. " | " .. tostring(t.state) .. " | " .. tostring(#(t.memberIds or {})) .. " | " .. tostring(t.destination and t.destination.label or "unknown")) end end
    if c==0 then self.list:addItem("none","No active missions") end
    -- unloaded
    for _,id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        if KnoxPersistence.isSurvivorAlive(id) and KnoxSurvivorRuntime.getCharacter(id)==nil then
            local aff=KnoxPersistence.getSurvivorAffiliation(id) or {}; local duty=KnoxPersistence.getSurvivorDuty(id) or {}
            if aff.kind=="player" or duty.mode=="base" then
                local ident=KnoxPersistence.getSurvivorIdentity(id) or {}
                local name=tostring(ident.forename or "").." "..tostring(ident.surname or "")
                self.list:addItem(name, name .. " | " .. (duty.mode=="base" and "resident" or "companion") .. " | stored")
            end
        end
    end
end
function MissionsView:new(x,y,w,h) local o=ISPanelJoypad.new(self,x,y,w,h); o:noBackground(); return o end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false); self.collapseButton:setVisible(false)
    local th=self:titleBarHeight(); local rh=self:resizeWidgetHeight()
    self.panel = ISTabPanel:new(0, th, self.width, self.height-th-rh)
    self.panel:initialise(); self.panel.tabPadX=10; self.panel.equalTabWidth=false
    self.panel:setAnchorRight(true); self.panel:setAnchorBottom(true); self:addChild(self.panel)
    self.baseView = BaseView:new(0, 8, self.panel.width, self.panel.height-8); self.baseView:initialise(); self.panel:addView("Base", self.baseView)
    self.residentsView = ResidentsView:new(0, 8, self.panel.width, self.panel.height-8); self.residentsView:initialise(); self.panel:addView("Residents", self.residentsView)
    self.workView = WorkView:new(0, 8, self.panel.width, self.panel.height-8); self.workView:initialise(); self.panel:addView("Work", self.workView)
    self.missionsView = MissionsView:new(0, 8, self.panel.width, self.panel.height-8); self.missionsView:initialise(); self.panel:addView("Missions", self.missionsView)
    -- keep legacy content for fallback
    self.content=nil
end

function Window:refreshContent()
    if self.baseView then self.baseView:populate(self.playerNum) end
    if self.residentsView then self.residentsView:populate(self.playerNum) end
    if self.workView then self.workView:populate(self.playerNum) end
    if self.missionsView then self.missionsView:populate(self.playerNum) end
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
    local rawW,rawH=620,520; local sw=getPlayerScreenWidth(playerNum); local sh=getPlayerScreenHeight(playerNum)
    local width=math.min(rawW, math.max(1, sw-20)); local height=math.min(rawH, math.max(1, sh-20))
    local left=getPlayerScreenLeft(playerNum); local top=getPlayerScreenTop(playerNum)
    local window=ISCollapsableWindowJoypad:new(left+(sw-width)/2, top+(sh-height)/2, width, height)
    setmetatable(window,self); self.__index=self
    window.playerNum=playerNum; window.activeTab="Base"
    window.backgroundColor={r=0.06,g=0.06,b=0.06,a=0.94}; window.borderColor={r=0.28,g=0.28,b=0.28,a=0.95}
    window:setTitle("Knox Survivors"); window:setResizable(true); return window
end

function Notebook.show(playerNum)
    playerNum=tonumber(playerNum) or 0
    if Notebook.window==nil then
        Notebook.window=Window:new(playerNum); Notebook.window:initialise()
        Notebook.window:setRenderThisPlayerOnly(playerNum); Notebook.window:addToUIManager()
    else Notebook.window.playerNum=playerNum; Notebook.window:setVisible(true); Notebook.window:bringToTop() end
    Notebook.window:refreshContent(); return Notebook.window
end

function Notebook.toggle(playerNum)
    if Notebook.window~=nil and Notebook.window:isVisible() then Notebook.window:setVisible(false) else Notebook.show(playerNum) end
end

Events.OnMainMenuEnter.Add(function() if Notebook.window~=nil then Notebook.window:removeFromUIManager(); Notebook.window=nil end end)

return Notebook
