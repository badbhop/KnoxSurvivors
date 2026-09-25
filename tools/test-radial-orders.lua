local projectRoot = arg[1] or "."

require = function()
    return true
end

local eventsAdded = {}
Events = {
    OnGameStart = {
        Add = function(fn)
            eventsAdded[#eventsAdded + 1] = fn
        end,
    },
}

local players = {}
getSpecificPlayer = function(num)
    return players[num]
end

local function makeSquare(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
    }
end

-- Fake vanilla radial menu: records slices, mimics fill-then-select flow.
local radialMenu = {
    slices = {},
    addSlice = function(self, text, texture, command, ...)
        self.slices[#self.slices + 1] = {
            text = text, texture = texture, command = { command, ... },
        }
    end,
    clear = function(self)
        self.slices = {}
    end,
    addToUIManager = function(self) end,
}
getPlayerRadialMenu = function()
    return radialMenu
end

getText = function(key)
    return key
end
getTexture = function(path)
    return "tex:" .. tostring(path)
end
KnoxSurvivorViewModel = {
    getSurvivor = function(id)
        return { displayName = "VM_" .. tostring(id), sex = "female" }
    end,
}

local dispatchedAll = {}
local dispatchedOne = {}
local talked, recruited, recalled, unstuck = {}, {}, {}, {}
local companionIds = { "c1", "c2" }
local residentIds = { "r1" }
local activeIds = { "c1", "c2", "r1", "s1", "dead1" }
local aliveIds = { c1 = true, c2 = true, r1 = true, s1 = true }
local characters = {}
KnoxCompanionService = {
    getPlayerId = function()
        return "owner0"
    end,
    getCompanionIds = function()
        return companionIds
    end,
    issueOrderAll = function(player, kind)
        dispatchedAll[#dispatchedAll + 1] = { player = player, kind = kind }
        return true
    end,
    issueOrder = function(player, survivorId, kind)
        dispatchedOne[#dispatchedOne + 1] = {
            player = player, id = survivorId, kind = kind,
        }
        return true
    end,
    unstick = function(player, survivorId)
        unstuck[#unstuck + 1] = { player = player, id = survivorId }
        return true
    end,
    talk = function(player, survivorId)
        talked[#talked + 1] = { player = player, id = survivorId }
        return true
    end,
    recruit = function(player, survivorId)
        recruited[#recruited + 1] = { player = player, id = survivorId }
        return true
    end,
    recallToParty = function(player, survivorId)
        recalled[#recalled + 1] = { player = player, id = survivorId }
        return true
    end,
}
KnoxSurvivorRuntime = {
    getCharacter = function(id)
        return characters[id]
    end,
    activeIds = function()
        return activeIds
    end,
}
KnoxBaseManager = {
    getForOwner = function()
        return { id = "base0" }
    end,
}
KnoxPersistence = {
    getBaseResidentIds = function()
        return residentIds
    end,
    getSurvivorAffiliation = function(id)
        if id == "s1" or id == "dead1" then
            return { kind = "independent" }
        end
        return { kind = "player", ownerId = "owner0" }
    end,
    isSurvivorAlive = function(id)
        return aliveIds[id] == true
    end,
    getSurvivorIdentity = function(id)
        return { forename = "Name_" .. tostring(id), surname = "" }
    end,
}
KnoxOrderCatalog = {
    label = function(kind, fallback)
        return fallback or tostring(kind)
    end,
}

-- Case 1: no vanilla API -> dormant, nothing wrapped, no error.
ISEmoteRadialMenu = nil
local radialPath = projectRoot
    .. "/mod/42/media/lua/client/KS_RadialOrders.lua"
assert(loadfile(radialPath))()
local Radial = assert(KnoxRadialOrders)
assert(Radial.install() == false, "absent API must stay dormant")
assert(Radial.isInstalled() == false, "dormant install must report false")

-- Case 2: real-ish API -> installs once, appends one Knox slice.
local fillCalls = 0
ISEmoteRadialMenu = {
    icons = { group = "g", back = "b" },
    fillMenu = function(self, submenu)
        fillCalls = fillCalls + 1
        radialMenu:clear()
        radialMenu:addSlice("Wave", nil, function() end)
    end,
}
players[0] = {
    id = "player0",
    getCurrentSquare = function() return makeSquare(0, 0, 0) end,
}
players[1] = {
    id = "player1",
    getCurrentSquare = function() return makeSquare(100, 100, 0) end,
}
characters.c1 = { getCurrentSquare = function() return makeSquare(2, 0, 0) end }
characters.c2 = { getCurrentSquare = function() return makeSquare(0, 3, 0) end }
characters.r1 = { getCurrentSquare = function() return makeSquare(1, 1, 0) end }
characters.s1 = { getCurrentSquare = function() return makeSquare(3, 0, 0) end }
characters.dead1 = { getCurrentSquare = function() return makeSquare(1, 0, 0) end }
assert(Radial.install() == true, "present API must install")
assert(Radial.isInstalled() == true, "installed flag must report true")
assert(Radial.install() == true, "second install must be a no-op success")

local function select(index)
    local slice = radialMenu.slices[index]
    assert(slice ~= nil and slice.command ~= nil, "slice " .. tostring(index) .. " selectable")
    local cmd = slice.command
    cmd[1](cmd[2], cmd[3], cmd[4])
end

local menuSelf = { playerNum = 0 }
ISEmoteRadialMenu.fillMenu(menuSelf, nil)
assert(fillCalls == 1, "original fill must run exactly once")
assert(#radialMenu.slices == 2, "base menu must gain exactly one Knox slice")
assert(radialMenu.slices[2].text == "Knox Orders", "Knox entry label")
assert(radialMenu.slices[2].texture == "tex:media/ui/knoxOrders.png",
    "custom Knox button art is picked up when present")

-- Case 3: Knox root shows the four tabs plus back.
select(2)
assert(#radialMenu.slices == 5, "knox level has 4 tabs + back")
assert(radialMenu.slices[1].text == "Party Orders", "party tab first")
assert(radialMenu.slices[2].text == "Followers", "followers tab")
assert(radialMenu.slices[3].text == "Residents", "residents tab")
assert(radialMenu.slices[4].text == "Nearby Survivors", "nearby tab")
assert(radialMenu.slices[5].text == "IGUI_Emote_Back", "knox level has back")

-- Case 4: followers tab lists companions sorted; orders dispatch + rebuild.
select(2)
assert(#radialMenu.slices == 3, "followers tab has 2 companions + back")
assert(radialMenu.slices[1].text == "VM_c1", "followers sorted by name")
assert(radialMenu.slices[1].texture == "tex:media/ui/defense/female_base.png",
    "follower slice uses the outline icon")
select(1)
assert(#radialMenu.slices == 10, "follower level has 9 orders + back")
assert(radialMenu.slices[6].text == "Survival Orders", "survival submenu entry present")
select(1)
assert(#dispatchedOne == 1, "follower select dispatches once")
assert(dispatchedOne[1].player.id == "player0", "dispatch targets radial player")
assert(dispatchedOne[1].id == "c1", "dispatch targets that follower")
assert(dispatchedOne[1].kind == "follow", "dispatch carries order kind")
assert(#radialMenu.slices == 10, "wheel rebuilds at the follower level")

-- Case 4b: follower survival submenu dispatches per-survivor find orders.
select(6)
assert(#radialMenu.slices == 6, "follower survival has 5 kinds + back")
assert(radialMenu.slices[1].text == "find_food", "food first")
select(1)
assert(#dispatchedOne == 2, "survival select dispatches once")
assert(dispatchedOne[2].id == "c1", "survival targets that follower")
assert(dispatchedOne[2].kind == "find_food", "survival carries find kind")
assert(#radialMenu.slices == 6, "wheel rebuilds at the survival level")
select(6)
assert(#radialMenu.slices == 10, "survival back returns to the follower level")

-- Case 5: party tab dispatches issueOrderAll and rebuilds.
Radial.fillKnox(menuSelf, "knox")
select(1)
assert(#radialMenu.slices == 8, "party level has 7 orders + back")
select(2)
assert(#dispatchedAll == 1, "party select dispatches once")
assert(dispatchedAll[1].player.id == "player0", "party targets radial player")
assert(dispatchedAll[1].kind == "hold", "party carries order kind")
assert(#radialMenu.slices == 8, "wheel rebuilds at the party level")

-- Case 6: residents tab excludes companions; recall dispatches + rebuilds.
Radial.fillKnox(menuSelf, "knox")
select(3)
assert(#radialMenu.slices == 2, "residents tab has r1 + back")
assert(radialMenu.slices[1].text == "VM_r1", "resident listed by name")
select(1)
assert(#radialMenu.slices == 5, "resident level has 4 orders + back")
assert(radialMenu.slices[1].text == "Check Needs", "resident needs first")
assert(radialMenu.slices[2].text == "Survival Orders", "resident survival second")
assert(radialMenu.slices[3].text == "Recall to Party", "resident recall third")
assert(radialMenu.slices[4].text == "Unstick", "resident unstick fourth")
select(3)
assert(#recalled == 1 and recalled[1].id == "r1", "recall dispatches for r1")
assert(recalled[1].player.id == "player0", "recall targets radial player")
assert(#radialMenu.slices == 5, "wheel rebuilds at the resident level")

-- Case 6b: resident survival submenu dispatches base supply orders.
select(2)
assert(#radialMenu.slices == 7, "resident survival has 6 kinds + back")
select(3)
assert(#dispatchedOne == 3, "resident survival dispatches once")
assert(dispatchedOne[3].id == "r1", "resident survival targets that resident")
assert(dispatchedOne[3].kind == "find_wood", "resident survival carries find kind")
assert(#radialMenu.slices == 7, "wheel rebuilds at the resident survival level")
select(7)
assert(#radialMenu.slices == 5, "resident survival back returns to resident level")

-- Case 7: nearby tab has the stranger only; talk + recruit dispatch.
Radial.fillKnox(menuSelf, "knox")
select(4)
assert(#radialMenu.slices == 2, "nearby tab has s1 + back (dead1 excluded)")
assert(radialMenu.slices[1].text == "VM_s1", "stranger listed by name")
select(1)
assert(#radialMenu.slices == 3, "nearby level has talk/recruit + back")
select(1)
assert(#talked == 1 and talked[1].id == "s1", "talk dispatches for s1")
select(2)
assert(#recruited == 1 and recruited[1].id == "s1", "recruit dispatches for s1")
assert(#radialMenu.slices == 3, "wheel rebuilds at the nearby level")

-- Case 8: back navigation climbs one level everywhere.
select(3)
assert(#radialMenu.slices == 2, "back returns to the nearby tab")
select(2)
assert(#radialMenu.slices == 5, "tab back returns to knox level")
assert(radialMenu.slices[1].text == "Party Orders", "knox level intact")
Radial.fillKnox(menuSelf, "knox")
select(4)
select(2)
assert(#radialMenu.slices == 5, "nearby back returns to knox level")

-- Case 9: stale ids fall back to the parent tab level.
Radial.fillKnox(menuSelf, "f:gone")
assert(radialMenu.slices[1].text == "VM_c1", "stale follower falls back to tab")
Radial.fillKnox(menuSelf, "r:gone")
assert(radialMenu.slices[1].text == "VM_r1", "stale resident falls back to tab")
Radial.fillKnox(menuSelf, "n:gone")
assert(radialMenu.slices[1].text == "VM_s1", "stale stranger falls back to tab")

-- Case 10: far/off-floor followers excluded; second player isolated.
characters.c1 = { getCurrentSquare = function() return makeSquare(50, 0, 0) end }
characters.c2 = { getCurrentSquare = function() return makeSquare(0, 3, 1) end }
characters.r1 = nil
characters.s1 = nil
Radial.fillKnox(menuSelf, "knox")
assert(#radialMenu.slices == 1, "empty tabs are omitted, back only")
local menuSelf1 = { playerNum = 1 }
ISEmoteRadialMenu.fillMenu(menuSelf1, nil)
assert(#radialMenu.slices == 1, "player 1 with nobody nearby sees vanilla only")

-- Case 11: submenus stay vanilla; repeated fills never duplicate.
ISEmoteRadialMenu.fillMenu(menuSelf, "group")
assert(#radialMenu.slices == 1, "submenu fills must stay vanilla")
characters.c1 = { getCurrentSquare = function() return makeSquare(2, 0, 0) end }
characters.c2 = { getCurrentSquare = function() return makeSquare(0, 3, 0) end }
characters.r1 = { getCurrentSquare = function() return makeSquare(1, 1, 0) end }
characters.s1 = { getCurrentSquare = function() return makeSquare(3, 0, 0) end }
ISEmoteRadialMenu.fillMenu(menuSelf, nil)
ISEmoteRadialMenu.fillMenu(menuSelf, nil)
assert(#radialMenu.slices == 2, "repeated fills must not duplicate")
assert(fillCalls == 5, "original fill runs once per open")

print("Radial orders PASS tabs=true dispatch=true rebuild=true back=true stale_safe=true split=true idempotent=true")
