local root = assert(arg[1], "repository root argument missing")
local file = assert(io.open(root .. "/mod/42/media/lua/client/KS_DeveloperTools.lua", "rb"))
local source = file:read("*a")
file:close()

for _, label in ipairs({
    "Population Scenarios",
    "Combat Tests",
    "Faction & World Events",
    "Destructive Tests",
    "Diagnostics",
}) do
    assert(source:find('addOption("' .. label .. '"', 1, true),
        "developer menu category missing: " .. label)
end

assert(source:find('combatMenu:addOption("Write Combat Snapshot to Log"', 1, true)
    and source:find('combatMenu:addOption("Cleanup Combat Test"', 1, true),
    "combat diagnostics must stay with combat tests")
assert(source:find('destructiveMenu:addOption("Schedule Scientists Entry Here"', 1, true)
    and source:find('destructiveMenu:addOption("Schedule Military Entry Here"', 1, true),
    "entry scenarios must be named for the action they schedule")

print("developer tools menu PASS grouped=true destructive-gated=true")
