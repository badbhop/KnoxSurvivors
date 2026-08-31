local root = arg[1] or "."
local fixture = dofile(root .. "/tools/test-trade-action.lua")
local now, fontHeight, screenWidth, screenHeight = 0, 14, 1280, 720
getTimestampMs = function() return now end
UIFont = { Small = "small" }
getTextManager = function() return { getFontHeight = function() return fontHeight end,
    MeasureStringX = function(_, _, text) return #text * fontHeight * .5 end } end
getText = function(key) return key == "UI_Close" and "Close" or key end
getTexture = function(path) return path end
getPlayerScreenWidth = function() return screenWidth end
getPlayerScreenHeight = function() return screenHeight end
getPlayerScreenLeft = function(index) return index * screenWidth end
getPlayerScreenTop = function() return 0 end
getCore = function() return { getGoodHighlitedColor = function() return {
    getR = function() return .2 end, getG = function() return .8 end, getB = function() return .2 end } end } end
Joypad = { AButton = 1, BButton = 2, YButton = 3 }
JoypadState = { players = {} }
setJoypadFocus = function(index, focus) JoypadState.players[index + 1].focus = focus end
local callbacks = {}
for _, event in ipairs({ "OnGameStart", "OnMainMenuEnter", "OnResolutionChange", "OnPlayerDeath", "OnFillWorldObjectContextMenu" }) do
    Events[event] = { Add = function(callback) callbacks[event] = callback end }
end
local Widget = {}
Widget.__index = Widget
function Widget:derive(name) local result = { Type = name }; result.__index = result; return setmetatable(result, { __index = self }) end
function Widget:new(x, y, width, height)
    return setmetatable({ x = x, y = y, width = width, height = height, selected = 1, items = {}, visible = true }, self)
end
function Widget:initialise() self.children = {} end
function Widget:instantiate()
    if self.instantiated then return end
    self.instantiated = true
    self:createChildren()
end
function Widget:createChildren() end
function Widget:addChild(child) child.parent = self; child:instantiate(); self.children[#self.children + 1] = child end
function Widget:addToUIManager() self:instantiate() self.inManager = true end
function Widget:removeFromUIManager() self.inManager = false end
function Widget:setVisible(value) self.visible = value end
function Widget:setRenderThisPlayerOnly(value) self.renderPlayer = value end
function Widget:setTitle(value) self.title = value end
function Widget:titleBarHeight() return fontHeight + 6 end
function Widget:setFont() end
function Widget:setEnable(value) self.enabled = value end
function Widget:setOnMouseDoubleClick(target, callback) self.target, self.onmousedblclick = target, callback end
function Widget:addItem(text, item) self.items[#self.items + 1] = { text = text, item = item, index = #self.items + 1 } end
function Widget:clear() self.items = {} self.selected = 1 end
function Widget:getYScroll() return self.scroll or 0 end
function Widget:setYScroll(value) self.scroll = value end
function Widget:update() end
function Widget:prerender() end
function Widget:drawRect() end
function Widget:drawTextureScaledAspect() end
function Widget:drawText(text, x, y)
    assert(x >= 0 and y >= 0 and x + #text * fontHeight * .5 <= self.width + 1,
        "text stays inside its panel: " .. text)
    assert(y + fontHeight <= self.height + 1, "text does not fall off the bottom")
end
function Widget:onJoypadDown() end
ISCollapsableWindowJoypad = Widget:derive("Window")
function ISCollapsableWindowJoypad:createChildren() self.chromeCreated = (self.chromeCreated or 0) + 1 end
ISScrollingListBox = Widget:derive("List")
function ISScrollingListBox:onJoypadDown(button)
    if button == Joypad.AButton and self.items[self.selected] then self.onmousedblclick(self.target, self.items[self.selected].item) end
end
ISButton = Widget:derive("Button")
function ISButton:new(x, y, width, height, title, target, callback)
    local result = Widget.new(self, x, y, width, height)
    result.title, result.target, result.onclick = title, target, callback
    return result
end
local ui = dofile(root .. "/mod/42/media/lua/client/KS_TradeUI.lua")
local player, npc, controller, giving, taking
local function addPresentation(item)
    function item:getName() return self.full end
    function item:getTex() return "item-texture" end
end
local function setup()
    ui.closeAll()
    player, npc, controller, giving, taking = fixture.setup()
    addPresentation(giving) addPresentation(taking)
    function player:getPlayerNum() return 0 end
    assert(KnoxPersistence.ensureSurvivorIdentity("exchange", "Jamie", "Miller", 0, 30))
    now = 0
end
local function show() return assert(ui.show(0, "exchange")) end
local function selectBoth(window)
    window.playerList.onmousedblclick(window.playerList.target, giving)
    window.survivorList.onmousedblclick(window.survivorList.target, taking)
end
setup()
local window = show()
assert(window.title == "Trade - Jamie Miller" and window.chromeCreated == 1 and window.renderPlayer == 0)
assert(#window.playerList.items == 1 and #window.survivorList.items == 1)
assert(not window.tradeButton.enabled and controller.state == "TRADING")
selectBoth(window)
assert(window.tradeButton.enabled and window.status == "That looks fair.")
window:prerender()
window.playerList:doDrawItem(0, window.playerList.items[1])
window:exchange()
assert(window.action and window.session.finished and not window.tradeButton.enabled)
window:exchange() -- no duplicate queue
window.action:perform() window:update()
assert(window.status == "Trade complete." and giving:getContainer() == npc.inventory and taking:getContainer() == player.inventory)
assert(window.closed and not window.inManager and ui.windows[0] == nil,
    "successful exchange automatically closes after real item transfer")
window:close()
assert(not window.inManager and ui.windows[0] == nil and controller.state == "IDLE")

setup() window = show() selectBoth(window) window:close()
assert(giving:getContainer() == player.inventory and controller.tradeAction == nil)
setup() window = show() selectBoth(window) window:exchange() window:close() window.action:perform()
assert(giving:getContainer() == player.inventory and taking:getContainer() == npc.inventory,
    "closing during an exchange cancels only that exchange before mutation")
setup() window = show() selectBoth(window) window:exchange()
window.action:finish(false, "exchange_rolled_back") window:update()
assert(not window.closed and window.status ~= "Trade complete.", "failed exchange remains visible")
setup() window = show() selectBoth(window) giving.favorite = true
now = 1001 window:update()
assert(not window.tradeButton.enabled and window.status:find("favorite"))
window:exchange()
assert(not window.action and giving:getContainer() == player.inventory)
setup() window = show() selectBoth(window) npc.inventory.capacity = 0 window:exchange()
assert(window.status:find("space") and not window.tradeButton.enabled)
now = 1001 window:update()
assert(window.status:find("space") and not window.tradeButton.enabled, "capacity failure is not replaced by a misleading fair label")
setup() npc.blocked = true window = show()
local failure = window.status window:update()
assert(window.status == failure and failure:find("blocking"), "initial failure remains readable")
setup() window = show() now = 120001 window:update()
assert(controller.state == "IDLE" and not window.tradeButton.enabled)
setup() window = show() npc.attackers = 1 controller.nextThreatScan = 999999 controller:tick(1) window:update()
assert(controller.state == "IDLE" and not window.tradeButton.enabled)
setup() window = show() callbacks.OnMainMenuEnter()
assert(window.closed and controller.tradeAction == nil)
setup() window = show() callbacks.OnPlayerDeath(player)
assert(window.closed and controller.tradeAction == nil)

-- Layout uses native font metrics and the local viewport, not off-slot player UI indices.
for _, dimensions in ipairs({ { 1280, 720, 14 }, { 480, 360, 14 }, { 480, 360, 32 } }) do
    setup() screenWidth, screenHeight, fontHeight = unpack(dimensions)
    window = show() window:prerender()
    assert(window.width <= screenWidth and window.height <= screenHeight)
    assert(window.statusY + fontHeight * (2 + window.helpLines) <= window.tradeButton.y)
    for _, child in ipairs(window.children) do
        assert(child.x >= 0 and child.y >= 0 and child.x + child.width <= window.width + 1
            and child.y + child.height <= window.height + 1, "native controls fit their parent")
    end
    callbacks.OnResolutionChange()
    assert(window.closed)
end
screenWidth, screenHeight, fontHeight = 1280, 720, 14
setup()
local priorFocus = {}
JoypadState.players[1] = { focus = priorFocus }
window = show()
assert(JoypadState.players[1].focus == window.playerList)
window.playerList:onJoypadDown(Joypad.AButton, JoypadState.players[1])
assert(window.giving[giving])
window.survivorList:onJoypadDown(Joypad.AButton, JoypadState.players[1])
assert(window.taking[taking])
window.survivorList:onJoypadDown(Joypad.BButton, JoypadState.players[1])
assert(window.closed and JoypadState.players[1].focus == priorFocus)
JoypadState.players = {}

-- Real context-menu callback targets this UI and never grants independent loot access.
setup()
KnoxCompanionService = { getPlayerId = function(actor) return actor:getModData().KnoxSurvivors.playerId end,
    canRecruit = function() return false, "trust" end }
local context = dofile(root .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua")
local function menu()
    return { options = {}, addOption = function(self, label, target, callback, ...)
        local option = { target = target, callback = callback, args = { ... } }
        self.options[label] = option return option
    end }
end
local options = menu()
assert(context.populate(options, 0, "exchange") and options.options.Trade and not options.options["Manage Inventory"])
local option = options.options.Trade
option.callback(option.target, unpack(option.args))
assert(ui.windows[0] and controller.state == "TRADING")
ui.closeAll()
KnoxPersistence.setSurvivorHostileToPlayer("exchange", player:getModData().KnoxSurvivors.playerId, true)
options = menu() context.populate(options, 0, "exchange")
assert(options.options["Trade (hostile)"].notAvailable)
setup() isClient = function() return true end
options = menu() context.populate(options, 0, "exchange")
assert(options.options["Trade (single-player only)"].notAvailable)
isClient = function() return false end
print("trade UI PASS context=true real-exchange=true native-widgets=true layout=true cancel=true expiry=true joypad=true")
