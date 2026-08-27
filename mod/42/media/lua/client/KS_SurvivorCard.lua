require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISTabPanel"
require "ISUI/ISUI3DModel"
require "XpSystem/ISUI/ISCharacterScreen"
require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISHealthPanel"
require "KS_SurvivorViewModel"

local SurvivorCard = rawget(_G, "KnoxSurvivorCard") or {}
_G.KnoxSurvivorCard = SurvivorCard

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorCardWindow")

local MAX_LOCAL_PLAYERS = 4
local REFRESH_MS = 500
local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 540
local PADDING = 10
local SECTION_GAP = 8

local COL_BG      = { 0.06, 0.06, 0.06 }
local COL_BORDER  = { 0.28, 0.28, 0.28 }
local COL_SEC_BG  = { 0.10, 0.10, 0.10 }
local COL_SEC_HDR = { 0.70, 0.70, 0.68 }
local COL_LABEL   = { 0.62, 0.62, 0.60 }
local COL_VALUE   = { 0.88, 0.88, 0.85 }
local COL_DIM     = { 0.52, 0.52, 0.50 }
local COL_ACCENT  = { 0.48, 0.56, 0.38 }

local windows = {}
local nextRefreshAt = 0

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
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

local function dayLabel(value)
    local days = tonumber(value)
    if days == nil then
        return "Unknown"
    end
    days = math.max(0, math.floor(days))
    return tostring(days) .. (days == 1 and " day" or " days")
end

