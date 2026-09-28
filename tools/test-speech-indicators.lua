local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["ISUI/ISPanel"] = true

local drawn = {}
local lastPanel = nil
local function stubPanel()
    local panel = {
        initialise = function() end,
        noBackground = function(self) self.background = false end,
        setWantMouseEvents = function(self, value) self.wantMouseEvents = value end,
        setVisible = function(self, v) self.visible = v end,
        setRenderThisPlayerOnly = function() end,
        addToUIManager = function() end,
        removeFromUIManager = function() end,
        getWidth = function() return 800 end,
        getHeight = function() return 600 end,
        drawLine2 = function(self, ...) drawn[#drawn + 1] = { ... } end,
        drawText = function() end,
        playerNum = 0,
        background = true,
    }
    lastPanel = panel
    return panel
end
ISPanel = {
    derive = function(_, name)
        local class = { __name = name }
        class.new = function(_, x, y, w, h)
            local panel = stubPanel()
            panel.x, panel.y = x, y
            return panel
        end
        return class
    end,
}
UIFont = { Small = "small" }

local now = 100000
getTimestampMs = function() return now end

local players = {}
getSpecificPlayer = function(num) return players[num] end
getPlayerScreenWidth = function() return 800 end
getPlayerScreenHeight = function() return 600 end
getPlayerScreenLeft = function() return 0 end
getPlayerScreenTop = function() return 0 end

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
    }
end

players[0] = {
    getCurrentSquare = function() return square(100, 100, 0) end,
}

local indicators = dofile(rootPath .. "/mod/42/media/lua/client/KS_SpeechIndicators.lua")
assert(indicators.MIN_TILES == 10 and indicators.MAX_TILES == 40,
    "arrows cover tracking range only")

-- Far speech: feed-only, no arrow, no tag.
assert(indicators.noteSpeech(square(300, 100, 0), "far-1", false) == nil,
    "distant voices stay out of the tracking UI")
-- Different floor: no arrow even when close in x/y.
assert(indicators.noteSpeech(square(120, 100, 1), "up-1", false) == nil,
    "other floors never draw arrows")
-- Close speech: primary tag with distance and compass.
local info = indicators.noteSpeech(square(130, 100, 0), "near-1", false)
assert(info ~= nil and info.dist == 30, "thirty tiles reads thirty")
assert(info.dir == "E", "due-east speaker reads east, got " .. tostring(info.dir))
local south = indicators.noteSpeech(square(100, 130, 0), "near-2", false)
assert(south ~= nil and south.dir == "S", "south reads south")
local north = indicators.noteSpeech(square(100, 70, 0), "near-3", false)
assert(north ~= nil and north.dir == "N", "north reads north")
local northwest = indicators.noteSpeech(square(80, 80, 0), "near-4", false)
assert(northwest ~= nil and northwest.dir == "NW", "northwest reads northwest")
assert(lastPanel ~= nil and lastPanel.background == false,
    "render-only overlay disables ISPanel's default black background")
assert(lastPanel.wantMouseEvents == false,
    "render-only overlay explicitly passes mouse input through")
indicators.prerender(0, lastPanel)
assert(#drawn > 0, "active indicators render line geometry")
for _, line in ipairs(drawn) do
    assert(not (line[6] == 0.05 and line[7] == 0.05 and line[8] == 0.05),
        "indicator contains no same-width black under-stroke")
end
-- Too close: audible bubble territory, no arrow needed.
assert(indicators.noteSpeech(square(105, 100, 0), "close-1", false) == nil,
    "point-blank speech needs no arrow")
assert(indicators.noteSpeech(square(nil, 100, 0), "stale-1", false) == nil,
    "missing stale speaker coordinates degrade without an error")
assert(indicators.noteSpeech(square(130, 100, nil), "stale-z", false) == nil,
    "missing stale speaker floor degrades without an error")

now = now + indicators.DURATION_MS + 1
indicators.prerender(0, lastPanel)
assert(lastPanel.visible == false, "expired indicators hide their overlay")
indicators.reset()

print("Speech indicators PASS range=true compass=true style=true input=true expiry=true stale=true")
