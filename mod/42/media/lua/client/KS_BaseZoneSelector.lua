require "BuildingObjects/ISSelectCursor"
require "KS_BaseManager"
require "KS_ActivityFeed"

local BaseZoneSelector = rawget(_G, "KnoxBaseZoneSelector") or {}
_G.KnoxBaseZoneSelector = BaseZoneSelector

local Selection = {}
Selection.__index = Selection

function Selection:onSquareSelected(square)
    self.cursor = nil
    if self.firstSquare == nil then
        self.firstSquare = square
        KnoxActivityFeed.event("Work area: select the opposite corner.")
        self.cursor = ISSelectCursor:new(self.player, self, self.onSquareSelected)
        getCell():setDrag(self.cursor, self.player:getPlayerNum())
        return
    end
    local zone, result = KnoxBaseManager.addZone(
        self.baseId,
        self.zoneType,
        {
            x1 = self.firstSquare:getX(),
            y1 = self.firstSquare:getY(),
            x2 = square:getX(),
            y2 = square:getY(),
            z = self.firstSquare:getZ(),
        },
        self.label
    )
    if zone ~= nil then
        KnoxActivityFeed.event("Work area set: " .. tostring(self.label) .. ".")
    else
        KnoxActivityFeed.event("Could not set work area: " .. tostring(result) .. ".")
    end
end

function BaseZoneSelector.start(player, baseId, zoneType, label)
    if player == nil or getCell() == nil then
        return false
    end
    local selection = setmetatable({
        player = player,
        baseId = baseId,
        zoneType = zoneType,
        label = label or zoneType,
        firstSquare = nil,
        cursor = nil,
    }, Selection)
    selection.cursor = ISSelectCursor:new(player, selection, selection.onSquareSelected)
    getCell():setDrag(selection.cursor, player:getPlayerNum())
    KnoxActivityFeed.event("Work area: select the first corner for " .. tostring(selection.label) .. ".")
    return true
end

return BaseZoneSelector
