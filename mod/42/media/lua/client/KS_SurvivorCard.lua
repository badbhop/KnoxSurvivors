require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISUI3DModel"
require "KS_SurvivorViewModel"

local SurvivorCard = rawget(_G, "KnoxSurvivorCard") or {}
_G.KnoxSurvivorCard = SurvivorCard

local Window = ISCollapsableWindowJoypad:derive("KnoxSurvivorCardWindow")

local MAX_LOCAL_PLAYERS = 4
local REFRESH_MS = 500
local WINDOW_WIDTH = 430
local WINDOW_HEIGHT = 385
local PADDING = 12
local AVATAR_TEXTURE = getTexture("media/ui/avatarBackgroundWhite.png")

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
    local smallHeight = getTextManager():getFontHeight(UIFont.Small)
    local conditionRowHeight = smallHeight + 6
    local firstConditionY = self.height - PADDING - 8 - conditionRowHeight * 3
    local conditionsY = firstConditionY - smallHeight - 7
    self.portraitX = PADDING
    self.portraitY = titleHeight + PADDING
    self.portraitWidth = math.min(136, math.max(88, math.floor((self.width - PADDING * 3) * 0.40)))
    self.portraitHeight = math.min(164, math.max(96, conditionsY - self.portraitY - 10))

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

local function conditionColour(value, highIsBad)
    if highIsBad then
        if value >= 0.75 then
            return 0.68, 0.20, 0.16
        end
        if value >= 0.45 then
            return 0.72, 0.52, 0.18
        end
        return 0.38, 0.58, 0.28
    end
    if value <= 0.25 then
        return 0.68, 0.20, 0.16
    end
    if value <= 0.50 then
        return 0.72, 0.52, 0.18
    end
    return 0.38, 0.58, 0.28
end

function Window:drawCondition(label, y, value, available, highIsBad)
    local labelWidth = 58
    local valueWidth = 42
    local barX = PADDING + labelWidth
    local barWidth = math.max(30, self.width - barX - valueWidth - PADDING)
    self:drawText(label, PADDING, y - 3, 0.82, 0.82, 0.77, 1, UIFont.Small)
    self:drawRect(barX, y, barWidth, 8, 0.90, 0.11, 0.11, 0.10)
    self:drawRectBorder(barX, y, barWidth, 8, 0.72, 0.34, 0.34, 0.31)
    if available then
        local amount = clamp(tonumber(value) or 0, 0, 1)
        local red, green, blue = conditionColour(amount, highIsBad)
        self:drawRect(barX + 1, y + 1, math.floor((barWidth - 2) * amount), 6,
            0.95, red, green, blue)
        self:drawTextRight(tostring(math.floor(amount * 100 + 0.5)) .. "%",
            self.width - PADDING, y - 3, 0.78, 0.78, 0.73, 1, UIFont.Small)
    else
        self:drawTextRight("--", self.width - PADDING, y - 3,
            0.55, 0.55, 0.52, 1, UIFont.Small)
    end
end

