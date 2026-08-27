require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISLabel"
require "ISUI/ISRichTextPanel"
require "KS_BaseManager"
require "KS_BaseStorage"
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

local UI_BORDER_SPACING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local BUTTON_HGT = FONT_HGT_SMALL + 6

-- Restrained accent used sparingly, matching vanilla highlight tones.
local ZONE_RGB = {
    guard       = "0.85,0.20,0.20",
    patrol      = "0.85,0.55,0.15",
    farming     = "0.20,0.70,0.20",
    woodcutting = "0.55,0.35,0.15",
    log_processing = "0.60,0.42,0.18",
    corpse      = "0.55,0.55,0.55",
    animal_care = "0.85,0.70,0.10",
    repair      = "0.20,0.50,0.85",
    construction= "0.70,0.40,0.85",
    general     = "0.52,0.52,0.75",
}

local function zoneSize(zone)
    if zone == nil or zone.x1 == nil or zone.x2 == nil or zone.y1 == nil or zone.y2 == nil then
        return nil, nil, nil
    end
    local w = math.abs(tonumber(zone.x2) - tonumber(zone.x1)) + 1
    local h = math.abs(tonumber(zone.y2) - tonumber(zone.y1)) + 1
    return w, h, w * h
end

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
    local minX = tostring(area.minX or "?")
    local minY = tostring(area.minY or "?")
    local maxX = tostring(area.maxX or ((area.minX or 0) + (area.width or 1) - 1))
    local maxY = tostring(area.maxY or ((area.minY or 0) + (area.height or 1) - 1))
    return "<H1>" .. tostring(base.name or "Home Base") .. "</H1>"
        .. line("Residents: " .. tostring(#residents) .. "  <RGB:0.52,0.52,0.50>— assigned to this home")
        .. line("Boundary: <RGB:0.78,0.84,0.62>" .. minX .. "," .. minY .. " to " .. maxX .. "," .. maxY .. "<RGB:0.82,0.82,0.80>  (all floors inside are home)")
        .. line("Jobs: " .. tostring(queued) .. " queued  |  " .. tostring(claimed)
            .. " active  |  " .. tostring(complete) .. " completed")
        .. line("<RGB:0.52,0.52,0.50>Edit Boundary to resize. Work areas below define where jobs may run.")
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
            .. "<RGB:0.85,0.85,0.82>  -  " .. tostring(duty.order or "available")
            .. "  -  preference: " .. tostring(duty.jobPreference or "auto"))
    end
    return text .. line("Residents choose eligible queued work and return to safe idle when none is available.")
end

function Window:workAreaText(base)
    local text = "<H1>Work Areas</H1>"
    if base == nil then return text .. line("Establish a home base first.") end
    local zones = sortedValues(base.zones, function(a, b)
        if tostring(a.type) == tostring(b.type) then
            return tostring(a.label or a.type) < tostring(b.label or b.type)
        end
        return tostring(a.type) < tostring(b.type)
    end)
    if #zones == 0 then
        return text .. line("No work areas yet.")
            .. line("<RGB:0.52,0.52,0.50>Pick a type above, click Add Area, then drag a rectangle in the world. Confirm size in the prompt. Right-click cancels.")
    end
    -- Group by type for scanability, like vanilla zone list grouping.
    local grouped = {}
    for _, z in ipairs(zones) do
        local t = tostring(z.type or "general")
        grouped[t] = grouped[t] or {}
        grouped[t][#grouped[t] + 1] = z
    end
    local order = { "guard","patrol","farming","woodcutting","log_processing","corpse","animal_care","repair","construction","general" }
    local seen = {}
    for _, kind in ipairs(order) do
        local list = grouped[kind]
        if list ~= nil then
            seen[kind] = true
            local rgb = ZONE_RGB[kind] or ZONE_RGB.general
            text = text .. line("<H2><RGB:" .. rgb .. ">-" .. " " .. tostring(kind) .. "</>")
            for _, zone in ipairs(list) do
                local w, h, total = zoneSize(zone)
                local sizeLabel = w ~= nil and ("  " .. tostring(w) .. "x" .. tostring(h) .. " (" .. tostring(total) .. ")") or ""
                local coord = "  at " .. tostring(zone.x1) .. "," .. tostring(zone.y1) .. " to " .. tostring(zone.x2) .. "," .. tostring(zone.y2)
                text = text .. line("  <RGB:" .. rgb .. ">" .. tostring(zone.label or zone.type) .. "</> <RGB:0.52,0.52,0.50>" .. sizeLabel .. coord .. "</>")
            end
        end
    end
    for kind, list in pairs(grouped) do
        if not seen[kind] then
            local rgb = ZONE_RGB[kind] or ZONE_RGB.general
            text = text .. line("<H2><RGB:" .. rgb .. ">-" .. " " .. tostring(kind) .. "</>")
            for _, zone in ipairs(list) do
                local w, h, total = zoneSize(zone)
                local sizeLabel = w ~= nil and ("  " .. tostring(w) .. "x" .. tostring(h) .. " (" .. tostring(total) .. ")") or ""
                text = text .. line("  <RGB:" .. rgb .. ">" .. tostring(zone.label or zone.type) .. "</> <RGB:0.52,0.52,0.50>" .. sizeLabel .. "  at " .. tostring(zone.x1) .. "," .. tostring(zone.y1) .. "</>")
            end
        end
    end
    text = text .. line("")
        .. line("<RGB:0.52,0.52,0.50>Tip: highlights show saved areas. Toggle in Notebook - Base tab.</>  Areas are work zones only - boundary above is the home itself.")
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
    local summary = KnoxBaseStorage.summarize(base)
    text = text .. line("") .. "<H2>Loaded Supplies</H2>"
    local labels = {
        food = "Food", water = "Water", medical = "Medical", weapons = "Weapons",
        ammunition = "Ammunition", tools = "Tools", building = "Building",
        farming = "Farming", clothing = "Clothing", other = "Other",
    }
    local entries = {}
    for _, category in ipairs(KnoxBaseStorage.RESOURCE_CATEGORIES) do
        entries[#entries + 1] = category
    end
    entries[#entries + 1] = "other"
    for _, category in ipairs(entries) do
        local count = tonumber(summary.totals[category]) or 0
        if count > 0 then
            text = text .. line("<RGB:0.78,0.84,0.62>" .. tostring(labels[category])
                .. "<RGB:0.85,0.85,0.82>: " .. tostring(count))
        end
    end
    if summary.loadedPolicies == 0 then
        text = text .. line("No assigned storage is currently loaded.")
    end
    if summary.unavailablePolicies > 0 then
        text = text .. line(tostring(summary.unavailablePolicies)
            .. " assigned container(s) are outside the loaded area and are not counted.")
    end
    if summary.misplacedItems > 0 then
        text = text .. line(tostring(summary.misplacedItems)
            .. " item(s) are in the wrong assigned container and await depot sorting.")
    end
    text = text .. line("Supply totals are a live view of loaded containers, not simulated stock.")
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
        KnoxActivityFeed.event("Drag the new home-base boundary, then release to confirm. Right-click to cancel.")
        self:setVisible(false)
    end
end

function Window:onAddZone()
    local base, player = self:getBase(), self:getPlayer()
    local selected = self.zonePicker.selected or 1
    local definition = ZONE_TYPES[selected]
    if base ~= nil and player ~= nil and definition ~= nil then
        KnoxBaseZoneSelector.start(player, base.id, definition.kind, definition.label)
        KnoxActivityFeed.event("Drag the " .. definition.label .. " area, then release to confirm. Right-click to cancel.")
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
    local y = self:titleBarHeight() + UI_BORDER_SPACING
    local x = UI_BORDER_SPACING
    for _, title in ipairs(TABS) do
        local width = title == "Work Areas" and 88 or (title == "Overview" and 76 or 70)
        local button = ISButton:new(x, y, width, BUTTON_HGT, title, self, self.onTab)
        button:initialise()
        button.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
        self:addChild(button)
        self.tabButtons[#self.tabButtons + 1] = button
        x = x + width + 4
    end
    y = y + BUTTON_HGT + UI_BORDER_SPACING
    -- Row 1: boundary. Row 2: work area picker — spaced like vanilla ISDesignationZonePanel.
    self.editBoundaryButton = ISButton:new(UI_BORDER_SPACING, y, 116, BUTTON_HGT, "Edit Boundary", self, self.onEditBoundary)
    self.editBoundaryButton:initialise()
    self.editBoundaryButton.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
    self:addChild(self.editBoundaryButton)
    self.recallPartyButton = ISButton:new(self.width - UI_BORDER_SPACING - 118, y, 118, BUTTON_HGT, "Send Party Home", self, self.onRecallParty)
    self.recallPartyButton:initialise()
    self.recallPartyButton.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
    self:addChild(self.recallPartyButton)

    self.zonePicker = ISComboBox:new(self.editBoundaryButton:getRight() + 8, y, 162, BUTTON_HGT, self, nil)
    self.zonePicker:initialise()
    for _, definition in ipairs(ZONE_TYPES) do self.zonePicker:addOption(definition.label) end
    self.zonePicker.selected = 1
    self:addChild(self.zonePicker)
    self.addZoneButton = ISButton:new(self.zonePicker:getRight() + 6, y, 88, BUTTON_HGT, "Add Area", self, self.onAddZone)
    self.addZoneButton:initialise()
    self.addZoneButton.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
    self:addChild(self.addZoneButton)

    local hintY = y + BUTTON_HGT + 4
    self.hintLabel = ISLabel:new(UI_BORDER_SPACING, hintY, BUTTON_HGT, "Select a work type, then Add Area and drag a rectangle. Confirm size to save. Right-click cancels.", 0.62, 0.62, 0.60, 1, UIFont.Small)
    self.hintLabel:initialise()
    self:addChild(self.hintLabel)

    self.content = ISRichTextPanel:new(UI_BORDER_SPACING, hintY + FONT_HGT_SMALL + 8, self.width - UI_BORDER_SPACING * 2, self.height - hintY - FONT_HGT_SMALL - 16)
    self.content:initialise()
    self.content.background = true
    self.content.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.92 }
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
