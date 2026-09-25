-- Developer tooling must never leave a survivor invincible.
-- Every setZombiesDontAttack(true) writer must live in a scenario-gated
-- probe file that also restores attackability on cleanup, and nothing
-- anywhere may write player god/ghost/invisible state.
local projectRoot = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local clientRoot = projectRoot .. "/mod/42/media/lua/client/"

local function sources(pattern)
    local found = {}
    local dirPath = string.gsub(clientRoot, "/", "\\")
    local pipe = io.popen('dir /b "' .. dirPath .. pattern .. '" 2>nul')
    if pipe == nil then return found end
    for name in pipe:lines() do
        found[#found + 1] = clientRoot .. name
    end
    pipe:close()
    return found
end

local function containsName(path, name)
    return string.find(string.lower(path), name, 1, true) ~= nil
end

-- Probe files allowed to pacify ONLY their own fixture survivors.
local function isProbeFile(path)
    return containsName(path, "probe") or containsName(path, "testscenarios")
        or containsName(path, "test_scenarios")
end

local pacifyWriters = {}
local godWriters = {}
for _, path in ipairs(sources("KS_*.lua")) do
    local text = read(path)
    if string.find(text, "setZombiesDontAttack(true)", 1, true) then
        pacifyWriters[#pacifyWriters + 1] = path
    end
    if string.find(text, "setGodMod(", 1, true)
        or string.find(text, "setGhostMode(", 1, true)
        or string.find(text, "setInvisible(", 1, true) then
        godWriters[#godWriters + 1] = path
    end
end

assert(#godWriters == 0,
    "no file may write player god/ghost/invisible state: "
        .. table.concat(godWriters, ", "))

for _, path in ipairs(pacifyWriters) do
    assert(isProbeFile(path),
        "pacification outside a probe fixture is forbidden: " .. path)
    local text = read(path)
    assert(string.find(text, "KnoxDevTests.enabled", 1, true)
        or string.find(text, "activeScenario", 1, true),
        "probe pacification must be scenario-gated: " .. path)
    assert(string.find(text, "setZombiesDontAttack(false)", 1, true),
        "probe pacification must restore attackability on cleanup: " .. path)
end
assert(#pacifyWriters > 0, "audit must actually observe the known probe writers")

print("Dev pacification PASS god_writers=0 probe_writers=" .. #pacifyWriters)