function Window:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    local snapshot = self.snapshot
    if snapshot == nil then
        return
    end

    self:drawRect(self.portraitX, self.portraitY, self.portraitWidth, self.portraitHeight,
        0.90, 0.15, 0.15, 0.14)
    self:drawRectBorder(self.portraitX, self.portraitY, self.portraitWidth, self.portraitHeight,
        0.88, 0.36, 0.39, 0.28)
    if AVATAR_TEXTURE ~= nil then
        self:drawTextureScaled(AVATAR_TEXTURE, self.portraitX, self.portraitY,
            self.portraitWidth, self.portraitHeight, 0.28, 0.42, 0.42, 0.40)
    end
    if not self.portraitAvailable then
        local mediumHeight = getTextManager():getFontHeight(UIFont.Medium)
        self:drawTextCentre(initials(snapshot),
            self.portraitX + self.portraitWidth / 2,
            self.portraitY + (self.portraitHeight - mediumHeight) / 2,
            0.80, 0.80, 0.74, 1, UIFont.Medium)
    end

    local infoX = self.portraitX + self.portraitWidth + 14
    local infoWidth = self.width - infoX - PADDING
    local y = self.portraitY
    local smallHeight = getTextManager():getFontHeight(UIFont.Small)
    local mediumHeight = getTextManager():getFontHeight(UIFont.Medium)
    self:drawText(trimText(UIFont.Medium, snapshot.displayName, infoWidth),
        infoX, y, 0.94, 0.93, 0.88, 1, UIFont.Medium)
    y = y + mediumHeight + 4

    local age = snapshot.ageYears ~= nil and "Age " .. tostring(snapshot.ageYears) or "Age unknown"
    local profession = tostring(snapshot.professionLabel or "Survivor")
    self:drawText(trimText(UIFont.Small, profession .. "  -  " .. age, infoWidth),
        infoX, y, 0.73, 0.75, 0.68, 1, UIFont.Small)
    y = y + smallHeight + 6
    self:drawText("Survived: " .. dayLabel(snapshot.daysSurvived),
        infoX, y, 0.80, 0.80, 0.75, 1, UIFont.Small)
    y = y + smallHeight + 3
    self:drawText("Known: " .. dayLabel(snapshot.daysKnown),
        infoX, y, 0.80, 0.80, 0.75, 1, UIFont.Small)
    y = y + smallHeight + 8
    self:drawText(trimText(UIFont.Small, "Role: " .. tostring(snapshot.roleLabel), infoWidth),
        infoX, y, 0.84, 0.83, 0.77, 1, UIFont.Small)
    y = y + smallHeight + 3
    self:drawText(trimText(UIFont.Small, "Location: " .. tostring(snapshot.locationLabel), infoWidth),
        infoX, y, 0.84, 0.83, 0.77, 1, UIFont.Small)
    y = y + smallHeight + 3
    self:drawText(trimText(UIFont.Small, "Order: " .. tostring(snapshot.orderLabel), infoWidth),
        infoX, y, 0.84, 0.83, 0.77, 1, UIFont.Small)
    y = y + smallHeight + 3
    local affiliation = snapshot.factionName ~= nil and ("Faction: " .. snapshot.factionName)
        or (snapshot.duty ~= nil and snapshot.duty.baseId ~= nil and "Home: base resident"
            or "Faction: none")
    self:drawText(trimText(UIFont.Small, affiliation, infoWidth),
        infoX, y, 0.72, 0.74, 0.67, 1, UIFont.Small)
    y = y + smallHeight + 3
    local trust = snapshot.trust ~= nil and ("Trust: " .. tostring(math.floor(snapshot.trust)))
        or "Trust: unknown"
    self:drawText(trimText(UIFont.Small, trust .. "  -  Weapon: " .. tostring(snapshot.weaponName), infoWidth),
        infoX, y, 0.72, 0.74, 0.67, 1, UIFont.Small)
    y = y + smallHeight + 3
    self:drawText(trimText(UIFont.Small, "Traits: " .. compactList(snapshot.traits, 3), infoWidth),
        infoX, y, 0.66, 0.68, 0.62, 1, UIFont.Small)
    y = y + smallHeight + 3
    self:drawText(trimText(UIFont.Small, "Skills: " .. compactSkills(snapshot.skills, 2), infoWidth),
        infoX, y, 0.66, 0.68, 0.62, 1, UIFont.Small)

    local vitals = snapshot.vitals or {}
    local rowHeight = smallHeight + 6
    local firstBarY = self.height - PADDING - 8 - rowHeight * 3
    local conditionsY = firstBarY - smallHeight - 7
    self:drawText("CURRENT CONDITION", PADDING, conditionsY,
        0.70, 0.72, 0.64, 1, UIFont.Small)
    if not vitals.available then
        self:drawTextRight("Unavailable while away", self.width - PADDING, conditionsY,
            0.58, 0.58, 0.55, 1, UIFont.Small)
    end
    self:drawCondition("Health", firstBarY, vitals.health, vitals.available, false)
    self:drawCondition("Hunger", firstBarY + rowHeight, vitals.hunger, vitals.available, true)
    self:drawCondition("Thirst", firstBarY + rowHeight * 2, vitals.thirst, vitals.available, true)
    self:drawCondition("Fatigue", firstBarY + rowHeight * 3, vitals.fatigue, vitals.available, true)
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
    window.backgroundColor = { r = 0.045, g = 0.05, b = 0.035, a = 0.94 }
    window.borderColor = { r = 0.38, g = 0.43, b = 0.25, a = 0.95 }
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
