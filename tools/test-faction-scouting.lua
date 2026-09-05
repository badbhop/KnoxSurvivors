local rootPath = arg[1] or "."
local source = assert(io.open(
    rootPath .. "/mod/42/media/lua/client/KS_FactionBaseScouting.lua",
    "r"
)):read("*a")

assert(source:find("local SCAN_RADII = { 30, 60, 90 }", 1, true),
    "shelter scouting should use bounded staged radii")
assert(source:find("if best ~= nil then break end", 1, true),
    "shelter scouting should stop after the first successful ring")
assert(source:find("outsidePrevious", 1, true),
    "wider rings should avoid rescanning the inner area")
assert(source:find("overlapsPersistedBase", 1, true),
    "wider shelter search must retain base ownership protection")
assert(source:find("safehouseOverlaps", 1, true),
    "wider shelter search must retain vanilla safehouse protection")

print("Faction scouting PASS staged_radii=true bounded=true ownership_safe=true")
