require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISRichTextPanel"
require "KS_Persistence"
require "KS_SurvivorViewModel"
require "KS_BaseManager"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"
require "KS_BaseHighlights"
require "KS_BaseSetup"

local Notebook = rawget(_G, "KnoxSurvivorNotebook") or {}
_G.KnoxSurvivorNotebook = Notebook

local Window = ISCollapsableWindow:derive("KnoxSurvivorNotebookWindow")
local TABS = { "Overview", "Survivors", "Base", "Work", "Missions" }
local UI_PAD = 10
local BUTTON_HGT = getTextManager():getFontHeight(UIFont.Small) + 6

local function line(value)
    return tostring(value or "") .. " <LINE> "
end

local function tableLength(values)
    local count = 0
    for _ in pairs(values or {}) do
        count = count + 1
    end
    return count
end

local function trimText(font, text, maximumWidth)
    local value = tostring(text or "")
    if getTextManager():MeasureStringX(font, value) <= maximumWidth then
        return value
    end
    local suffix = "..."
    while #value > 1
        and getTextManager():MeasureStringX(font, value .. suffix) > maximumWidth do
        value = string.sub(value, 1, #value - 1)
    end
    return value .. suffix
end

-- Overview: party count, base summary, quick stats
function Window:overviewText()
    local snapshots = KnoxSurvivorViewModel.getForPlayer(self.playerNum)
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    local awayTeams = KnoxPersistence.getAwayTeams ~= nil and KnoxPersistence.getAwayTeams() or {}
    local teamCount = 0
    for _ in pairs(awayTeams) do teamCount = teamCount + 1 end

    local text = "<H1>Overview</H1>"
        .. line("Companions: " .. tostring(#snapshots))

    if base ~= nil then
        local residents = KnoxPersistence.getBaseResidentIds(base.id)
        local zones = 0
        for _ in pairs(base.zones or {}) do zones = zones + 1 end
        local queued, claimed = 0, 0
        for _, task in pairs(base.tasks or {}) do
            if task.state == "queued" then queued = queued + 1
            elseif task.state == "claimed" then claimed = claimed + 1 end
        end
        text = text
            .. line("Home Base: " .. tostring(base.name or "Home Base"))
            .. line("  Residents: " .. tostring(#residents)
                .. "  |  Work areas: " .. tostring(zones)
                .. "  |  Tasks: " .. tostring(queued) .. " queued, " .. tostring(claimed) .. " active")
    else
        text = text .. line("Home Base: none established")
    end

    if teamCount > 0 then
        text = text .. line("Active missions: " .. tostring(teamCount))
    end

    text = text .. line("")
    text = text .. "<H2>Party</H2>"
    if #snapshots == 0 then
        text = text .. line("No companions recruited yet.")
    else
        for _, s in ipairs(snapshots) do
            local dist = s.distanceTiles ~= nil and tostring(math.floor(s.distanceTiles + 0.5)) .. " tiles" or ""
            text = text .. line("<RGB:0.72,0.78,0.58>" .. s.displayName
                .. "<RGB:0.82,0.82,0.80>  " .. s.activity
                .. (dist ~= "" and "  (" .. dist .. ")" or "")
                .. "  -  " .. s.orderLabel)
        end
    end
    return text
end

-- Survivors: companions + base residents only (no random world NPCs)
function Window:survivorsText()
    local snapshots = KnoxSurvivorViewModel.getForPlayer(self.playerNum)
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil

    local text = "<H1>Survivors</H1>"
        .. line("Companions: " .. tostring(#snapshots) .. "  |  Right-click a companion for full details.")
        .. line("")

    -- Companions
    text = text .. "<H2>Companions</H2>"
    if #snapshots == 0 then
        text = text .. line("No companions recruited.")
    else
        for _, s in ipairs(snapshots) do
            local health = ""
            if s.vitals ~= nil and s.vitals.available then
                local pct = math.floor((s.vitals.health or 0) * 100 + 0.5)
                health = "  HP " .. tostring(pct) .. "%"
            end
            text = text .. line("<RGB:0.72,0.78,0.58>" .. s.displayName
                .. "<RGB:0.82,0.82,0.80>  " .. s.professionLabel
                .. "  -  " .. s.activity
                .. "  -  " .. s.orderLabel
                .. health)
        end
    end

    -- Base residents
    if base ~= nil then
        local ids = KnoxPersistence.getBaseResidentIds(base.id)
        if #ids > 0 then
            text = text .. line("") .. "<H2>Base Residents</H2>"
            for _, id in ipairs(ids) do
                local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
                local duty = KnoxPersistence.getSurvivorDuty(id) or {}
                local profile = KnoxPersistence.getSurvivorCapabilities(id) or {}
                local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
                local profession = KnoxSurvivorCapabilities.professionLabel(profile) or "Survivor"
                local loaded = KnoxSurvivorRuntime.getCharacter(id) ~= nil
                local job = tostring(duty.jobPreference or "auto")
                text = text .. line("<RGB:0.72,0.78,0.58>" .. name
                    .. "<RGB:0.82,0.82,0.80>  " .. profession
                    .. "  -  Job: " .. job
                    .. "  -  " .. (loaded and "present" or "stored"))
            end
        end
    end

    return text
end

-- Base: base info, setup controls, zones, storage
function Window:baseText()
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    if base == nil then
        return "<H1>Base</H1>" .. line("No home base established.")
            .. line("Right-click inside a building to establish one.")
    end
    local area = base.territory or base.home or {}
    local residents = KnoxPersistence.getBaseResidentIds(base.id)
    local hl = KnoxBaseHighlights.isEnabled(self.playerNum) and "ON" or "OFF"

    local text = "<H1>" .. tostring(base.name or "Home Base") .. "</H1>"
        .. line("Residents: " .. tostring(#residents)
            .. "  |  Highlights: " .. hl)
        .. line("Boundary: " .. tostring(area.minX or "?") .. "," .. tostring(area.minY or "?")
            .. " to " .. tostring(area.maxX or "?") .. "," .. tostring(area.maxY or "?"))

    -- Work areas
    local zones = {}
    for _, zone in pairs(base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(a, b)
        return tostring(a.label or a.type) < tostring(b.label or b.type)
    end)
    text = text .. line("") .. "<H2>Work Areas</H2>"
    if #zones == 0 then
        text = text .. line("No work areas set. Use Add Area below.")
    else
        for _, zone in ipairs(zones) do
            text = text .. line("  " .. tostring(zone.label or zone.type)
                .. "  [" .. tostring(zone.type) .. "]")
        end
    end

    -- Storage
    local storageCount = tableLength(base.storage)
    text = text .. line("") .. "<H2>Storage</H2>"
        .. line("Storage policies: " .. tostring(storageCount)
            .. "  |  Use Base Setup window for details.")

    return text
end

-- Work: jobs, tasks, storage
function Window:workText()
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    if base == nil then
        return "<H1>Work</H1>" .. line("No home base established.")
    end

    local queued, claimed, done = 0, 0, 0
    for _, task in pairs(base.tasks or {}) do
        if task.state == "queued" then queued = queued + 1
        elseif task.state == "claimed" then claimed = claimed + 1
        else done = done + 1 end
    end

    local text = "<H1>Work Queue</H1>"
        .. line("Queued: " .. tostring(queued) .. "  |  Active: " .. tostring(claimed)
            .. "  |  Completed: " .. tostring(done))

    -- Storage categories
    local cats = {}
    for _, policy in pairs(base.storage or {}) do
        if policy ~= nil and policy.category ~= nil then
            cats[policy.category] = (cats[policy.category] or 0) + 1
        end
    end
    text = text .. line("") .. "<H2>Storage Categories</H2>"
    local sorted = {}
    for cat, count in pairs(cats) do
        sorted[#sorted + 1] = { cat = cat, count = count }
    end
    table.sort(sorted, function(a, b) return a.cat < b.cat end)
    if #sorted == 0 then
        text = text .. line("No storage policies configured.")
    else
        for _, entry in ipairs(sorted) do
            text = text .. line("  " .. entry.cat .. ": " .. tostring(entry.count) .. " containers")
        end
    end

    -- Job summary
    text = text .. line("") .. "<H2>Resident Jobs</H2>"
    local ids = KnoxPersistence.getBaseResidentIds(base.id)
    if #ids == 0 then
        text = text .. line("No residents assigned.")
    else
        local jobs = {}
        for _, id in ipairs(ids) do
            local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
            local duty = KnoxPersistence.getSurvivorDuty(id) or {}
            local name = tostring(identity.forename or "Unknown")
            local job = tostring(duty.jobPreference or "auto")
            jobs[#jobs + 1] = name .. ": " .. job
        end
        table.sort(jobs)
        for _, j in ipairs(jobs) do
            text = text .. line("  " .. j)
        end
    end

    return text
end

-- Missions: away teams + unloaded survivors
function Window:missionsText()
    local text = "<H1>Missions</H1>"
    local teams = KnoxPersistence.getAwayTeams ~= nil and KnoxPersistence.getAwayTeams() or {}
    local teamCount = 0
    for _, team in pairs(teams) do
        if team ~= nil then
            teamCount = teamCount + 1
            local members = #(team.memberIds or {})
            local dest = team.destination ~= nil and team.destination.label or "unknown"
            text = text .. line("<RGB:0.72,0.78,0.58>" .. tostring(team.id)
                .. "<RGB:0.82,0.82,0.80>  " .. tostring(team.missionType)
                .. "  -  " .. tostring(team.state)
                .. "  -  " .. tostring(members) .. " survivors"
                .. "  -  " .. tostring(dest))
        end
    end
    if teamCount == 0 then
        text = text .. line("No active missions.")
    end

    -- Unloaded companions/residents
    local ids = KnoxPersistence.getSurvivorIds()
    local unloaded = 0
    for _, id in ipairs(ids) do
        if KnoxPersistence.isSurvivorAlive(id)
            and KnoxSurvivorRuntime.getCharacter(id) == nil then
            local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
            local duty = KnoxPersistence.getSurvivorDuty(id) or {}
            if affiliation.kind == "player" or duty.mode == "base" then
                unloaded = unloaded + 1
                local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
                local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
                local role = duty.mode == "base" and "resident" or "companion"
                text = text .. line("<RGB:0.72,0.78,0.58>" .. name
                    .. "<RGB:0.82,0.82,0.80>  " .. role .. "  -  stored outside active area")
            end
        end
    end
    if unloaded > 0 then
        text = text .. line("") .. "<H2>Unloaded</H2>"
            .. line(tostring(unloaded) .. " companions/residents stored outside the active area.")
    end

    return text
end

function Window:refreshContent()
    local builders = {
        Overview  = self.overviewText,
        Survivors = self.survivorsText,
        Base      = self.baseText,
        Work      = self.workText,
        Missions  = self.missionsText,
    }
    self.content.text = builders[self.activeTab](self)
    self.content:paginate()
    for _, button in ipairs(self.tabButtons) do
        button.backgroundColor.a = button.title == self.activeTab and 0.45 or 0.18
    end
    local showSetup = self.activeTab == "Base"
    if self.setupButtons ~= nil then
        for _, b in ipairs(self.setupButtons) do b:setVisible(showSetup) end
        if self.highlightButton ~= nil then
            self.highlightButton:setTitle(KnoxBaseHighlights.isEnabled(self.playerNum) and "Highlights: ON" or "Highlights: OFF")
        end
    end
end

function Window:onTab(button)
    self.activeTab = button.title
    self:refreshContent()
end

function Window:onToggleHighlights()
    KnoxBaseHighlights.toggle(self.playerNum)
    self:refreshContent()
end

function Window:onEditBoundaryNotebook()
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    if base ~= nil and player ~= nil then
        KnoxBaseSetup.show(self.playerNum)
        if KnoxBaseTerritorySelector ~= nil then
            KnoxBaseTerritorySelector.start(player, base.id)
        end
    end
end

function Window:onAddZoneNotebook()
    KnoxBaseSetup.show(self.playerNum)
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.tabButtons = {}
    local y = self:titleBarHeight() + UI_PAD
    local x = UI_PAD
    for _, title in ipairs(TABS) do
        local w = 72
        if title == "Survivors" then w = 80
        elseif title == "Overview" then w = 76
        elseif title == "Missions" then w = 78 end
        local button = ISButton:new(x, y, w, BUTTON_HGT, title, self, self.onTab)
        button:initialise()
        button.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
        self:addChild(button)
        self.tabButtons[#self.tabButtons + 1] = button
        x = x + w + 4
    end
    -- Base controls — same spacing as BaseSetup (10px pad, small+6 height), scrollable content.
    self.setupButtons = {}
    local by = y + BUTTON_HGT + 6
    self.highlightButton = ISButton:new(UI_PAD, by, 118, BUTTON_HGT, "Highlights: OFF", self, self.onToggleHighlights)
    self.highlightButton:initialise()
    self.highlightButton.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
    self:addChild(self.highlightButton)
    self.setupButtons[#self.setupButtons + 1] = self.highlightButton
    self.editBoundaryBtn = ISButton:new(UI_PAD + 122, by, 112, BUTTON_HGT, "Edit Boundary", self, self.onEditBoundaryNotebook)
    self.editBoundaryBtn:initialise()
    self.editBoundaryBtn.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
    self:addChild(self.editBoundaryBtn)
    self.setupButtons[#self.setupButtons + 1] = self.editBoundaryBtn
    self.addAreaBtn = ISButton:new(UI_PAD + 238, by, 92, BUTTON_HGT, "Add Area", self, self.onAddZoneNotebook)
    self.addAreaBtn:initialise()
    self.addAreaBtn.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
    self:addChild(self.addAreaBtn)
    self.setupButtons[#self.setupButtons + 1] = self.addAreaBtn
    self.openSetupBtn = ISButton:new(UI_PAD + 334, by, 118, BUTTON_HGT, "Open Base Setup", self, self.onAddZoneNotebook)
    self.openSetupBtn:initialise()
    self.openSetupBtn.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.9 }
    self:addChild(self.openSetupBtn)
    self.setupButtons[#self.setupButtons + 1] = self.openSetupBtn
    for _, b in ipairs(self.setupButtons) do b:setVisible(false) end
    self.content = ISRichTextPanel:new(UI_PAD, by + BUTTON_HGT + 6, self.width - UI_PAD * 2, self.height - by - BUTTON_HGT - 14)
    self.content:initialise()
    self.content.background = true
    self.content.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.92 }
    self.content:setAnchorRight(true)
    self.content:setAnchorBottom(true)
    self:addChild(self.content)
    self:refreshContent()
end

function Window:new(playerNum)
    local rawW, rawH = 580, 460
    local sw = getPlayerScreenWidth(playerNum)
    local sh = getPlayerScreenHeight(playerNum)
    local width = math.min(rawW, math.max(1, sw - 20))
    local height = math.min(rawH, math.max(1, sh - 20))
    local left = getPlayerScreenLeft(playerNum)
    local top = getPlayerScreenTop(playerNum)
    local window = ISCollapsableWindow:new(
        left + (sw - width) / 2,
        top + (sh - height) / 2,
        width,
        height
    )
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum
    window.activeTab = "Overview"
    window.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.94 }
    window.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.95 }
    window:setTitle("Knox Survivors")
    window:setResizable(true)
    return window
end

function Notebook.show(playerNum)
    playerNum = tonumber(playerNum) or 0
    if Notebook.window == nil then
        Notebook.window = Window:new(playerNum)
        Notebook.window:initialise()
        Notebook.window:setRenderThisPlayerOnly(playerNum)
        Notebook.window:addToUIManager()
    else
        Notebook.window.playerNum = playerNum
        Notebook.window:refreshContent()
        Notebook.window:setVisible(true)
        Notebook.window:bringToTop()
    end
    return Notebook.window
end

function Notebook.toggle(playerNum)
    if Notebook.window ~= nil and Notebook.window:isVisible() then
        Notebook.window:setVisible(false)
    else
        Notebook.show(playerNum)
    end
end

Events.OnMainMenuEnter.Add(function()
    if Notebook.window ~= nil then
        Notebook.window:removeFromUIManager()
        Notebook.window = nil
    end
end)

return Notebook
