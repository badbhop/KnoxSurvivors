require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISRichTextPanel"
require "KS_BaseManager"
require "KS_BaseTerritorySelector"
require "KS_BaseZoneSelector"
require "KS_CompanionService"
require "KS_Persistence"
require "KS_ActivityFeed"

local BaseSetup = rawget(_G, "KnoxBaseSetup") or {}
_G.KnoxBaseSetup = BaseSetup

local Window = ISCollapsableWindow:derive("KnoxBaseSetupWindow")
local TABS = { "Overview", "Residents", "Work Areas", "Storage", "Tasks" }
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

local function line(value)
    return tostring(value or "") .. " <LINE> "
end

local function sortedValues(values, compare)
    local result = {}
    for _, value in pairs(values or {}) do
        if value ~= nil then result[#result + 1] = value end
    end
    table.sort(result, compare)
    return result
end

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

function Window:getPlayer()
    return getSpecificPlayer(self.playerNum)
end

function Window:getBase()
    local player = self:getPlayer()
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    return playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
end

function Window:overviewText(base)
    if base == nil then
        return "<H1>Home Base</H1>" .. line("No home base established.")
            .. line("Right-click inside a building and choose Establish Home Base.")
    end
    local area = base.territory or base.home or {}
    local residents = KnoxPersistence.getBaseResidentIds(base.id)
    local queued, claimed, complete = 0, 0, 0
    for _, task in pairs(base.tasks or {}) do
        if task.state == "queued" then queued = queued + 1
        elseif task.state == "claimed" then claimed = claimed + 1
        elseif task.state == "complete" then complete = complete + 1 end
    end
    return "<H1>" .. tostring(base.name or "Home Base") .. "</H1>"
        .. line("Residents: " .. tostring(#residents))
        .. line("Boundary: " .. tostring(area.minX) .. ", " .. tostring(area.minY)
            .. " to " .. tostring(area.maxX or ((area.minX or 0) + (area.width or 1) - 1))
            .. ", " .. tostring(area.maxY or ((area.minY or 0) + (area.height or 1) - 1)))
        .. line("Jobs: " .. tostring(queued) .. " queued, " .. tostring(claimed)
            .. " active, " .. tostring(complete) .. " completed")
        .. line("Use Edit Boundary to include the house and yard. All floors within it are home.")
end

function Window:residentText(base)
    local text = "<H1>Residents</H1>"
    if base == nil then return text .. line("Establish a home base first.") end
    local ids = KnoxPersistence.getBaseResidentIds(base.id)
    if #ids == 0 then
        return text .. line("No one is assigned here.")
            .. line("Recruit a companion, then use Return to Base from their menu.")
    end
    for _, id in ipairs(ids) do
        local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
        text = text .. line("<RGB:0.78,0.84,0.62>" .. name
            .. "<RGB:0.85,0.85,0.82>  -  " .. tostring(duty.order or "available"))
    end
    return text .. line("Residents choose eligible queued work and return to safe idle when none is available.")
end

function Window:workAreaText(base)
    local text = "<H1>Work Areas</H1>"
    if base == nil then return text .. line("Establish a home base first.") end
    local zones = sortedValues(base.zones, function(a, b)
        return tostring(a.label or a.type) < tostring(b.label or b.type)
    end)
    if #zones == 0 then
        return text .. line("No work areas marked.")
            .. line("Choose a type below, then drag a rectangle in the world.")
    end
    for _, zone in ipairs(zones) do
        text = text .. line("<RGB:0.78,0.84,0.62>" .. tostring(zone.label or zone.type)
            .. "<RGB:0.85,0.85,0.82>  -  " .. tostring(zone.type)
            .. " [" .. tostring(zone.x1) .. "," .. tostring(zone.y1)
            .. " to " .. tostring(zone.x2) .. "," .. tostring(zone.y2) .. "]")
    end
    return text
end

function Window:storageText(base)
    local text = "<H1>Storage Policies</H1>"
    if base == nil then return text .. line("Establish a home base first.") end
    local policies = sortedValues(base.storage, function(a, b)
        return tostring(a.category) < tostring(b.category)
    end)
    if #policies == 0 then
        return text .. line("No storage assigned.")
            .. line("Right-click a container inside the base and set its category.")
    end
    for _, policy in ipairs(policies) do
        text = text .. line("<RGB:0.78,0.84,0.62>" .. tostring(policy.category)
            .. "<RGB:0.85,0.85,0.82>  -  " .. tostring(policy.containerType or "container")
            .. " at " .. tostring(policy.x) .. "," .. tostring(policy.y))
    end
    return text
end

function Window:taskText(base)
    local text = "<H1>Task Queue</H1>"
    if base == nil then return text .. line("Establish a home base first.") end
    local tasks = sortedValues(base.tasks, function(a, b)
        local aPriority, bPriority = tonumber(a.priority) or 0, tonumber(b.priority) or 0
        if aPriority == bPriority then return tostring(a.id) < tostring(b.id) end
        return aPriority > bPriority
    end)
    if #tasks == 0 then
        return text .. line("No work is waiting.")
            .. line("Jobs appear when marked areas need real work and residents have the required supplies.")
    end
    for _, task in ipairs(tasks) do
        text = text .. line("<RGB:0.78,0.84,0.62>" .. tostring(task.type)
            .. "<RGB:0.85,0.85,0.82>  -  " .. tostring(task.state)
            .. (task.claimedBy ~= nil and "  -  assigned" or "")
            .. "  -  priority " .. tostring(task.priority or 0))
    end
    return text
end

function Window:refreshContent()
    local base = self:getBase()
    local builders = {
        Overview = self.overviewText,
        Residents = self.residentText,
        ["Work Areas"] = self.workAreaText,
        Storage = self.storageText,
        Tasks = self.taskText,
    }
    self.content.text = builders[self.activeTab](self, base)
    self.content:paginate()
    for _, button in ipairs(self.tabButtons or {}) do
        button.backgroundColor.a = button.title == self.activeTab and 0.45 or 0.18
    end
    local enabled = base ~= nil
    self.editBoundaryButton:setEnable(enabled)
    self.addZoneButton:setEnable(enabled)
    self.recallPartyButton:setEnable(enabled)
end

function Window:onTab(button)
    self.activeTab = button.title
    self:refreshContent()
end

function Window:onEditBoundary()
    local base, player = self:getBase(), self:getPlayer()
    if base ~= nil and player ~= nil then
        KnoxBaseTerritorySelector.start(player, base.id)
        KnoxActivityFeed.event("Drag the new home-base boundary, then release to confirm.")
        self:setVisible(false)
    end
end

function Window:onAddZone()
    local base, player = self:getBase(), self:getPlayer()
    local selected = self.zonePicker.selected or 1
    local definition = ZONE_TYPES[selected]
    if base ~= nil and player ~= nil and definition ~= nil then
        KnoxBaseZoneSelector.start(player, base.id, definition.kind, definition.label)
        KnoxActivityFeed.event("Drag the " .. definition.label .. ", then release to confirm.")
        self:setVisible(false)
    end
end

function Window:onRecallParty()
    local base, player = self:getBase(), self:getPlayer()
    if base == nil or player == nil then return end
    local moved = 0
    for _, id in ipairs(KnoxCompanionService.getCompanionIds(player)) do
        local success = KnoxCompanionService.sendToBase(player, id)
        if success then moved = moved + 1 end
    end
    KnoxActivityFeed.event(moved > 0 and (tostring(moved) .. " companion(s) sent home.")
        or "No active companions were sent home.")
    self:refreshContent()
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.tabButtons = {}
    local y, x = self:titleBarHeight() + 8, 8
    for _, title in ipairs(TABS) do
        local width = title == "Work Areas" and 88 or (title == "Overview" and 76 or 70)
        local button = ISButton:new(x, y, width, 24, title, self, self.onTab)
        button:initialise()
        button.borderColor = { r = 0.42, g = 0.46, b = 0.28, a = 0.9 }
        self:addChild(button)
        self.tabButtons[#self.tabButtons + 1] = button
        x = x + width + 4
    end
    y = y + 32
    self.editBoundaryButton = ISButton:new(8, y, 108, 22, "Edit Boundary", self, self.onEditBoundary)
    self.editBoundaryButton:initialise(); self:addChild(self.editBoundaryButton)
    self.zonePicker = ISComboBox:new(122, y, 158, 22, self, nil)
    self.zonePicker:initialise()
    for _, definition in ipairs(ZONE_TYPES) do self.zonePicker:addOption(definition.label) end
    self.zonePicker.selected = 1
    self:addChild(self.zonePicker)
    self.addZoneButton = ISButton:new(286, y, 84, 22, "Add Area", self, self.onAddZone)
    self.addZoneButton:initialise(); self:addChild(self.addZoneButton)
    self.recallPartyButton = ISButton:new(376, y, 112, 22, "Send Party Home", self, self.onRecallParty)
    self.recallPartyButton:initialise(); self:addChild(self.recallPartyButton)
    self.content = ISRichTextPanel:new(8, y + 30, self.width - 16, self.height - y - 38)
    self.content:initialise()
    self.content.background = true
    self.content.backgroundColor = { r = 0.07, g = 0.07, b = 0.055, a = 0.92 }
    self.content:setAnchorRight(true); self.content:setAnchorBottom(true)
    self:addChild(self.content)
    self:refreshContent()
end

function Window:new(playerNum)
    local width, height = 560, 450
    local left, top = getPlayerScreenLeft(playerNum), getPlayerScreenTop(playerNum)
    local window = ISCollapsableWindow:new(left + (getPlayerScreenWidth(playerNum) - width) / 2,
        top + (getPlayerScreenHeight(playerNum) - height) / 2, width, height)
    setmetatable(window, self); self.__index = self
    window.playerNum = playerNum; window.activeTab = "Overview"
    window:setTitle("Base Setup")
    window:setResizable(true)
    return window
end

function BaseSetup.show(playerNum)
    playerNum = tonumber(playerNum) or 0
    if BaseSetup.window == nil then
        BaseSetup.window = Window:new(playerNum)
        BaseSetup.window:initialise()
        BaseSetup.window:setRenderThisPlayerOnly(playerNum)
        BaseSetup.window:addToUIManager()
    else
        BaseSetup.window.playerNum = playerNum
        BaseSetup.window:refreshContent()
        BaseSetup.window:setVisible(true)
        BaseSetup.window:bringToTop()
    end
    return BaseSetup.window
end

Events.OnMainMenuEnter.Add(function()
    if BaseSetup.window ~= nil then
        BaseSetup.window:removeFromUIManager()
        BaseSetup.window = nil
    end
end)

return BaseSetup
