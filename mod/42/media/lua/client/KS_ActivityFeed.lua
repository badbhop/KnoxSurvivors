require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"

local ActivityFeed = rawget(_G, "KnoxActivityFeed") or {}
_G.KnoxActivityFeed = ActivityFeed

local MAX_LINES = 7
local WINDOW_WIDTH = 500
local WINDOW_HEIGHT = 172

local FeedWindow = ISCollapsableWindow:derive("KnoxActivityFeedWindow")

function FeedWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local titleHeight = self:titleBarHeight()
    self.messagePanel = ISRichTextPanel:new(
        6,
        titleHeight + 4,
        self.width - 12,
        self.height - titleHeight - 10
    )
    self.messagePanel:initialise()
    self.messagePanel.background = false
    self.messagePanel.autosetheight = false
    self.messagePanel.clip = true
    self.messagePanel:setMargins(6, 4, 6, 4)
    self.messagePanel:setAnchorLeft(true)
    self.messagePanel:setAnchorRight(true)
    self.messagePanel:setAnchorTop(true)
    self.messagePanel:setAnchorBottom(true)
    self:addChild(self.messagePanel)
end

function FeedWindow:new(x, y)
    local window = ISCollapsableWindow:new(x, y, WINDOW_WIDTH, WINDOW_HEIGHT)
    setmetatable(window, self)
    self.__index = self
    window:setTitle("Knox Survivors")
    window:setResizable(false)
    window.backgroundColor = { r = 0, g = 0, b = 0, a = 0.72 }
    window.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return window
end

ActivityFeed.lines = ActivityFeed.lines or {}
ActivityFeed.window = ActivityFeed.window or nil

local function ensureWindow()
    if ActivityFeed.window ~= nil then
        return ActivityFeed.window
    end
    local x = 18
    local y = math.max(18, getCore():getScreenHeight() - WINDOW_HEIGHT - 42)
    local window = FeedWindow:new(x, y)
    window:initialise()
    window:addToUIManager()
    window:setVisible(false)
    ActivityFeed.window = window
    return window
end

local function refreshWindow()
    local window = ensureWindow()
    local formatted = {}
    for _, line in ipairs(ActivityFeed.lines) do
        formatted[#formatted + 1] = line.colour .. " " .. line.text
    end
    window.messagePanel.text = table.concat(formatted, " <LINE> ")
    window.messagePanel:paginate()
    window.messagePanel:setYScroll(-math.max(
        0,
        window.messagePanel:getScrollHeight() - window.messagePanel:getHeight()
    ))
    window:setVisible(true)
    window:bringToTop()
end

local function addLine(text, colour)
    ActivityFeed.lines[#ActivityFeed.lines + 1] = {
        text = tostring(text),
        colour = colour,
    }
    while #ActivityFeed.lines > MAX_LINES do
        table.remove(ActivityFeed.lines, 1)
    end
    refreshWindow()
end

local function characterName(character)
    if character == nil or character:getDescriptor() == nil then
        return "Survivor"
    end
    local descriptor = character:getDescriptor()
    local forename = tostring(descriptor:getForename() or "")
    local surname = tostring(descriptor:getSurname() or "")
    local name = string.gsub(forename .. " " .. surname, "^%s*(.-)%s*$", "%1")
    return name ~= "" and name or "Survivor"
end

function ActivityFeed.speak(character, text)
    if character ~= nil then
        pcall(function()
            character:Say(text)
        end)
    end
    addLine(characterName(character) .. ": " .. tostring(text), "<RGB:0.93,0.93,0.93>")
end

function ActivityFeed.event(text)
    addLine(tostring(text), "<RGB:0.68,0.82,0.52>")
end

local function reset()
    ActivityFeed.lines = {}
    if ActivityFeed.window ~= nil then
        ActivityFeed.window:removeFromUIManager()
        ActivityFeed.window = nil
    end
end

Events.OnGameStart.Add(reset)

return ActivityFeed
