local rootPath = arg[1] or "."

package.loaded["KS_BaseManager"] = true
package.loaded["KS_ActivityFeed"] = true
package.loaded["KS_BaseHighlights"] = true
package.loaded["KS_Persistence"] = true

local territoryCalls = 0
local zoneCalls = 0
KnoxBaseManager = {
    setTerritory = function()
        territoryCalls = territoryCalls + 1
        return {}, "ok"
    end,
    addZone = function()
        zoneCalls = zoneCalls + 1
        return {}, "ok"
    end,
}
KnoxActivityFeed = { event = function() end }
KnoxBaseHighlights = { setDraft = function() end }
KnoxPersistence = {
    getBase = function()
        return { territory = { minX = 0, minY = 0, maxX = 100, maxY = 100, z = 0 }, zones = {} }
    end,
}

Events = {
    OnTick = {
        Add = function() end,
        Remove = function() end,
    },
}

local activeDrag = nil
local cell = {
    setDrag = function(_, cursor)
        activeDrag = cursor
    end,
    getGridSquare = function() return nil end,
}
function getCell() return cell end
function getJoypadData() return nil end
function getMouseX() return 0 end
function getMouseY() return 0 end
function screenToIsoX() return 0 end
function screenToIsoY() return 0 end

ISSelectCursor = {}
function ISSelectCursor:new(player, ui, callback)
    return { player = player, ui = ui, callback = callback, skipWalk2 = false }
end

local lastModal = nil
ISModalDialog = {}
function ISModalDialog:new(_, _, _, _, _, _, target, callback)
    local modal = {
        target = target,
        callback = callback,
        initialise = function() end,
        addToUIManager = function() end,
    }
    lastModal = modal
    return modal
end

local player = {
    getPlayerNum = function() return 0 end,
    getZ = function() return 0 end,
}
local function square(x, y)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return 0 end,
    }
end

local territory = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseTerritorySelector.lua")
assert(territory.start(player, "base-1"), "territory selector should start")
assert(activeDrag and activeDrag.skipWalk2 == true,
    "territory selection must opt out of ISBuildingObject walk-to")
activeDrag.ui:onSquareSelected(square(10, 10))
assert(activeDrag and activeDrag.skipWalk2 == true,
    "territory second-corner cursor must keep walk-to disabled")
activeDrag.ui:onSquareSelected(square(12, 13))
assert(lastModal and lastModal.callback, "territory confirmation modal must open")
assert(pcall(lastModal.callback, lastModal.target, { internal = "YES" }),
    "territory modal callback must accept Build 42 target/button arguments")
assert(territoryCalls == 1, "territory confirmation must save exactly once")

local zone = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseZoneSelector.lua")
assert(zone.start(player, "base-1", "guard", "Guard"), "zone selector should start")
assert(activeDrag and activeDrag.skipWalk2 == true,
    "zone selection must opt out of ISBuildingObject walk-to")
activeDrag.ui:onSquareSelected(square(20, 20))
assert(activeDrag and activeDrag.skipWalk2 == true,
    "zone second-corner cursor must keep walk-to disabled")
activeDrag.ui:onSquareSelected(square(22, 21))
assert(lastModal and lastModal.callback, "zone confirmation modal must open")
assert(pcall(lastModal.callback, lastModal.target, { internal = "YES" }),
    "zone modal callback must accept Build 42 target/button arguments")
assert(zoneCalls == 1, "zone confirmation must save exactly once")

print("Base selectors PASS modal=true skipWalk2=true territory=true zone=true")
