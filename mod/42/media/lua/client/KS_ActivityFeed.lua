require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"

local ActivityFeed = rawget(_G, "KnoxActivityFeed") or {}
_G.KnoxActivityFeed = ActivityFeed

local MAX_LINES = 7
local WINDOW_WIDTH = 500
local WINDOW_HEIGHT = 172
local GROUP_COLOURS = {
    "<RGB:0.65,0.82,0.42>",
    "<RGB:0.45,0.72,0.90>",
    "<RGB:0.88,0.62,0.34>",
    "<RGB:0.78,0.52,0.86>",
    "<RGB:0.88,0.48,0.48>",
}

local FeedWindow = ISCollapsableWindow:derive("KnoxActivityFeedWindow")

function FeedWindow:new(x, y)
    -- Keep compact; clamp to viewport like other Knox windows.
    local w = math.min(WINDOW_WIDTH, math.max(1, getCore():getScreenWidth() - 20))
    local h = math.min(WINDOW_HEIGHT, math.max(1, getCore():getScreenHeight() - 20))
    local window = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(window, self)
    self.__index = self
    window:setTitle("Knox Survivors")
    window:setResizable(true)
    window.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.88 }
    window.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.92 }
    return window
end

function FeedWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    if self.closeButton ~= nil then
        self.closeButton:setVisible(false)
        self.closeButton:setEnable(false)
    end
    local titleHeight = self:titleBarHeight()
    local pad = 10
    self.messagePanel = ISRichTextPanel:new(
        pad,
        titleHeight + 4,
        self.width - pad * 2,
        self.height - titleHeight - pad - 2
    )
    self.messagePanel:initialise()
    self.messagePanel.background = true
    self.messagePanel.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.92 }
    self.messagePanel.autosetheight = false
    self.messagePanel.clip = true
    self.messagePanel:setMargins(6, 4, 6, 4)
    self.messagePanel:setAnchorLeft(true)
    self.messagePanel:setAnchorRight(true)
    self.messagePanel:setAnchorTop(true)
    self.messagePanel:setAnchorBottom(true)
    self:addChild(self.messagePanel)
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
    if not KnoxSettings.showActivityFeed() then
        return
    end
    ActivityFeed.lines[#ActivityFeed.lines + 1] = {
        text = tostring(text),
        colour = colour,
    }
    while #ActivityFeed.lines > MAX_LINES do
        table.remove(ActivityFeed.lines, 1)
    end
    refreshWindow()
end

local function stableColour(key)
    local hash = 0
    for index = 1, #tostring(key or "independent") do
        hash = (hash * 31 + string.byte(tostring(key), index)) % 2147483647
    end
    return GROUP_COLOURS[(hash % #GROUP_COLOURS) + 1]
end

local function speakerContext(character)
    local id = KnoxSurvivorRuntime.idForCharacter(character)
    local affiliation = id ~= nil and KnoxPersistence.getSurvivorAffiliation(id) or nil
    if affiliation ~= nil and affiliation.kind == "player" then
        return "YOUR PARTY", "<RGB:0.68,0.84,0.43>"
    end
    if affiliation ~= nil and affiliation.factionId ~= nil then
        local label = string.upper(tostring(affiliation.factionId):gsub("%-", " "))
        return label, stableColour(affiliation.factionId)
    end
    local group = id ~= nil and KnoxPersistence.getTravelGroupFor(id) or nil
    if group ~= nil then
        local label = string.upper(tostring(group.id):gsub("travel%-group%-", "GROUP "))
        return label, stableColour(group.id)
    end
    return "SURVIVOR", "<RGB:0.82,0.82,0.76>"
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
    local groupLabel, colour = speakerContext(character)
    addLine("[" .. groupLabel .. "] " .. characterName(character)
        .. ": " .. tostring(text), colour)
end

function ActivityFeed.event(text)
    addLine(tostring(text), "<RGB:0.68,0.82,0.52>")
end

function ActivityFeed.show()
    local window = ensureWindow()
    refreshWindow()
    window:setVisible(true)
    window:bringToTop()
    return window
end

function ActivityFeed.hide()
    -- Feed stays open and resizable; X removed, so hide is a no-op that keeps it visible.
    if ActivityFeed.window ~= nil then
        ActivityFeed.window:setVisible(true)
        ActivityFeed.window:bringToTop()
    end
end

function ActivityFeed.toggle()
    ActivityFeed.show()
end

local function reset()
    ActivityFeed.lines = {}
    if ActivityFeed.window ~= nil then
        ActivityFeed.window:removeFromUIManager()
        ActivityFeed.window = nil
    end
end

function ActivityFeed.applySettings()
    if not KnoxSettings.showActivityFeed() and ActivityFeed.window ~= nil then
        ActivityFeed.window:setVisible(false)
    end
end

Events.OnGameStart.Add(reset)

return ActivityFeed
