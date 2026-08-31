-- A bounded hint from configured procedural loot weights, not a census of the
-- world or a claim about exact spawn probability. No world/container scanning.
local Availability = {}
_G.KnoxTradeAvailability = Availability
local weights = {}
local MAX_TABLES, MAX_ENTRIES = 10000, 300000

function Availability.refresh()
    weights = {}
    local source = rawget(_G, "ProceduralDistributions")
    source = type(source) == "table" and source.list or nil
    if type(source) ~= "table" then return false end
    local collected, tables, entries = {}, 0, 0
    local function collect(items)
        if type(items) ~= "table" then return true end
        if #items > MAX_ENTRIES * 2 then return false end
        for i = 1, #items - 1, 2 do
            entries = entries + 1
            if entries > MAX_ENTRIES then return false end
            local full, weight = items[i], items[i + 1]
            if type(full) == "string" and #full <= 200 and type(weight) == "number"
                and weight == weight and weight > 0 and weight < math.huge then
                if not full:find(".", 1, true) then full = "Base." .. full end
                collected[full] = math.max(collected[full] or 0, weight)
            end
        end
        return true
    end
    for _, distribution in pairs(source) do
        tables = tables + 1
        if tables > MAX_TABLES then return false end
        if type(distribution) == "table" then
            if not collect(distribution.items) then return false end
            local junk = distribution.junk
            if type(junk) == "table" and not collect(junk.items) then return false end
        end
    end
    weights = collected
    return true
end

function Availability.factor(fullType)
    local weight = weights[fullType]
    return weight ~= nil and (1 + .35 / (1 + weight)) or 1
end

-- SP loads the merged server distributions before OnGameStart. Missing data
-- gets no premium. Keep one stable cache throughout a session, never per quote.
Events.OnGameStart.Add(Availability.refresh)
return Availability
