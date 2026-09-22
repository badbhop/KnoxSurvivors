local rootPath = arg[1] or "."

local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function colors(source)
    local found = {}
    for name, r, g, b in string.gmatch(source,
        "([a-z_]+)%s*=%s*{%s*r%s*=%s*([%d%.]+)%s*,%s*g%s*=%s*([%d%.]+)%s*,%s*b%s*=%s*([%d%.]+)") do
        found[#found + 1] = {
            name = name, r = tonumber(r), g = tonumber(g), b = tonumber(b),
        }
    end
    return found
end

local function distance(a, b)
    local dr, dg, db = a.r - b.r, a.g - b.g, a.b - b.b
    return math.sqrt(dr * dr + dg * dg + db * db)
end

local highlights = read(rootPath .. "/mod/42/media/lua/client/KS_BaseHighlights.lua")
local palette = colors(highlights)
assert(#palette >= 19, "palette must cover territory, work and storage, got " .. #palette)
for i = 1, #palette do
    for j = i + 1, #palette do
        local d = distance(palette[i], palette[j])
        assert(d >= 0.14,
            "zone colors must stay distinguishable: " .. palette[i].name
                .. " vs " .. palette[j].name .. " distance=" .. tostring(d))
    end
end

-- Draft cursor hues must track the placed palette one-to-one.
local selector = read(rootPath .. "/mod/42/media/lua/client/KS_BaseZoneSelector.lua")
for _, work in ipairs({ "guard", "patrol", "cooking", "farming", "woodcutting",
    "log_processing", "corpse", "repair" }) do
    local placed = string.match(highlights, work .. "%s*=%s*{%s*r%s*=%s*([%d%.]+)")
    local draft = string.match(selector, work .. "%s*=%s*{%s*r%s*=%s*([%d%.]+)")
    assert(placed ~= nil and draft ~= nil and tonumber(placed) == tonumber(draft),
        "draft cursor hue must match placed hue for " .. work)
end

print("Zone palette PASS distinct=true draft_matches=true")
