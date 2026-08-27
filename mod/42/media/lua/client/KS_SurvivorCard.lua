require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISUI3DModel"
require "KS_SurvivorViewModel"

local SurvivorCard = rawget(_G, "KnoxSurvivorCard") or {}
_G.KnoxSurvivorCard = SurvivorCard

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorCardWindow")

local MAX_LOCAL_PLAYERS = 4
local REFRESH_MS = 500
local WINDOW_WIDTH = 460
local WINDOW_HEIGHT = 500
local PADDING = 10
local SECTION_GAP = 8
local AVATAR_TEXTURE = getTexture("media/ui/avatarBackgroundWhite.png")

local COL_BG      = { 0.06, 0.06, 0.06 }
local COL_BORDER  = { 0.28, 0.28, 0.28 }
local COL_SEC_BG  = { 0.10, 0.10, 0.10 }
local COL_SEC_HDR = { 0.70, 0.70, 0.68 }
local COL_LABEL   = { 0.62, 0.62, 0.60 }
local COL_VALUE   = { 0.88, 0.88, 0.85 }
local COL_DIM     = { 0.52, 0.52, 0.50 }
local COL_ACCENT  = { 0.48, 0.56, 0.38 }
local COL_HEALTH  = { 0.72, 0.22, 0.18 }
local COL_HUNGER  = { 0.78, 0.54, 0.14 }
local COL_THIRST  = { 0.22, 0.50, 0.82 }
local COL_FATIGUE = { 0.68, 0.34, 0.72 }

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

local function initials(snapshot)
    local first = string.sub(tostring(snapshot ~= nil and snapshot.forename or ""), 1, 1)
    local last = string.sub(tostring(snapshot ~= nil and snapshot.surname or ""), 1, 1)
    local value = string.upper(first .. last)
    return value ~= "" and value or "?"
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

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)

    local titleHeight = self:titleBarHeight()
    self.portraitX = PADDING
    self.portraitY = titleHeight + PADDING
    self.portraitWidth = math.min(124, math.max(100, math.floor((self.width - PADDING * 3) * 0.30)))
    self.portraitHeight = math.min(156, math.max(120, math.floor(self.height * 0.32)))

    self.portrait = ISUI3DModel:new(
        self.portraitX,
        self.portraitY,
        self.portraitWidth,
        self.portraitHeight
    )
    self.portrait:initialise()
    -- addChild() instantiates UI3DModel.javaObject in Build 42.20. Every method
    -- below delegates to that Java object, so configure the portrait only after
    -- it has been attached (the same order used by vanilla character screens).
    self:addChild(self.portrait)
    self.portrait:setWantMouseEvents(false)
    self.portrait:setState("idle")
    self.portrait:setDirection(IsoDirections.S)
    self.portrait:setIsometric(false)
    self.portrait:setDoRandomExtAnimations(false)
    self.portrait:setZoom(14)
    self.portrait:setYOffset(-0.85)
    self.portrait:setVisible(false)
    self.portrait:setRenderThisPlayerOnly(self.playerNum)
    self.portrait.boundCharacter = nil
end

function Window:releasePortrait()
    if self.portrait == nil then
        return
    end
    pcall(function()
        self.portrait:setCharacter(nil)
    end)
    self.portrait.boundCharacter = nil
    self.portraitAvailable = false
    self.portrait:setVisible(false)
end

function Window:refreshPortrait()
    local character = self.snapshot ~= nil and self.snapshot.loaded
        and KnoxSurvivorViewModel.resolveLiveCharacter(self.snapshot.id)
        or nil
    if character == nil then
        self:releasePortrait()
        return
    end
    if self.portrait.boundCharacter == character and self.portraitAvailable then
        return
    end
    local success = pcall(function()
        self.portrait:setCharacter(nil)
        self.portrait:setCharacter(character)
        self.portrait:setState("idle")
    end)
    if not success then
        self:releasePortrait()
        return
    end
    self.portrait.boundCharacter = character
    self.portraitAvailable = true
    self.portrait:setVisible(true)
end

function Window:refreshSnapshot()
    local snapshot = companionSnapshot(self.playerNum, self.survivorId)
    if snapshot == nil then
        self:destroy(true)
        return false
    end
    self.snapshot = snapshot
    self:refreshPortrait()
    return true
end

function Window:setSurvivor(survivorId)
    if self.survivorId ~= survivorId then
        self:releasePortrait()
    end
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

local function drawSectionHeader(window, x, y, w, title)
    window:drawRect(x, y, w, 16, 0.92, COL_SEC_BG[1], COL_SEC_BG[2], COL_SEC_BG[3])
    window:drawText(title:upper(), x + 6, y + 2, COL_SEC_HDR[1], COL_SEC_HDR[2], COL_SEC_HDR[3], 0.8, UIFont.Small)
    return y + 20
