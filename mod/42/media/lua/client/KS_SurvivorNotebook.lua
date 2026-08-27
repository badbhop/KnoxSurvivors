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
local TABS = { "Party", "Home Base", "Base Setup", "Residents", "Away", "Survivors", "Factions" }

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

function Window:partyText()
    local snapshots = KnoxSurvivorViewModel.getForPlayer(self.playerNum)
    local text = "<H1>Party</H1>" .. line("Active companions: " .. tostring(#snapshots))
    for _, survivor in ipairs(snapshots) do
        text = text .. line("<RGB:0.78,0.84,0.62>" .. survivor.displayName
            .. "<RGB:0.85,0.85,0.82>  -  " .. survivor.activity
            .. "  -  " .. survivor.orderLabel)
    end
    return text .. (#snapshots == 0 and line("Recruit survivors to build a party.") or "")
end

function Window:residentText()
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    local text = "<H1>Base Residents</H1>"
    if base == nil then
        return text .. line("No home base established.")
    end
    local ids = KnoxPersistence.getBaseResidentIds(base.id)
    if #ids == 0 then
        return text .. line("No survivors are living at this base.")
    end
    for _, id in ipairs(ids) do
        local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        local profile = KnoxPersistence.getSurvivorCapabilities(id) or {}
        local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
        local profession = KnoxSurvivorCapabilities.professionLabel(profile) or "Survivor"
        local loaded = KnoxSurvivorRuntime.getCharacter(id) ~= nil
        text = text .. line("<RGB:0.78,0.84,0.62>" .. name
            .. "<RGB:0.85,0.85,0.82>  -  " .. profession
            .. "  -  " .. (loaded and "at base" or "unloaded")
            .. "  -  " .. tostring(duty.jobPreference or "auto"))
    end
    return text .. line("Change an individual preference from the survivor's context menu.")
end

function Window:awayText()
    local ids = KnoxPersistence.getSurvivorIds()
    local text = "<H1>Away / Unloaded</H1>"
    local count = 0
    local teams = KnoxPersistence.getAwayTeams ~= nil and KnoxPersistence.getAwayTeams() or {}
    for _, team in pairs(teams) do
        if team ~= nil then
            count = count + 1
            text = text .. line("<RGB:0.78,0.84,0.62>" .. tostring(team.id)
                .. "<RGB:0.85,0.85,0.82>  -  " .. tostring(team.missionType)
                .. "  -  " .. tostring(team.state)
                .. "  -  " .. tostring(#(team.memberIds or {})) .. " survivors"
                .. "  -  " .. tostring(team.destination ~= nil and team.destination.label or "unknown"))
        end
    end
    for _, id in ipairs(ids) do
        if KnoxPersistence.isSurvivorAlive(id)
            and KnoxSurvivorRuntime.getCharacter(id) == nil then
            count = count + 1
            local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
            local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
            local duty = KnoxPersistence.getSurvivorDuty(id) or {}
            local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
            local role = duty.mode == "base" and "base resident"
                or affiliation.kind == "player" and "companion"
                or affiliation.kind == "faction" and "faction survivor"
                or "independent"
            text = text .. line("<RGB:0.78,0.84,0.62>" .. name
                .. "<RGB:0.85,0.85,0.82>  -  " .. role
                .. "  -  stored outside the active area")
        end
    end
    if count == 0 then
        return text .. line("No known survivors are currently unloaded.")
    end
    return text .. line("Away teams preserve their previous duty and return it after a completed or blocked mission. Scout results do not create items.")
end

function Window:baseText()
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    if base == nil then
        return "<H1>Home Base</H1>" .. line("No home base established.")
            .. line("Claim a building from the world context menu, then set its boundary.")
    end
    local area = base.territory or base.home
    local residents = KnoxPersistence.getBaseResidentIds(base.id)
    local zones = {}
    for _, zone in pairs(base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(first, second)
        return tostring(first.label or first.type) < tostring(second.label or second.type)
    end)
    local queued, claimed = 0, 0
    for _, task in pairs(base.tasks or {}) do
        if task.state == "queued" then
            queued = queued + 1
        elseif task.state == "claimed" then
            claimed = claimed + 1
        end
    end
    local hl = KnoxBaseHighlights.isEnabled(self.playerNum) and "ON" or "OFF"
    local text = "<H1>" .. tostring(base.name or "Home Base") .. "</H1>"
        .. line("Residents: " .. tostring(#residents))
        .. line("Boundary: " .. tostring(area.minX) .. ", " .. tostring(area.minY)
            .. " to " .. tostring(area.maxX or (area.minX + area.width - 1))
            .. ", " .. tostring(area.maxY or (area.minY + area.height - 1)))
        .. line("Work queue: " .. tostring(queued) .. " queued, "
            .. tostring(claimed) .. " active")
        .. line("Storage policies: " .. tostring(tableLength(base.storage)))
        .. line("Highlights: " .. hl .. " (toggle in Base Setup tab)")
    if #zones == 0 then
        text = text .. line("No work areas set. Use Base Setup to mark one.")
    else
        text = text .. line("Work areas:")
        for _, zone in ipairs(zones) do
            text = text .. line("  " .. tostring(zone.label or zone.type)
                .. " [" .. tostring(zone.type) .. "]")
        end
    end
    return text .. line("All building floors are included. Work zones keep their own floor.")
end

function Window:baseSetupText()
    local player = getSpecificPlayer(self.playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    if base == nil then
        return "<H1>Base Setup</H1>" .. line("No home base established.")
            .. line("Right-click inside a building → Establish Home Base, then use Edit Boundary.")
    end
    -- Reuse BaseSetup window builders but render as notebook text with vanilla controls below.
    local area = base.territory or base.home or {}
    local residents = KnoxPersistence.getBaseResidentIds(base.id)
    local hl = KnoxBaseHighlights.isEnabled(self.playerNum) and "ON" or "OFF"
    local text = "<H1>Base Setup</H1>"
        .. line("Base: " .. tostring(base.name or "Home Base") .. "  |  Highlights: " .. hl)
        .. line("Boundary: " .. tostring(area.minX or "?") .. "," .. tostring(area.minY or "?")
            .. " to " .. tostring(area.maxX or "?") .. "," .. tostring(area.maxY or "?"))
        .. line("Residents: " .. tostring(#residents) .. "  |  Use survivor context menu for job prefs.")
        .. line("Work areas and storage are managed with the buttons below — same tools as the old Base Setup window.")
    return text
end

function Window:survivorText()
    local ids = KnoxPersistence.getSurvivorIds()
    local text = "<H1>Known Survivors</H1>" .. line("Recorded people: " .. tostring(#ids))
    for _, id in ipairs(ids) do
        local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
        local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        local profile = KnoxPersistence.getSurvivorCapabilities(id) or {}
        local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
        text = text .. line(name .. "  -  "
            .. tostring(KnoxSurvivorCapabilities.professionLabel(profile) or "Survivor")
            .. "  -  " .. tostring(affiliation.kind or "independent")
            .. "  -  " .. tostring(duty.mode or "autonomous"))
    end
    return text
end

function Window:factionText()
    local factions = KnoxPersistence.getFactions()
    local count = 0
    local text = "<H1>Factions</H1>"
    for id, faction in pairs(factions) do
        if faction ~= nil then
            count = count + 1
            local camp = KnoxPersistence.getFactionCamp ~= nil
                and KnoxPersistence.getFactionCamp(id) or nil
            text = text .. line(tostring(id) .. "  -  "
                .. tostring(#(faction.memberIds or {})) .. " members"
                .. (faction.homeBaseId ~= nil and "  -  based"
                    or camp ~= nil and "  -  sheltering at " .. tostring(camp.name)
                    or "  -  travelling"))
        end
    end
    return text .. (count == 0 and line("No organized factions are known.") or "")
end

function Window:refreshContent()
    local builders = {
        ["Party"] = self.partyText,
        ["Home Base"] = self.baseText,
        ["Base Setup"] = self.baseSetupText,
        Residents = self.residentText,
        Away = self.awayText,
        ["Survivors"] = self.survivorText,
        ["Factions"] = self.factionText,
    }
    self.content.text = builders[self.activeTab](self)
    self.content:paginate()
    for _, button in ipairs(self.tabButtons) do
        button.backgroundColor.a = button.title == self.activeTab and 0.45 or 0.18
    end
    local showSetup = self.activeTab == "Base Setup"
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
        -- Also allow direct edit from notebook
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
    local y = self:titleBarHeight() + 8
    local x = 8
    for _, title in ipairs(TABS) do
        local w = 68
        if title == "Home Base" then w = 84
        elseif title == "Base Setup" then w = 84
        elseif title == "Residents" then w = 74
        elseif title == "Party" then w = 56
        elseif title == "Survivors" then w = 74
        elseif title == "Factions" then w = 68
        elseif title == "Away" then w = 54 end
        local button = ISButton:new(x, y, w, 24, title, self, self.onTab)
        button:initialise()
        button.borderColor = { r = 0.42, g = 0.46, b = 0.28, a = 0.9 }
        self:addChild(button)
        self.tabButtons[#self.tabButtons + 1] = button
        x = x + w + 4
    end
    -- Base Setup vanilla controls (visible only on that tab)
    self.setupButtons = {}
    local by = y + 28
    self.highlightButton = ISButton:new(8, by, 118, 22, "Highlights: OFF", self, self.onToggleHighlights)
    self.highlightButton:initialise(); self.highlightButton.borderColor = { r = 0.42, g = 0.46, b = 0.28, a = 0.9 }
    self:addChild(self.highlightButton); self.setupButtons[#self.setupButtons+1] = self.highlightButton
    self.editBoundaryBtn = ISButton:new(130, by, 112, 22, "Edit Boundary", self, self.onEditBoundaryNotebook)
    self.editBoundaryBtn:initialise(); self:addChild(self.editBoundaryBtn); self.setupButtons[#self.setupButtons+1] = self.editBoundaryBtn
    self.addAreaBtn = ISButton:new(246, by, 92, 22, "Add Area", self, self.onAddZoneNotebook)
    self.addAreaBtn:initialise(); self:addChild(self.addAreaBtn); self.setupButtons[#self.setupButtons+1] = self.addAreaBtn
    self.openSetupBtn = ISButton:new(342, by, 118, 22, "Open Base Setup", self, self.onAddZoneNotebook)
    self.openSetupBtn:initialise(); self:addChild(self.openSetupBtn); self.setupButtons[#self.setupButtons+1] = self.openSetupBtn
    for _, b in ipairs(self.setupButtons) do b:setVisible(false) end
    self.content = ISRichTextPanel:new(8, by + 28, self.width - 16, self.height - by - 36)
    self.content:initialise()
    self.content.background = true
    self.content.backgroundColor = { r = 0.07, g = 0.07, b = 0.055, a = 0.92 }
    self.content:setAnchorRight(true)
    self.content:setAnchorBottom(true)
    self:addChild(self.content)
    self:refreshContent()
end

function Window:new(playerNum)
    local width, height = 620, 460
    local left = getPlayerScreenLeft(playerNum)
    local top = getPlayerScreenTop(playerNum)
    local window = ISCollapsableWindow:new(
        left + (getPlayerScreenWidth(playerNum) - width) / 2,
        top + (getPlayerScreenHeight(playerNum) - height) / 2,
        width,
        height
    )
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum
    window.activeTab = "Party"
    window:setTitle("Survivor Notebook")
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
