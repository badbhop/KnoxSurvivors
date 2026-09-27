local root = arg[1] or "."
local file = assert(io.open(root .. "/mod/42/media/lua/client/KS_SurvivorNotebook.lua"))
local source = file:read("*a"); file:close()
-- Exercise the real projection without booting native UI widgets.
local method = assert(source:match("(function MissionsView:populate%(playerNum%).-)\nfunction MissionsView:new"))
MissionsView = {}
local helper = assert(source:match("(local function addRow%(.-)\nlocal ZONE_TYPES"))
assert(loadstring(helper .. "\n" .. method))()
-- File-locals the projection shares with the rest of the notebook.
notebookBases = function() return {} end
claimantName = function(id) return "Name_" .. tostring(id) end
getSpecificPlayer = function() return {} end
local teams = {
    mine = { ownerKind = "player", ownerId = "me", state = "outbound", memberIds = {"traveller"} },
    other = { ownerKind = "player", ownerId = "other", state = "outbound" },
    faction = { ownerKind = "faction", ownerId = "me", state = "outbound" },
    done = { ownerKind = "player", ownerId = "me", state = "complete" },
    failed = { ownerKind = "player", ownerId = "me", state = "blocked" },
}
KnoxPersistence = {
    ensurePlayerId = function() return "me" end,
    getAwayTeams = function() return teams end,
    getSurvivorIds = function() return {"resident", "outsider", "traveller"} end,
    isSurvivorAlive = function() return true end,
    getSurvivorAffiliation = function(id)
        return {kind = id == "outsider" and "faction" or "player", ownerId = "me"}
    end,
    getSurvivorDuty = function(id)
        return {mode = "base", awayTeamId = id == "traveller" and "mine" or nil}
    end,
}
KnoxSurvivorRuntime = { getCharacter = function() return nil end }
KnoxSurvivorViewModel = { getSurvivor = function()
    return {displayName = "Morgan", roleLabel = "Base resident", activity = "Resting"}
end }
local rows = {}
local view = setmetatable({list = {
    clear = function() rows = {} end,
    addItem = function(self, text, id, tooltip)
        assert(text == tooltip, "full row must remain available as tooltip")
        rows[id] = text
        return {}
    end,
}}, {__index = MissionsView})
view:populate(0)
assert(rows.mine and rows.resident and rows.resident:find("Resting", 1, true))
for _, id in ipairs({"other", "faction", "done", "failed", "outsider", "traveller"}) do
    assert(rows[id] == nil, "Away tab leaked or duplicated " .. id)
end
print("Notebook Missions PASS ownership=true active=true noDuplicate=true activity=true")