end

local function drawKeyValue(window, x, y, w, label, value, valCol)
    local c = valCol or COL_VALUE
    window:drawText(tostring(label), x, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
    window:drawTextRight(trimText(UIFont.Small, tostring(value or "Unknown"), w - 60), x + w, y, c[1], c[2], c[3], 1, UIFont.Small)
    return y + 16
end

local function drawBar(window, x, y, w, value, colour)
    local amount = clamp(tonumber(value) or 0, 0, 1)
    window:drawRect(x, y, w, 6, 0.92, 0.10, 0.10, 0.10)
    window:drawRectBorder(x, y, w, 6, 0.72, 0.22, 0.22, 0.22)
    local fade = 0.55 + amount * 0.45
    window:drawRect(x + 1, y + 1, math.max(0, math.floor((w - 2) * amount)), 4,
        0.92, colour[1] * fade, colour[2] * fade, colour[3] * fade)
end

function Window:drawCondition(label, y, value, available, highIsBad, colour)
    local labelWidth = 58
    local rx = self.rightColX or (self.portraitX + self.portraitWidth + 14)
    local barX = rx + labelWidth
    local barWidth = math.max(20, self.rightColWidth - labelWidth - 34)
    self:drawText(label, rx, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
    self:drawRect(barX, y + 3, barWidth, 6, 0.92, 0.10, 0.10, 0.10)
    self:drawRectBorder(barX, y + 3, barWidth, 6, 0.72, 0.28, 0.28, 0.28)
    if available then
        local amount = clamp(tonumber(value) or 0, 0, 1)
        local c = colour or COL_HEALTH
        local bad = highIsBad and amount >= 0.75 or (not highIsBad and amount <= 0.25)
        local warn = highIsBad and amount >= 0.45 or (not highIsBad and amount <= 0.50)
        if bad then c = COL_HEALTH elseif warn then c = COL_HUNGER end
        local fade = 0.55 + amount * 0.45
        self:drawRect(barX + 1, y + 3, math.max(0, math.floor((barWidth - 2) * amount)), 4,
            0.92, c[1] * fade, c[2] * fade, c[3] * fade)
        self:drawTextRight(tostring(math.floor(amount * 100 + 0.5)) .. "%",
            self.width - PADDING, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)
    else
        self:drawTextRight("--", self.width - PADDING, y,
            COL_DIM[1], COL_DIM[2], COL_DIM[3], 1, UIFont.Small)
    end
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    local snapshot = self.snapshot
    if snapshot == nil then return end

    local titleH = self:titleBarHeight()
    local smallH = getTextManager():getFontHeight(UIFont.Small)
    local mediumH = getTextManager():getFontHeight(UIFont.Medium)

    local leftCol = PADDING
    local rightCol = self.portraitX + self.portraitWidth + 14
    self.rightColX = rightCol
    self.rightColWidth = self.width - rightCol - PADDING
    local contentW = self.rightColWidth
    local y

    -- Portrait background
    self:drawRect(self.portraitX, self.portraitY, self.portraitWidth, self.portraitHeight,
        0.92, COL_SEC_BG[1], COL_SEC_BG[2], COL_SEC_BG[3])
    self:drawRectBorder(self.portraitX, self.portraitY, self.portraitWidth, self.portraitHeight,
        0.88, COL_BORDER[1], COL_BORDER[2], COL_BORDER[3])
    if AVATAR_TEXTURE ~= nil then
        self:drawTextureScaled(AVATAR_TEXTURE, self.portraitX, self.portraitY,
            self.portraitWidth, self.portraitHeight, 0.30, 0.34, 0.34, 0.34)
    end
    if not self.portraitAvailable then
        self:drawTextCentre(initials(snapshot),
            self.portraitX + self.portraitWidth / 2,
            self.portraitY + (self.portraitHeight - mediumH) / 2,
            COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Medium)
    end

    -- Identity (below portrait)
    y = self.portraitY + self.portraitHeight + 8
    self:drawText(trimText(UIFont.Medium, snapshot.displayName, self.portraitWidth),
        self.portraitX, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Medium)
    y = y + mediumH + 3
    local age = snapshot.ageYears ~= nil and "Age " .. tostring(snapshot.ageYears) or ""
    self:drawText(trimText(UIFont.Small, age, self.portraitWidth),
        self.portraitX, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
    y = y + smallH + 2
    self:drawText("Survived " .. dayLabel(snapshot.daysSurvived),
        self.portraitX, y, COL_DIM[1], COL_DIM[2], COL_DIM[3], 1, UIFont.Small)
    y = y + smallH + 2
    self:drawText("Known " .. dayLabel(snapshot.daysKnown),
        self.portraitX, y, COL_DIM[1], COL_DIM[2], COL_DIM[3], 1, UIFont.Small)

    -- Occupation
    y = titleH + PADDING
    y = drawSectionHeader(self, rightCol, y, contentW, "Occupation")
    y = drawKeyValue(self, rightCol, y, contentW, "Profession", snapshot.professionLabel)
    if snapshot.duty ~= nil and snapshot.duty.baseId ~= nil then
        y = drawKeyValue(self, rightCol, y, contentW, "Home Base", "Base resident")
    end

    -- Traits / Skills
    y = y + 4
    y = drawSectionHeader(self, rightCol, y, contentW, "Traits / Skills")
    self:drawText("Traits", rightCol, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
    self:drawText(trimText(UIFont.Small, compactList(snapshot.traits, 3), contentW - 48),
        rightCol + 48, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)
    y = y + smallH + 3
    self:drawText("Skills", rightCol, y, COL_LABEL[1], COL_LABEL[2], COL_LABEL[3], 1, UIFont.Small)
    self:drawText(trimText(UIFont.Small, compactSkills(snapshot.skills, 3), contentW - 48),
        rightCol + 48, y, COL_VALUE[1], COL_VALUE[2], COL_VALUE[3], 1, UIFont.Small)

    -- Health / Vitals
    y = y + smallH + SECTION_GAP
    y = drawSectionHeader(self, rightCol, y, contentW, "Health / Vitals")
    local vitals = snapshot.vitals or {}
    if not vitals.available then
        self:drawText("Away from group", rightCol + 6, y, COL_DIM[1], COL_DIM[2], COL_DIM[3], 1, UIFont.Small)
        y = y + smallH + 4
    end
    local barX = rightCol + 58
    local barW = contentW - 58
    self:drawCondition("Health", y, vitals.health, vitals.available, false, COL_HEALTH)
    y = y + smallH + 6
    self:drawCondition("Hunger", y, vitals.hunger, vitals.available, true, COL_HUNGER)
    y = y + smallH + 6
    self:drawCondition("Thirst", y, vitals.thirst, vitals.available, true, COL_THIRST)
    y = y + smallH + 6
    self:drawCondition("Fatigue", y, vitals.fatigue, vitals.available, true, COL_FATIGUE)

    -- Equipment
    y = y + smallH + SECTION_GAP
    y = drawSectionHeader(self, rightCol, y, contentW, "Equipment")
    y = drawKeyValue(self, rightCol, y, contentW, "Weapon", snapshot.weaponName)

    -- Relationship / Trust
    y = y + 4
    y = drawSectionHeader(self, rightCol, y, contentW, "Relationship")
    local faction = snapshot.factionName or "None"
    y = drawKeyValue(self, rightCol, y, contentW, "Faction", faction)
    local trustVal = snapshot.trust ~= nil and math.floor(snapshot.trust) or nil
    local trustLabel = trustVal ~= nil and tostring(trustVal) or "Unknown"
    local trustCol = trustVal ~= nil and (trustVal >= 70 and COL_ACCENT or (trustVal >= 40 and COL_VALUE or COL_HEALTH)) or COL_DIM
    y = drawKeyValue(self, rightCol, y, contentW, "Trust", trustLabel, trustCol)

    -- Base / Activity
    y = y + 4
    y = drawSectionHeader(self, rightCol, y, contentW, "Base / Activity")
    local job = snapshot.duty ~= nil and snapshot.duty.jobPreference or nil
    if job ~= nil and job ~= "" and job ~= "auto" then
        y = drawKeyValue(self, rightCol, y, contentW, "Job", job:sub(1, 1):upper() .. job:sub(2))
    end
    y = drawKeyValue(self, rightCol, y, contentW, "Location", snapshot.locationLabel)
    y = drawKeyValue(self, rightCol, y, contentW, "Order", snapshot.orderLabel)
    local status = snapshot.activity or "Idle"
    if snapshot.distanceTiles ~= nil then
        status = status .. " (" .. tostring(math.floor(snapshot.distanceTiles + 0.5)) .. " tiles)"
    end
    y = drawKeyValue(self, rightCol, y, contentW, "Activity", status)
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
    ISCollapsableWindowJoypad.onJoypadDown(self, button, joypadData)
end

function Window:destroy(restoreFocus)
    self:releasePortrait()
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
    window.portrait = nil
    window.portraitAvailable = false
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
        setJoypadFocus(playerNum, window)
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
