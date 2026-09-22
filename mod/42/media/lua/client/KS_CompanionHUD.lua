require "ISUI/ISPanel"
require "ISUI/ISUI3DModel"
require "KS_SurvivorContextMenu"
require "KS_SurvivorViewModel"
require "KS_Settings"
require "KS_PartyCommands"
require "KS_CompanionInventoryMenu"

local CompanionHUD = rawget(_G, "KnoxCompanionHUD") or {}
_G.KnoxCompanionHUD = CompanionHUD

local Panel = ISPanel:derive("KnoxCompanionHUDPanel")

local MAX_PORTRAITS = 6
local MAX_LOCAL_PLAYERS = 4
local REFRESH_MS = 400
local OUTER_PADDING = 8
local ROW_GAP = 3
local AVATAR_TEXTURE = getTexture("media/ui/avatarBackgroundWhite.png")

local panels = {}
local nextRefreshAt = 0

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function sidebarPixels()
    local size = getCore():getOptionSidebarSize()
    if size == 6 then
        size = getCore():getOptionFontSizeReal() - 1
    end
    local sizes = { 48, 64, 80, 96, 128 }
    return sizes[clamp(tonumber(size) or 1, 1, 5)]
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
    local first = string.sub(tostring(snapshot.forename or ""), 1, 1)
    local last = string.sub(tostring(snapshot.surname or ""), 1, 1)
    local result = string.upper(first .. last)
    return result ~= "" and result or "?"
end

local function screenBounds(playerNum)
    return getPlayerScreenLeft(playerNum),
        getPlayerScreenTop(playerNum),
        getPlayerScreenWidth(playerNum),
        getPlayerScreenHeight(playerNum)
end

local function activePlayer(playerNum)
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then
        return nil
    end
    return player
end

local function playerPreferences(playerNum)
    local player = getSpecificPlayer(playerNum)
    if player == nil then
        return nil
    end
    local modData = player:getModData()
    local ui = modData.KnoxSurvivorsUI
    return type(ui) == "table" and ui.companionHud or nil
end

local function savePlayerPreferences(panel)
    local player = getSpecificPlayer(panel.playerNum)
    if player == nil then
        return
    end
    local left, top, width, height = screenBounds(panel.playerNum)
    local rangeX = math.max(1, width - panel:getWidth())
    local rangeY = math.max(1, height - panel:getHeight())
    local modData = player:getModData()
    modData.KnoxSurvivorsUI = modData.KnoxSurvivorsUI or {}
    modData.KnoxSurvivorsUI.companionHud = {
        x = clamp((panel:getX() - left) / rangeX, 0, 1),
        y = clamp((panel:getY() - top) / rangeY, 0, 1),
    }
    panel.manualPosition = true
end

function Panel:calculateMetrics()
    local small = getTextManager():getFontHeight(UIFont.Small)
    local medium = getTextManager():getFontHeight(UIFont.Medium)
    local portrait = clamp(sidebarPixels(), 46, 50)
    self.smallFontHeight = small
    self.mediumFontHeight = medium
    self.portraitSize = portrait
    self.headerHeight = medium + 12
    self.rowHeight = math.max(74, small * 4 + 14)
    self.panelWidth = 188
    self.sidebarOption = getCore():getOptionSidebarSize()
end

function Panel:createChildren()
    self.portraits = {}
    self.portraitAvailable = {}
    for index = 1, MAX_PORTRAITS do
        local portrait = ISUI3DModel:new(0, 0, 1, 1)
        portrait:initialise()
        self:addChild(portrait)
        portrait:setWantMouseEvents(false)
        portrait:setState("idle")
        portrait:setDirection(IsoDirections.S)
        portrait:setIsometric(false)
        portrait:setDoRandomExtAnimations(false)
        portrait:setZoom(14)
        portrait:setYOffset(-0.85)
        portrait:setVisible(false)
        portrait.boundCharacter = nil
        self.portraits[index] = portrait
        self.portraitAvailable[index] = false
    end
end

function Panel:releasePortrait(index)
    local portrait = self.portraits ~= nil and self.portraits[index] or nil
    if portrait == nil then
        return
    end
    portrait.boundCharacter = nil
    self.portraitAvailable[index] = false
    portrait:setVisible(false)
end

function Panel:releaseAllPortraits()
    for index = 1, MAX_PORTRAITS do
        self:releasePortrait(index)
    end
end

