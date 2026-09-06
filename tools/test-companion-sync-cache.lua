local root = arg[1] or "."
local file = assert(io.open(root .. "/mod/42/media/lua/client/KS_CompanionService.lua", "r"))
local source = file:read("*a")
file:close()

assert(source:find("local syncCache = {}", 1, true),
    "companion sync must keep a bounded runtime cache")
assert(source:find("local previousKey = syncCache[survivorId]", 1, true),
    "companion sync must compare the previous state")
assert(source:find("if previousKey == cacheKey then", 1, true),
    "unchanged companion state must skip repeated setter work")
assert(source:find("syncCache[survivorId] = cacheKey", 1, true),
    "changed companion state must update the cache")
assert(source:find("roster = table.concat(parts, \",\")", 1, true),
    "formation roster changes must invalidate the cached sync")

print("Companion sync cache PASS state_key=true roster_key=true")
