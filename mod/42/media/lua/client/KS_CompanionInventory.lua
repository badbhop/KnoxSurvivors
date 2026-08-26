require "ISUI/ISCollapsableWindowJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "KS_SurvivorRuntime"
require "KS_Persistence"

local CompanionInventory = rawget(_G, "KnoxCompanionInventory") or {}
_G.KnoxCompanionInventory = CompanionInventory

local Window = ISCollapsableWindowJoypad:derive("KnoxCompanionInventoryWindow")
local windows = {}
local MAX_DISTANCE_SQUARED = 16
local REFRESH_MS = 350

local function characterName(survivorId)
    local identity = KnoxPersistence.getSurvivorIdentity(survivorId) or {}
    local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
    return name ~= " " and name or tostring(survivorId)
end

local function nearby(player, character)
    if player == nil or character == nil or player:getCurrentSquare() == nil
        or character:getCurrentSquare() == nil or player:getZ() ~= character:getZ() then
        return false
    end
    local dx, dy = player:getX() - character:getX(), player:getY() - character:getY()
    return dx * dx + dy * dy <= MAX_DISTANCE_SQUARED
end

function Window:character()
    return KnoxSurvivorRuntime.getCharacter(self.survivorId)
end

function Window:refreshItems()
    local character = self:character()
    local inventory = character ~= nil and character:getInventory() or nil
    self.list:clear()
    self.itemCount = 0
    if inventory == nil then
        return
    end
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item ~= nil then
            self.itemCount = self.itemCount + 1
            self.list:addItem(tostring(item:getName()), { item = item })
        end
    end
    self.nextRefresh = getTimestamp() + REFRESH_MS
end

function Window:queueItem(item)
    local player = getSpecificPlayer(self.playerNum)
    local character = self:character()
    if not nearby(player, character) or item == nil then
        return false
    end
    local source = item:getContainer()
    if source == nil or not source:contains(item) then
        return false
    end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(
        player,
        item,
        source,
        player:getInventory()
    )
    if action == nil then
        return false
    end
    ISTimedActionQueue.add(action)
    return true
end

function Window:onTakeSelected()
    local entry = self.list.items[self.list.selected]
    local data = entry ~= nil and entry.item or nil
    if data ~= nil and self:queueItem(data.item) then
        self.nextRefresh = 0
    end
end

function Window:onTakeAll()
    local character = self:character()
    local inventory = character ~= nil and character:getInventory() or nil
    if inventory == nil then
        return
    end
    local queued = false
    -- Copy the current top-level list before queuing actions: the native action
    -- owns each mutation and may complete before the next UI refresh.
    local items = inventory:getItems()
    local snapshot = {}
    for index = 0, items:size() - 1 do
        snapshot[#snapshot + 1] = items:get(index)
    end
    for _, item in ipairs(snapshot) do
        queued = self:queueItem(item) or queued
    end
    if queued then
        self.nextRefresh = 0
    end
end

function Window:createChildren()
    ISCollapsableWindowJoypad.createChildren(self)
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)
    local top = self:titleBarHeight() + 10
    self.list = ISScrollingListBox:new(10, top, self.width - 20, self.height - top - 48)
    self.list:initialise()
    self.list.itemheight = getTextManager():getFontHeight(UIFont.Small) + 6
    self.list.drawBorder = true
    self.list:setAnchorRight(true)
    self.list:setAnchorBottom(true)
    self:addChild(self.list)
    self.takeSelected = ISButton:new(10, self.height - 34, 150, 24, "Take Selected", self, Window.onTakeSelected)
    self.takeSelected:initialise()
    self.takeSelected:setAnchorBottom(true)
    self:addChild(self.takeSelected)
    self.takeAll = ISButton:new(170, self.height - 34, 100, 24, "Take All", self, Window.onTakeAll)
    self.takeAll:initialise()
    self.takeAll:setAnchorBottom(true)
    self:addChild(self.takeAll)
    self:refreshItems()
end

function Window:update()
    ISCollapsableWindowJoypad.update(self)
    local player = getSpecificPlayer(self.playerNum)
    local character = self:character()
    if not nearby(player, character) then
        self:close()
        return
    end
    if getTimestamp() >= (self.nextRefresh or 0) then
        self:refreshItems()
    end
end

function Window:close()
    windows[self.playerNum] = nil
    ISCollapsableWindowJoypad.close(self)
end

function Window:new(playerNum, survivorId)
    local width, height = 340, 430
    local x = getPlayerScreenLeft(playerNum) + math.max(20, getPlayerScreenWidth(playerNum) - width - 24)
    local y = getPlayerScreenTop(playerNum) + 60
    local o = ISCollapsableWindowJoypad.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.survivorId = survivorId
    o.title = characterName(survivorId) .. " - Inventory"
    o.moveWithMouse = true
    o.resizable = false
    o:setRenderThisPlayerOnly(playerNum)
    return o
end

function CompanionInventory.show(playerNum, survivorId)
    local player = getSpecificPlayer(playerNum)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not nearby(player, character) then
        return false, "too_far_away"
    end
    local previous = windows[playerNum]
    if previous ~= nil then
        previous:close()
    end
    local window = Window:new(playerNum, survivorId)
    window:initialise()
    window:addToUIManager()
    windows[playerNum] = window
    return true
end

return CompanionInventory