function Panel:visibleRowCount()
    return math.min(#self.snapshots, self.visibleCapacity)
end

function Panel:maximumScrollOffset()
    return math.max(0, #self.snapshots - self.visibleCapacity)
end

function Panel:clampToViewport()
    local left, top, width, height = screenBounds(self.playerNum)
    self:setX(clamp(self:getX(), left, left + width - self:getWidth()))
    self:setY(clamp(self:getY(), top, top + height - self:getHeight()))
    self:stayOnSplitScreen(self.playerNum)
end

function Panel:applyPosition()
    local left, top, width, height = screenBounds(self.playerNum)
    local stored = playerPreferences(self.playerNum)
    if self.manualPosition and type(stored) == "table" then
        local rangeX = math.max(1, width - self:getWidth())
        local rangeY = math.max(1, height - self:getHeight())
        self:setX(left + clamp(tonumber(stored.x) or 1, 0, 1) * rangeX)
        self:setY(top + clamp(tonumber(stored.y) or 0, 0, 1) * rangeY)
    else
        local rightEdge = left + width - OUTER_PADDING
        local y = top + OUTER_PADDING
        local moodles = UIManager.getMoodleUI(self.playerNum)
        if moodles ~= nil and moodles:isVisible() then
            rightEdge = math.min(rightEdge, moodles:getAbsoluteX() - OUTER_PADDING)
            y = math.max(y, moodles:getAbsoluteY())
        end
        self:setX(rightEdge - self:getWidth())
        self:setY(y)
    end
    self:clampToViewport()
end

function Panel:layout(forcePosition)
    local previousOption = self.sidebarOption
    self:calculateMetrics()
    local left, top, screenWidth, screenHeight = screenBounds(self.playerNum)
    local availableHeight = math.max(self.rowHeight, screenHeight - OUTER_PADDING * 2 - self.headerHeight)
    self.visibleCapacity = clamp(
        math.floor((availableHeight + ROW_GAP) / (self.rowHeight + ROW_GAP)),
        1,
        MAX_PORTRAITS
    )
    self.scrollOffset = clamp(self.scrollOffset, 0, self:maximumScrollOffset())

    local rows = self:visibleRowCount()
    local height = self.headerHeight
    if rows > 0 then
        height = height + OUTER_PADDING + rows * self.rowHeight + (rows - 1) * ROW_GAP
            + OUTER_PADDING
    end
    self:setWidth(math.min(self.panelWidth, math.max(140, screenWidth - OUTER_PADDING * 2)))
    self:setHeight(height)

    local boundsSignature = table.concat({
        tostring(left), tostring(top), tostring(screenWidth), tostring(screenHeight),
        tostring(self:getWidth()), tostring(self:getHeight()), tostring(rows),
    }, ":")
    if forcePosition or previousOption ~= self.sidebarOption
        or self.lastBoundsSignature ~= boundsSignature then
        self.lastBoundsSignature = boundsSignature
        self:applyPosition()
    else
        self:clampToViewport()
    end

    for slot = 1, MAX_PORTRAITS do
        local portrait = self.portraits[slot]
        if portrait ~= nil then
            local rowY = self.headerHeight + OUTER_PADDING
                + (slot - 1) * (self.rowHeight + ROW_GAP)
            portrait:setX(OUTER_PADDING + 3)
            portrait:setY(rowY + 3)
            portrait:setWidth(self.portraitSize - 6)
            portrait:setHeight(self.rowHeight - 6)
        end
    end
end

function Panel:refreshPortraits()
    local rows = self:visibleRowCount()
    for slot = 1, MAX_PORTRAITS do
        if slot > rows then
            self:releasePortrait(slot)
        else
            local snapshot = self.snapshots[self.scrollOffset + slot]
            local character = snapshot ~= nil
                and KnoxSurvivorViewModel.resolveLiveCharacter(snapshot.id)
                or nil
            local portrait = self.portraits[slot]
            if character == nil then
                self:releasePortrait(slot)
            else
                if portrait.boundCharacter ~= character then
                    local success = pcall(function()
                        portrait:setCharacter(character)
                        portrait:setState("idle")
                    end)
                    if success then
                        portrait.boundCharacter = character
                        self.portraitAvailable[slot] = true
                    else
                        portrait.boundCharacter = nil
                        self:releasePortrait(slot)
                    end
                end
                portrait:setVisible(self.portraitAvailable[slot] == true)
            end
        end
    end
end

function Panel:refresh(forcePosition)
    local player = getSpecificPlayer(self.playerNum)
    if player == nil then
        self.snapshots = {}
        self:releaseAllPortraits()
        self:setVisible(false)
        return
    end
    self.snapshots = KnoxSurvivorViewModel.getForPlayer(self.playerNum)
    self.scrollOffset = clamp(self.scrollOffset, 0, self:maximumScrollOffset())
    if self.selectedId ~= nil then
        local found = false
        for _, snapshot in ipairs(self.snapshots) do
            if snapshot.id == self.selectedId then
                found = true
                break
            end
        end
        if not found then
            self.selectedId = nil
        end
    end
    self:layout(forcePosition == true)
    self:refreshPortraits()
    self:setVisible(#self.snapshots > 0)
end

function Panel:rowAt(y)
    local relative = y - self.headerHeight - OUTER_PADDING
    if relative < 0 then
        return nil
    end
    local stride = self.rowHeight + ROW_GAP
    local slot = math.floor(relative / stride) + 1
    if slot < 1 or slot > self:visibleRowCount()
        or relative % stride >= self.rowHeight then
        return nil
    end
    return slot, self.snapshots[self.scrollOffset + slot]
end

local BAR_HEIGHT = 6

local BAR_COLOURS = {
    health = { r = 0.72, g = 0.22, b = 0.18 },
    hunger = { r = 0.78, g = 0.54, b = 0.14 },
    thirst = { r = 0.22, g = 0.50, b = 0.82 },
    fatigue = { r = 0.68, g = 0.34, b = 0.72 },
}

function Panel:drawBar(x, y, width, value, colour, label)
    if tonumber(value) == nil then
        self:drawRect(x, y, width, BAR_HEIGHT, 0.92, 0.10, 0.10, 0.10)
        self:drawRectBorder(x, y, width, BAR_HEIGHT, 0.70, 0.36, 0.36, 0.36)
        if label ~= nil then
            self:drawTextCentre(label .. "?", x + width / 2, y - 3,
                0.58, 0.58, 0.56, 1, UIFont.Small)
        end
        return
    end
    local amount = clamp(tonumber(value) or 0, 0, 1)
    self:drawRect(x, y, width, BAR_HEIGHT, 0.92, 0.10, 0.10, 0.10)
    local c = colour or BAR_COLOURS.health
    local fade = 0.55 + amount * 0.45
    self:drawRect(x, y, math.floor(width * amount), BAR_HEIGHT,
        0.92, c.r * fade, c.g * fade, c.b * fade)
    -- Critically low needs read at a glance: amber label plus a red frame
    -- so a starving/thirsty/exhausted companion pops without reading bars.
    local critical = tonumber(value) ~= nil and amount < 0.30
    if critical then
        self:drawRectBorder(x - 1, y - 1, width + 2, BAR_HEIGHT + 2,
            0.95, 0.85, 0.25, 0.25)
    end
    if label ~= nil then
        if critical then
            self:drawTextCentre(label .. "!", x + width / 2, y - 3,
                1.0, 0.85, 0.40, 1, UIFont.Small)
        else
            self:drawTextCentre(label, x + width / 2, y - 3,
                0.96, 0.96, 0.94, 1, UIFont.Small)
        end
    end
end

function Panel:prerender()
    ISPanel.prerender(self)
    self:drawRect(0, 0, self.width, self.headerHeight, 0.80, 0.08, 0.08, 0.08)
    self:drawText(
        "SQUAD  " .. tostring(#self.snapshots),
        OUTER_PADDING,
        math.floor((self.headerHeight - self.mediumFontHeight) / 2),
        0.86, 0.86, 0.84, 1,
        UIFont.Medium
    )
    if #self.snapshots > self.visibleCapacity then
        local first = self.scrollOffset + 1
        local last = math.min(#self.snapshots, self.scrollOffset + self.visibleCapacity)
        self:drawTextRight(
            tostring(first) .. "-" .. tostring(last),
            self.width - OUTER_PADDING,
            math.floor((self.headerHeight - self.smallFontHeight) / 2) + 1,
            0.68, 0.68, 0.68, 1,
            UIFont.Small
        )
    end

    local rows = self:visibleRowCount()
    for slot = 1, rows do
        local snapshot = self.snapshots[self.scrollOffset + slot]
        local y = self.headerHeight + OUTER_PADDING
            + (slot - 1) * (self.rowHeight + ROW_GAP)
        local selected = snapshot.id == self.selectedId
        local hovered = slot == self.hoverSlot
        local shade = selected and 0.22 or (hovered and 0.17 or 0.11)
        self:drawRect(OUTER_PADDING, y, self.width - OUTER_PADDING * 2, self.rowHeight,
            0.88, shade, shade, shade)
        local border = hovered and 0.62 or (selected and 0.50 or 0.28)
        self:drawRectBorder(OUTER_PADDING, y, self.width - OUTER_PADDING * 2,
            self.rowHeight, 0.9, border, border, border)

        local portraitX = OUTER_PADDING + 3
        local portraitY = y + 3
        local portraitWidth = self.portraitSize - 6
        local portraitHeight = self.rowHeight - 6
        self:drawRect(portraitX, portraitY, portraitWidth, portraitHeight,
            0.9, 0.14, 0.14, 0.14)
        if AVATAR_TEXTURE ~= nil then
            self:drawTextureScaled(AVATAR_TEXTURE, portraitX, portraitY,
                portraitWidth, portraitHeight, 0.30, 0.38, 0.38, 0.38)
        end
        if not snapshot.loaded or not self.portraitAvailable[slot] then
            self:drawTextCentre(initials(snapshot), portraitX + portraitWidth / 2,
                portraitY + (portraitHeight - self.mediumFontHeight) / 2,
                0.80, 0.80, 0.80, 1, UIFont.Medium)
        end

        local textX = OUTER_PADDING + self.portraitSize + 5
        local textRight = self.width - OUTER_PADDING - 5
        local textWidth = math.max(30, textRight - textX)
        local order = snapshot.order == "hold" and "HOLD"
            or (snapshot.order == "relax" and "RELAX" or "FOLLOW")
        local badgeWidth = getTextManager():MeasureStringX(UIFont.Small, order) + 8
        self:drawRect(textRight - badgeWidth, y + 5, badgeWidth, self.smallFontHeight + 2,
            0.78, 0.14, 0.14, 0.14)
        self:drawTextCentre(order, textRight - badgeWidth / 2, y + 6,
            0.82, 0.82, 0.78, 1, UIFont.Small)

        local nameWidth = math.max(20, textWidth - badgeWidth - 5)
        self:drawText(trimText(UIFont.Medium, snapshot.displayName, nameWidth),
            textX, y + 5, 0.95, 0.95, 0.93, 1, UIFont.Medium)

        local status = snapshot.activity
        if snapshot.distanceTiles ~= nil then
            status = status .. " - " .. tostring(math.floor(snapshot.distanceTiles + 0.5)) .. " tiles"
        end
        self:drawText(trimText(UIFont.Small, status, textWidth), textX,
            y + 8 + self.mediumFontHeight, 0.72, 0.72, 0.70, 1, UIFont.Small)
        local detail = snapshot.needSummary ~= nil and ("Needs: " .. snapshot.needSummary)
            or snapshot.weaponName
        self:drawText(trimText(UIFont.Small, detail, textWidth), textX,
            y + 10 + self.mediumFontHeight + self.smallFontHeight,
            snapshot.needSummary ~= nil and 0.95 or 0.62,
            snapshot.needSummary ~= nil and 0.76 or 0.62, 0.60, 1, UIFont.Small)

        local barY = y + self.rowHeight - BAR_HEIGHT - 5
        local gap = 4
        local barWidth = math.floor((textWidth - gap * 3) / 4)
        self:drawBar(textX, barY, barWidth, snapshot.health, BAR_COLOURS.health, "H")
        self:drawBar(textX + barWidth + gap, barY, barWidth,
            snapshot.needs ~= nil and snapshot.needs.food or nil, BAR_COLOURS.hunger, "F")
        self:drawBar(textX + (barWidth + gap) * 2, barY, barWidth,
            snapshot.needs ~= nil and snapshot.needs.water or nil, BAR_COLOURS.thirst, "W")
        self:drawBar(textX + (barWidth + gap) * 3, barY, barWidth,
            snapshot.needs ~= nil and (snapshot.needs.sleep or snapshot.needs.rest) or nil,
            BAR_COLOURS.fatigue, "S")
    end
end

function Panel:onMouseDown(x, y)
    if y <= self.headerHeight then
        self.draggingHeader = true
        self.dragMoved = false
        self:setCapture(true)
        self:bringToTop()
        return true
    end
    return true
end

function Panel:moveHeader(dx, dy)
    if not self.draggingHeader then
        return
    end
    self:setX(self:getX() + dx)
    self:setY(self:getY() + dy)
    self:clampToViewport()
    self.dragMoved = self.dragMoved or dx ~= 0 or dy ~= 0
end

function Panel:onMouseMove(dx, dy)
    self:moveHeader(dx, dy)
    local slot = self:rowAt(self:getMouseY())
    self.hoverSlot = slot
    return true
end

function Panel:onMouseMoveOutside(dx, dy)
    self:moveHeader(dx, dy)
    self.hoverSlot = nil
end

function Panel:onMouseUp(x, y)
    if self.draggingHeader then
        self.draggingHeader = false
        self:setCapture(false)
        if self.dragMoved then
            savePlayerPreferences(self)
        end
        return true
    end
    local _, snapshot = self:rowAt(y)
    if snapshot ~= nil then
        self.selectedId = snapshot.id
    end
    return true
end

function Panel:onMouseUpOutside(x, y)
    if self.draggingHeader then
        self.draggingHeader = false
        self:setCapture(false)
        if self.dragMoved then
            savePlayerPreferences(self)
        end
    end
    return true
end

function Panel:onRightMouseUp(x, y)
    if y <= self.headerHeight then
        KnoxPartyCommands.openMenu(
            self.playerNum,
            self:getAbsoluteX() + x,
            self:getAbsoluteY() + y,
            getSpecificPlayer(self.playerNum) ~= nil
                and getSpecificPlayer(self.playerNum):getCurrentSquare() or nil
        )
        return true
    end
    local _, snapshot = self:rowAt(y)
    if snapshot == nil then
        return false
    end
    self.selectedId = snapshot.id
    KnoxSurvivorContextMenu.open(
        self.playerNum,
        snapshot.id,
        self:getAbsoluteX() + x,
        self:getAbsoluteY() + y
    )
    return true
end

function Panel:onMouseWheel(delta)
    if #self.snapshots <= self.visibleCapacity then
        return false
    end
    local nextOffset = clamp(self.scrollOffset - delta, 0, self:maximumScrollOffset())
    if nextOffset ~= self.scrollOffset then
        self.scrollOffset = nextOffset
        self:refreshPortraits()
    end
    return true
end

function Panel:new(playerNum)
    local panel = ISPanel.new(self, 0, 0, 224, 40)
    panel.playerNum = playerNum
    panel.snapshots = {}
    panel.portraits = {}
    panel.portraitAvailable = {}
    panel.scrollOffset = 0
    panel.visibleCapacity = MAX_PORTRAITS
    panel.selectedId = nil
    panel.hoverSlot = nil
    panel.draggingHeader = false
    panel.dragMoved = false
    panel.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.88 }
    panel.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.92 }
    panel:calculateMetrics()
    panel.manualPosition = type(playerPreferences(playerNum)) == "table"
    return panel
end

local function destroyPanel(playerNum)
    local panel = panels[playerNum]
    if panel == nil then
        return
    end
    panel:releaseAllPortraits()
    panel:setVisible(false)
    panel:removeFromUIManager()
    panels[playerNum] = nil
end

local function ensurePanel(playerNum)
    if not KnoxSettings.showCompanionHUD() then
        destroyPanel(playerNum)
        return nil
    end
    local player = activePlayer(playerNum)
    if player == nil then
        destroyPanel(playerNum)
        return nil
    end
    local panel = panels[playerNum]
    if panel == nil then
        panel = Panel:new(playerNum)
        panel:initialise()
        panel:setRenderThisPlayerOnly(playerNum)
        panel:addToUIManager()
        panels[playerNum] = panel
    end
    return panel
end

function CompanionHUD.refresh(playerNum)
    if playerNum ~= nil then
        local n = tonumber(playerNum)
        if n == nil then return end
        local panel = ensurePanel(n)
        if panel ~= nil then
            panel:refresh(false)
        end
        return
    end
    for index = 0, MAX_LOCAL_PLAYERS - 1 do
        local panel = ensurePanel(index)
        if panel ~= nil then
            panel:refresh(false)
        end
    end
end

function CompanionHUD.destroyAll()
    local ids = {}
    for playerNum in pairs(panels) do
        ids[#ids + 1] = playerNum
    end
    for _, playerNum in ipairs(ids) do
        destroyPanel(playerNum)
    end
end

local function onTick()
    local now = getTimestampMs()
    if now < nextRefreshAt then
        return
    end
    nextRefreshAt = now + REFRESH_MS
    if not KnoxSettings.showCompanionHUD() then
        CompanionHUD.destroyAll()
        return
    end
    CompanionHUD.refresh()
end

local function onCreatePlayer(playerNum)
    for index = 0, MAX_LOCAL_PLAYERS - 1 do
        local panel = ensurePanel(index)
        if panel ~= nil then
            panel:refresh(true)
        end
    end
end

local function onPlayerDeath(player)
    if player ~= nil then
        destroyPanel(player:getPlayerNum())
    end
end

local function onResolutionChange()
    for _, panel in pairs(panels) do
        panel:refresh(true)
    end
end

local function onGameStart()
    CompanionHUD.destroyAll()
    nextRefreshAt = 0
    CompanionHUD.refresh()
end

local function onMainMenuEnter()
    CompanionHUD.destroyAll()
    nextRefreshAt = 0
end

Events.OnTick.Add(onTick)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnResolutionChange.Add(onResolutionChange)
Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

return CompanionHUD
