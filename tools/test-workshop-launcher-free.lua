local root = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"), "missing " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

local gradle = read(root .. "/build.gradle.kts")
assert(gradle:find('rename("knox-agent-${project.version}.jar", "knox-agent.jar")', 1, true),
    "staging must publish the agent under a version-stable filename")
assert(gradle:find('include("knox-agent.jar.sha256")', 1, true),
    "staging must ship the stable checksum sidecar")
assert(gradle:find('tools/get-steam-launch-options.ps1', 1, true),
    "staging must ship the Steam launch-option helper")
assert(not gradle:find('include("knox-agent-${project.version}.jar", "knox-agent-${project.version}.jar.sha256")', 1, true),
    "staging must not ship versioned agent names (launch options would rot)")

local helper = read(root .. "/tools/get-steam-launch-options.ps1")
for _, token in ipairs({
    "-javaagent:",
    "ExistingOptions",
    "knox-agent.jar",
    " --",
}) do
    assert(helper:find(token, 1, true),
        "Steam helper must preserve/generate launch integration: " .. token)
end
assert(not helper:find("$bootstrap", 1, true),
    "Steam helper must not depend on the retired command bootstrap")

local runDev = read(root .. "/tools/run-dev.ps1")
assert(runDev:find("java\\knox-agent.jar", 1, true),
    "dev runs must launch against the stable staged agent path")

local description = read(root .. "/workshop/description.bbcode")
for _, token in ipairs({
    "knox-agent.jar",
    "ZombieBuddy",
    "Knox Launcher",
    "KnoxSurvivorsLauncher/releases",
    "KnoxIsoPlayer.log",
}) do
    assert(description:find(token, 1, true),
        "workshop description must document " .. token)
end

local bridge = read(root .. "/mod/42/media/lua/client/KS_JavaBridge.lua")
assert(bridge:find("Java systems are not loaded", 1, true),
    "bridge failure must tell players how to load the agent")

for _, info in ipairs({ "/mod/mod.info", "/mod/42/mod.info" }) do
    local text = read(root .. info)
    assert(not text:find("Launcher required", 1, true),
        info .. " must not claim the launcher is required")
end

print("Workshop launcher-free PASS stable_agent=true direct_option=true docs=true")
