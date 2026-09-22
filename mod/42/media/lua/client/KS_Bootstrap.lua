local KnoxSurvivors = rawget(_G, "KnoxSurvivors") or {}
_G.KnoxSurvivors = KnoxSurvivors

KnoxSurvivors.VERSION = "0.0.1-dev"

local function onGameStart()
    print("[KnoxSurvivors] Lua bootstrap loaded version=" .. KnoxSurvivors.VERSION)
end

Events.OnGameStart.Add(onGameStart)
require "KS_AutomatedQA"