local function compactList(values, maximum)
    local output = {}
    for _, value in ipairs(values or {}) do
        if type(value) == "string" and value ~= "" then
            output[#output + 1] = value
            if #output >= (maximum or 3) then break end
        end
    end
    return #output > 0 and table.concat(output, ", ") or "None"
end

local function compactSkills(values, maximum)
    local output = {}
    for id, saved in pairs(values or {}) do
        local level = type(saved) == "table" and tonumber(saved.level) or nil
        if level ~= nil and level > 0 then
            output[#output + 1] = { id = tostring(id), level = math.floor(level) }
        end
    end
    table.sort(output, function(a, b)
        if a.level == b.level then return a.id < b.id end
        return a.level > b.level
    end)
    local labels = {}
    for index = 1, math.min(#output, maximum or 3) do
        labels[#labels + 1] = output[index].id .. " " .. tostring(output[index].level)
    end
    return #labels > 0 and table.concat(labels, ", ") or "No trained skills yet"
end

local function companionSnapshot(playerNum, survivorId)
    for _, snapshot in ipairs(KnoxSurvivorViewModel.getForPlayer(playerNum) or {}) do
        if snapshot.id == survivorId then
            return snapshot
        end
    end
    return nil
end

local function screenBounds(playerNum)
    return getPlayerScreenLeft(playerNum),
        getPlayerScreenTop(playerNum),
        getPlayerScreenWidth(playerNum),
        getPlayerScreenHeight(playerNum)
end

local function restoreJoypadFocus(window)
    local joypadData = JoypadState.players[window.playerNum + 1]
    if joypadData == nil or getJoypadFocus(window.playerNum) ~= window then
        return
    end
    local previous = window.previousJoypadFocus
    if previous == window then
        previous = nil
    end
    if previous ~= nil then
        local success, visible = pcall(function()
            if previous.isReallyVisible ~= nil then
                return previous:isReallyVisible()
            end
            return previous:getIsVisible()
        end)
        if not success or not visible then
            previous = nil
        end
    end
    setJoypadFocus(window.playerNum, previous)
end

-- Knox tab — preserves Knox-specific data (relationship / base / activity) inside vanilla tab frame.
local KnoxPanel = ISPanelJoypad:derive("KnoxSurvivorKnoxPanel")

function KnoxPanel:prerender()
    ISPanelJoypad.prerender(self)
    local snapshot = self.snapshot
    if snapshot == nil then return end
    local smallH = getTextManager():getFontHeight(UIFont.Small)
    local y = PADDING
    local w = self.width - PADDING * 2

    local function sectionHeader(title)
        self:drawRect(PADDING, y, w, 16, 0.92, COL_SEC_BG[1], COL_SEC_BG[2], COL_SEC_BG[3])
        self:drawText(title:upper(), PADDING + 6, y + 2, COL_SEC_HDR[1], COL_SEC_HDR[2], COL_SEC_HDR[3], 0.8, UIFont.Small)
        y = y + 20
    end
    local function keyValue(label, value, col)
        local c = col or COL_VALUE
        self:drawText(tostring(label), PADDING, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
        self:drawTextRight(trimText(UIFont.Small, tostring(value or "Unknown"), w - 70), PADDING + w, y, c[1], c[2], c[3], 1, UIFont.Small)
        y = y + 16
    end

    self:drawText(trimText(UIFont.Medium, snapshot.displayName, w), PADDING, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Medium)
    local mediumH = getTextManager():getFontHeight(UIFont.Medium)
    y = y + mediumH + 4
    local age = snapshot.ageYears ~= nil and "Age " .. tostring(snapshot.ageYears) or ""
    if age ~= "" then
        self:drawText(age, PADDING, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
        y = y + smallH + 2
    end
    self:drawText("Survived " .. dayLabel(snapshot.daysSurvived) .. "  |  Known " .. dayLabel(snapshot.daysKnown), PADDING, y, COL_DIM[1], COL_DIM[2], COL_DIM[3], 1, UIFont.Small)
    y = y + smallH + SECTION_GAP

    sectionHeader("Occupation")
    keyValue("Profession", snapshot.professionLabel)
    if snapshot.duty ~= nil and snapshot.duty.baseId ~= nil then
        keyValue("Home Base", "Base resident")
    end
    y = y + 4
    sectionHeader("Traits / Skills")
    self:drawText("Traits", PADDING, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
    self:drawText(trimText(UIFont.Small, compactList(snapshot.traits, 3), w - 60), PADDING + 60, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)
    y = y + smallH + 3
    self:drawText("Skills", PADDING, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
    self:drawText(trimText(UIFont.Small, compactSkills(snapshot.skills, 3), w - 60), PADDING + 60, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)
    y = y + smallH + SECTION_GAP

    sectionHeader("Equipment")
    keyValue("Weapon", snapshot.weaponName)
    y = y + 4
    sectionHeader("Relationship")
    keyValue("Faction", snapshot.factionName or "None")
    local trustVal = snapshot.trust ~= nil and math.floor(snapshot.trust) or nil
    local trustLabel = trustVal ~= nil and tostring(trustVal) or "Unknown"
    local trustCol = trustVal ~= nil and (trustVal >= 70 and COL_ACCENT or (trustVal >= 40 and COL_VALUE or COL_DIM)) or COL_DIM
    keyValue("Trust", trustLabel, trustCol)
    y = y + 4
    sectionHeader("Base / Activity")
    local job = snapshot.duty ~= nil and snapshot.duty.jobPreference or nil
    if job ~= nil and job ~= "" and job ~= "auto" then
        keyValue("Job", job:sub(1,1):upper() .. job:sub(2))
    end
    keyValue("Location", snapshot.locationLabel)
    keyValue("Order", snapshot.orderLabel)
    local status = snapshot.activity or "Idle"
    if snapshot.distanceTiles ~= nil then
        status = status .. " (" .. tostring(math.floor(snapshot.distanceTiles + 0.5)) .. " tiles)"
    end
    keyValue("Activity", status)
end

function KnoxPanel:new(x, y, width, height)
    local o = ISPanelJoypad.new(self, x, y, width, height)
    o:noBackground()
    o.snapshot = nil
    return o
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)

    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    -- ISTabPanel matching ISCharacterInfoWindow:117 — tabPadX 10, equalTabWidth false
    self.panel = ISTabPanel:new(0, th, self.width, self.height - th - rh)
    self.panel:initialise()
    self.panel.tabPadX = 10
    self.panel.equalTabWidth = false
    self.panel:setAnchorRight(true)
    self.panel:setAnchorBottom(true)
    self:addChild(self.panel)

    -- Views are created lazily when survivor is known so they can bind to the correct IsoPlayer.
    self.infoView = nil
    self.skillsView = nil
    self.healthView = nil
    self.knoxView = nil
end

local function ensureViews(window)
    if window.panel == nil then return end
    local survivor = window.snapshot ~= nil and window.snapshot.loaded
        and KnoxSurvivorViewModel.resolveLiveCharacter(window.snapshot.id) or nil

    if window.infoView == nil then
        local view = ISCharacterScreen:new(0, 8, window.panel.width, 400, window.playerNum)
        view:initialise()
        view.setWidthAndParentWidth = function(self, w) self:setWidth(w) end
        view.setHeightAndParentHeight = function(self, h) self:setHeight(h); self:setScrollHeight(h) end
        view.char = survivor
        view.playerNum = survivor ~= nil and survivor:getPlayerNum() or -1
        view.knoxWindow = window
        if survivor ~= nil then
            view.bFemale = survivor:isFemale()
            view.refreshNeeded = true
            pcall(function() view:loadTraits() end)
            pcall(function() view:loadProfession() end)
            view:loadBeardAndHairStyle()
        end
        -- Augment vanilla Info with Knox fields (relationship/faction/base) using restrained style.
        local origRender = view.render
        view.render = function(self)
            origRender(self)
            local snap = self.knoxWindow and self.knoxWindow.snapshot or nil
            if snap == nil then return end
            local y = self:getHeight() + 10
            local w = self.width - 20
            local smallH = getTextManager():getFontHeight(UIFont.Small)
            -- Separator
            self:drawRect(10, y, w, 1, 0.5, COL_BORDER[1], COL_BORDER[2], COL_BORDER[3])
            y = y + 8
            self:drawRect(10, y, w, 16, 0.92, COL_SEC_BG[1], COL_SEC_BG[2], COL_SEC_BG[3])
            self:drawText("KNOX", 16, y + 2, COL_SEC_HDR[1], COL_SEC_HDR[2], COL_SEC_HDR[3], 0.8, UIFont.Small)
            y = y + 20
            local function kv(label, value)
                self:drawText(tostring(label), 10, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
                self:drawTextRight(trimText(UIFont.Small, tostring(value or "Unknown"), w - 70), 10 + w, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)
                y = y + 16
            end
            kv("Time Alive", dayLabel(snap.daysSurvived))
            kv("Known", dayLabel(snap.daysKnown))
            kv("Faction", snap.factionName or "None")
            local trustVal = snap.trust ~= nil and math.floor(snap.trust) or nil
            kv("Trust", trustVal ~= nil and tostring(trustVal) or "Unknown")
            kv("Group", snap.affiliation and snap.affiliation.kind or "independent")
            local job = snap.duty and snap.duty.jobPreference or nil
            if job ~= nil and job ~= "" and job ~= "auto" then kv("Base Job", job:sub(1,1):upper()..job:sub(2)) end
            kv("Base / Activity", snap.locationLabel .. " — " .. (snap.orderLabel or ""))
            local act = snap.activity or "Idle"
            if snap.distanceTiles ~= nil then act = act .. " (" .. tostring(math.floor(snap.distanceTiles+0.5)) .. " tiles)" end
            kv("Activity", act)
            local nh = y + 6
            if nh > self:getHeight() then
                self:setHeight(nh)
                self:setScrollHeight(nh)
                if self:getParent() then self:getParent():setScrollHeight(nh) end
            end
        end
        window.infoView = view
        window.panel:addView(xpSystemText.info, view)
    end
    if window.skillsView == nil then
        local view = ISCharacterInfo:new(0, 8, window.panel.width, window.panel.height - 8, window.playerNum)
        view:initialise()
        view.setWidthAndParentWidth = function(self, w) self:setWidth(w) end
        view.setHeightAndParentHeight = function(self, h) self:setHeight(h); self:setScrollHeight(h) end
        view.char = survivor
        view.playerNum = survivor ~= nil and survivor:getPlayerNum() or -1
        view.knoxSnapshot = window.snapshot
        if survivor ~= nil then
            view.perks = ISCharacterInfo.loadPerk(view)
            view.progressBarLoaded = false
            view.reloadSkillBar = true
        end
        -- When survivor has no live IsoPlayer, fall back to persisted snapshot skills for display.
        local origPrerender = view.prerender
        view.prerender = function(self)
            -- Inject persisted levels into vanilla XP before draw when off-slot not fully synced.
            if self.char ~= nil and self.knoxSnapshot ~= nil and self.knoxSnapshot.skills ~= nil then
                pcall(function()
                    for perkId, saved in pairs(self.knoxSnapshot.skills) do
                        local lvl = tonumber(saved.level)
                        if lvl ~= nil and lvl > 0 then
                            local perk = PerkFactory.getPerk(PerkFactory.getPerkFromName(tostring(perkId)))
                            if perk ~= nil then
                                -- Keep vanilla progress bars in sync with persisted value where vanilla is stale.
                                local cur = self.char:getPerkLevel(perk)
                                if cur ~= lvl then
                                    -- Do not mutate live XP heavily; just ensure display reflects persisted (overlay handled below).
                                end
                            end
                        end
                    end
                end)
            end
            if origPrerender then origPrerender(self) end
        end
        window.skillsView = view
        window.panel:addView(xpSystemText.skills, view)
    end
    if window.healthView == nil and survivor ~= nil then
        local localPlayer = getSpecificPlayer(window.playerNum)
        local view = ISHealthPanel:new(survivor, 0, 8, window.panel.width, window.panel.height - 8)
        view:initialise()
        view.setWidthAndParentWidth = function(self, w) self:setWidth(w) end
        view.setHeightAndParentHeight = function(self, h) self:setHeight(h); self:setScrollHeight(h) end
        if localPlayer ~= nil then
            view.otherPlayer = localPlayer
            view.character = survivor
            view.playerNum = localPlayer:getPlayerNum()
            view.doctorLevel = localPlayer:getPerkLevel(Perks.Doctor)
        end
        window.healthView = view
        window.panel:addView(xpSystemText.health, view)
    end
    if window.knoxView == nil then
        local view = KnoxPanel:new(0, 8, window.panel.width, window.panel.height - 8)
        view:initialise()
        window.knoxView = view
        window.panel:addView("Knox", view)
    end

    -- Bind all vanilla views to the selected survivor (never local player)
    if survivor ~= nil then
        -- Info
        if window.infoView.char ~= survivor then
            window.infoView.char = survivor
            window.infoView.playerNum = survivor:getPlayerNum()
            window.infoView.bFemale = survivor:isFemale()
            window.infoView.refreshNeeded = true
            pcall(function() window.infoView:loadTraits() end)
            pcall(function() window.infoView:loadProfession() end)
            window.infoView:loadBeardAndHairStyle()
        end
        window.infoView.knoxWindow = window
        -- Skills
        if window.skillsView.char ~= survivor then
            window.skillsView.char = survivor
            window.skillsView.playerNum = survivor:getPlayerNum()
            window.skillsView.perks = ISCharacterInfo.loadPerk(window.skillsView)
            window.skillsView.progressBarLoaded = false
            window.skillsView.reloadSkillBar = true
        end
        window.skillsView.knoxSnapshot = window.snapshot
        -- Health — keep doctor as local player for safe treatment
        if window.healthView ~= nil and window.healthView.character ~= survivor then
            local localPlayer = getSpecificPlayer(window.playerNum)
            if localPlayer ~= nil then
                window.healthView.otherPlayer = localPlayer
                window.healthView.doctorLevel = localPlayer:getPerkLevel(Perks.Doctor)
            else
                window.healthView.otherPlayer = nil
            end
            window.healthView.character = survivor
            window.healthView.playerNum = localPlayer ~= nil and localPlayer:getPlayerNum() or survivor:getPlayerNum()
            window.healthView.characterX = survivor:getX()
            window.healthView.characterY = survivor:getY()
        end
    end
    if window.knoxView ~= nil then
        window.knoxView.snapshot = window.snapshot
    end
end

function Window:refreshSnapshot()
    local snapshot = companionSnapshot(self.playerNum, self.survivorId)
    if snapshot == nil then
        self:destroy(true)
        return false
    end
    self.snapshot = snapshot
    ensureViews(self)
    -- Nudge vanilla views to refresh when survivor moved / leveled
    if self.infoView ~= nil and self.infoView.char ~= nil then
        self.infoView.refreshNeeded = true
    end
    if self.skillsView ~= nil then
        self.skillsView.reloadSkillBar = false
    end
    return true
end

function Window:setSurvivor(survivorId)
    self.survivorId = survivorId
    return self:refreshSnapshot()
end

function Window:clampToViewport()
    local left, top, width, height = screenBounds(self.playerNum)
    self:setX(clamp(self:getX(), left, left + math.max(0, width - self:getWidth())))
    self:setY(clamp(self:getY(), top, top + math.max(0, height - self:getHeight())))
    self:stayOnSplitScreen(self.playerNum)
end

function Window:centerInViewport()
    local left, top, width, height = screenBounds(self.playerNum)
    self:setX(left + math.max(0, width - self:getWidth()) / 2)
    self:setY(top + math.max(0, height - self:getHeight()) / 2)
    self:clampToViewport()
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    -- Tab content is drawn by ISTabPanel children; window just keeps title correct.
    if self.snapshot ~= nil then
        self:setTitle(trimText(UIFont.Medium, self.snapshot.displayName, self.width - 40))
    end
end

function Window:onMouseUp(x, y)
    ISCollapsableWindowJoypad.onMouseUp(self, x, y)
    self:clampToViewport()
    return true
end

function Window:onMouseUpOutside(x, y)
    ISCollapsableWindowJoypad.onMouseUpOutside(self, x, y)
    self:clampToViewport()
    return true
end

function Window:onJoypadDown(button, joypadData)
    if button == Joypad.BButton then
        self:close()
        return
    end
    if button == Joypad.LBumper or button == Joypad.RBumper then
        if self.panel ~= nil and self.panel.viewList ~= nil and #self.panel.viewList > 1 then
            local idx = self.panel:getActiveViewIndex()
            if button == Joypad.LBumper then
                idx = idx == 1 and #self.panel.viewList or idx - 1
            else
                idx = idx == #self.panel.viewList and 1 or idx + 1
            end
            self.panel:activateView(self.panel.viewList[idx].name)
            setJoypadFocus(self.playerNum, self.panel:getActiveView())
        end
        return
    end
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function Window:destroy(restoreFocus)
    self.snapshot = nil
    self:setVisible(false)
    self:removeFromUIManager()
    if windows[self.playerNum] == self then
        windows[self.playerNum] = nil
    end
    if restoreFocus then
        restoreJoypadFocus(self)
    end
    self.previousJoypadFocus = nil
end

function Window:close()
    self:destroy(true)
end

function Window:new(playerNum)
    local _, _, screenWidth, screenHeight = screenBounds(playerNum)
    local width = math.min(WINDOW_WIDTH, math.max(1, screenWidth - 20))
    local height = math.min(WINDOW_HEIGHT, math.max(1, screenHeight - 20))
    local window = ISCollapsableWindowJoypad:new(0, 0, width, height)
    setmetatable(window, self)
    self.__index = self
    window.playerNum = playerNum
    window.survivorId = nil
    window.snapshot = nil
    window.previousJoypadFocus = nil
    window.resizable = false
    window.pin = true
    window.backgroundColor = { r = COL_BG[1], g = COL_BG[2], b = COL_BG[3], a = 0.94 }
    window.borderColor = { r = COL_BORDER[1], g = COL_BORDER[2], b = COL_BORDER[3], a = 0.95 }
    window:setTitle("Survivor")
    return window
end

local function createWindow(playerNum)
    local window = Window:new(playerNum)
    window:initialise()
    window:setRenderThisPlayerOnly(playerNum)
    window:addToUIManager()
    window:centerInViewport()
    windows[playerNum] = window
    return window
end

function SurvivorCard.show(playerNum, survivorId)
    playerNum = tonumber(playerNum) or 0
    if getSpecificPlayer(playerNum) == nil or type(survivorId) ~= "string" then
        return nil
    end
    local snapshot = companionSnapshot(playerNum, survivorId)
    if snapshot == nil then
        return nil
    end

    local window = windows[playerNum]
    local wasVisible = window ~= nil and window:isVisible()
    if window == nil then
        window = createWindow(playerNum)
    end
    if not wasVisible and JoypadState.players[playerNum + 1] ~= nil then
        window.previousJoypadFocus = getJoypadFocus(playerNum)
    end
    if not window:setSurvivor(survivorId) then
        return nil
    end
    window:setVisible(true)
    window:bringToTop()
    window:clampToViewport()
    if JoypadState.players[playerNum + 1] ~= nil then
        setJoypadFocus(playerNum, window.panel and window.panel:getActiveView() or window)
    end
    return window
end

function SurvivorCard.close(playerNum, restoreFocus)
    local window = windows[tonumber(playerNum) or 0]
    if window ~= nil then
        window:destroy(restoreFocus ~= false)
    end
end

function SurvivorCard.destroyAll(restoreFocus)
    local playerNums = {}
    for playerNum in pairs(windows) do
        playerNums[#playerNums + 1] = playerNum
    end
    for _, playerNum in ipairs(playerNums) do
        SurvivorCard.close(playerNum, restoreFocus)
    end
end

local function onTick()
    local now = getTimestampMs()
    if now < nextRefreshAt then
        return
    end
    nextRefreshAt = now + REFRESH_MS
    local active = {}
    for playerNum, window in pairs(windows) do
        if window:isVisible() then
            active[#active + 1] = playerNum
        end
    end
    for _, playerNum in ipairs(active) do
        local window = windows[playerNum]
        if window ~= nil then
            window:refreshSnapshot()
        end
    end
end

local function onPlayerDeath(player)
    if player ~= nil then
        SurvivorCard.close(player:getPlayerNum(), false)
    end
end

local function onResolutionChange()
    for _, window in pairs(windows) do
        window:clampToViewport()
    end
end

Events.OnTick.Add(onTick)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnResolutionChange.Add(onResolutionChange)
Events.OnGameStart.Add(function()
    SurvivorCard.destroyAll(false)
    nextRefreshAt = 0
end)
Events.OnMainMenuEnter.Add(function()
    SurvivorCard.destroyAll(false)
    nextRefreshAt = 0
end)

return SurvivorCard
