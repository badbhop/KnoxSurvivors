require "BuildingObjects/ISSelectCursor"
require "KS_BaseManager"
require "KS_ActivityFeed"

local BaseTerritorySelector = rawget(_G, "KnoxBaseTerritorySelector") or {}
_G.KnoxBaseTerritorySelector = BaseTerritorySelector

local Selection = {}
Selection.__index = Selection

function Selection:onSquareSelected(square)
    self.cursor = nil
    if self.firstSquare == nil then
        self.firstSquare = square
        KnoxActivityFeed.event("Base boundary: select the opposite corner.")
        self.cursor = ISSelectCursor:new(self.player, self, self.onSquareSelected)
        getCell():setDrag(self.cursor, self.player:getPlayerNum())
        return
    end
    local territory, result = KnoxBaseManager.setTerritory(
        self.player,
        self.baseId,
        self.firstSquare,
        square
    )
    if territory ~= nil then
        KnoxActivityFeed.event("Home base boundary updated across all floors.")
    else
        KnoxActivityFeed.event("Could not set base boundary: " .. tostring(result) .. ".")
    end
end

function BaseTerritorySelector.start(player, baseId)
    if player == nil or getCell() == nil then
        return false
    end
    local selection = setmetatable({
        player = player,
        baseId = baseId,
        firstSquare = nil,
        cursor = nil,
    }, Selection)
    selection.cursor = ISSelectCursor:new(player, selection, selection.onSquareSelected)
    getCell():setDrag(selection.cursor, player:getPlayerNum())
    KnoxActivityFeed.event("Base boundary: select the first corner.")
    return true
end

return BaseTerritorySelector
