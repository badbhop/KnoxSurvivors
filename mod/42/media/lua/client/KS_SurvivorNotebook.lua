require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISRichTextPanel"
require "KS_Persistence"
require "KS_SurvivorViewModel"
require "KS_BaseManager"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"

local Notebook = rawget(_G, "KnoxSurvivorNotebook") or {}
_G.KnoxSurvivorNotebook = Notebook

local Window = ISCollapsableWindow:derive("KnoxSurvivorNotebookWindow")
local TABS = { "Party", "Home Base", "Residents", "Away", "Survivors", "Factions" }

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
    return text .. line("Unloaded survivors retain their identity and stored state. Away-team simulation is not active yet.")
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
    local text = "<H1>" .. tostring(base.name or "Home Base") .. "</H1>"
        .. line("Residents: " .. tostring(#residents))
        .. line("Boundary: " .. tostring(area.minX) .. ", " .. tostring(area.minY)
            .. " to " .. tostring(area.maxX or (area.minX + area.width - 1))
            .. ", " .. tostring(area.maxY or (area.minY + area.height - 1)))
        .. line("Work queue: " .. tostring(queued) .. " queued, "
            .. tostring(claimed) .. " active")
        .. line("Storage policies: " .. tostring(tableLength(base.storage)))
    if #zones == 0 then
        text = text .. line("No work areas set. Use the world menu to mark one.")
    else
        text = text .. line("Work areas:")
        for _, zone in ipairs(zones) do
            text = text .. line("  " .. tostring(zone.label or zone.type)
                .. " [" .. tostring(zone.type) .. "]")
        end
    end
    return text .. line("All building floors are included. Work zones keep their own floor.")
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
            text = text .. line(tostring(id) .. "  -  "
                .. tostring(#(faction.memberIds or {})) .. " members"
                .. (faction.homeBaseId ~= nil and "  -  based" or "  -  travelling"))
        end
    end
    return text .. (count == 0 and line("No organized factions are known.") or "")
end

function Window:refreshContent()
    local builders = {
        ["Party"] = self.partyText,
        ["Home Base"] = self.baseText,
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
end

function Window:onTab(button)
    self.activeTab = button.title
    self:refreshContent()
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.tabButtons = {}
    local y = self:titleBarHeight() + 8
    local x = 8
    for _, title in ipairs(TABS) do
        local width = title == "Home Base" and 92 or (title == "Residents" and 82 or 70)
        local button = ISButton:new(x, y, width, 24, title, self, self.onTab)
        button:initialise()
        button.borderColor = { r = 0.42, g = 0.46, b = 0.28, a = 0.9 }
        self:addChild(button)
        self.tabButtons[#self.tabButtons + 1] = button
        x = x + width + 4
    end
    self.content = ISRichTextPanel:new(8, y + 32, self.width - 16, self.height - y - 40)
    self.content:initialise()
    self.content.background = true
    self.content.backgroundColor = { r = 0.07, g = 0.07, b = 0.055, a = 0.92 }
    self.content:setAnchorRight(true)
    self.content:setAnchorBottom(true)
    self:addChild(self.content)
    self:refreshContent()
end

function Window:new(playerNum)
    local width, height = 520, 420
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
