local root = arg[1] or "."
require = function() end
local reset
Events = { OnGameStart = { Add = function(f) reset = f end } }
local squares = {}
for x = 1, 4 do
    local floor = { setHighlighted = function(self, value) self.highlight = value end,
        setHighlightColor = function() end }
    squares[x] = { getFloor = function() return floor end }
end
getCell = function() return { getGridSquare = function(_, x) return squares[x] end } end
getSpecificPlayer = function(n) return n end
KnoxPersistence = { ensurePlayerId = function(p) return p end }
local bases = { [0] = { territory = { minX = 1, minY = 1, maxX = 1, maxY = 1 }, zones = {
    a = { x1 = 2, y1 = 1, x2 = 2, y2 = 1, type = "farming" },
} }, [1] = { territory = { minX = 3, minY = 1, maxX = 3, maxY = 1 } } }
KnoxBaseManager = { getForOwner = function(_, id) return bases[id] end }
local h = dofile(root .. "/mod/42/media/lua/client/KS_BaseHighlights.lua")
h.setEnabled(0, true) h.setEnabled(1, true)
assert(squares[1]:getFloor().highlight and squares[2]:getFloor().highlight and squares[3]:getFloor().highlight)
bases[0].zones = {} h.refresh(0)
assert(not squares[2]:getFloor().highlight and squares[3]:getFloor().highlight,
    "deleted zone clears without erasing other viewer")
bases[0].territory.minX, bases[0].territory.maxX = 4, 4 h.refresh(0)
assert(not squares[1]:getFloor().highlight and squares[4]:getFloor().highlight, "old boundary clears")
bases[0] = nil h.refresh(0) assert(not squares[4]:getFloor().highlight)
reset() assert(not squares[3]:getFloor().highlight)
print("Base highlights PASS deletion=true boundary=true split_screen=true base_removed=true reset=true")
