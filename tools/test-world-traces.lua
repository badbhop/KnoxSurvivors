local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["ISUI/ISPanel"] = true
ISPanel = {
    derive = function(_, name)
        return { __name = name }
    end,
}
Events = { OnTick = { Add = function() end }, OnResolutionChange = { Add = function() end } }
getTimestampMs = function() return 0 end

local blood, smashed = {}, {}
local function square(x, y, z, window)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z or 0 end,
        haveBlood = function() return blood[x .. "," .. y] == true end,
        splatBlood = function(_, n, f)
            assert(n == 4 and f == 0.5, "conservative splat arguments")
            blood[x .. "," .. y] = true
        end,
        getObjects = function()
            if window == true then
                return { size = function() return 1 end,
                    get = function(_, i)
                        return {
                            _smashed = false,
                            isSmashed = function(self) return self._smashed end,
                            setSmashed = function(self, v)
                                self._smashed = v
                                smashed[#smashed + 1] = true
                            end,
                        }
                    end }
            end
            return { size = function() return 0 end, get = function() end }
        end,
    }
end

local cells = {}
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        return cells[x .. "," .. y .. "," .. (z or 0)]
    end }
end
local playerSquare = square(100, 100, 0)
getSpecificPlayer = function(num) return num == 0 and {
    getCurrentSquare = function() return playerSquare end,
} or nil end
getNumActivePlayers = function() return 1 end
instanceof = function(object, class) return class == "IsoWindow" end

local stored = {}
KnoxPersistence = {
    getTraceSites = function()
        local out = {}
        for _, site in ipairs(stored) do out[#out + 1] = site end
        return out
    end,
    markTraceVisited = function(id)
        for _, site in ipairs(stored) do
            if site.id == id then site.visited = true return true end
        end
        return false
    end,
}

local traces = dofile(rootPath .. "/mod/42/media/lua/client/KS_WorldTraces.lua")

-- Far sites wait; near fight sites bleed once and never repeat.
stored = { { id = "far", kind = "fight", x = 500, y = 500, z = 0, visited = false } }
for i = 1, 130 do traces.update() end
assert(blood["500,500"] == nil, "far sites stay dormant")
stored = { { id = "near", kind = "fight", x = 102, y = 100, z = 0, visited = false } }
cells["100,100,0"] = square(100, 100, 0)
cells["101,100,0"] = square(101, 100, 0)
cells["102,100,0"] = square(102, 100, 0)
for i = 1, 130 do traces.update() end
assert(stored[1].visited == true, "materialized sites mark visited")
local splats = 0
for _ in pairs(blood) do splats = splats + 1 end
assert(splats >= 1 and splats <= 6, "fight bleeds a bounded patch, got " .. splats)
for i = 1, 130 do traces.update() end
local splats2 = 0
for _ in pairs(blood) do splats2 = splats2 + 1 end
assert(splats2 == splats, "visited sites never re-materialize")

-- Breach sites smash nearby windows once.
blood, smashed = {}, {}
cells["103,100,0"] = square(103, 100, 0, true)
stored = { { id = "breach", kind = "breach", x = 102, y = 100, z = 0, visited = false } }
for i = 1, 130 do traces.update() end
assert(#smashed >= 1 and #smashed <= 4, "breach smashes a bounded set")
assert(stored[1].visited == true, "breach marks visited")

print("World traces PASS dormant=true bounded=true once=true breach=true")
