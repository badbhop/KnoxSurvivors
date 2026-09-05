-- Presentation only: runtime IDs never become names and saved identity is untouched.
local Names = {}

local function part(value, id)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    local lower = text:lower()
    if text == tostring(id or "") or lower:match("^ks%-survivor")
        or lower:match("^knox%-survivor") then return "" end
    return text
end

function Names.resolve(id, identity, character)
    identity = type(identity) == "table" and identity or {}
    local first, last = part(identity.forename, id), part(identity.surname, id)
    if character ~= nil and (first == "" or last == "") then
        local ok, descriptor = pcall(function() return character:getDescriptor() end)
        if ok and descriptor ~= nil then
            if first == "" then
                local got, value = pcall(function() return descriptor:getForename() end)
                if got then first = part(value, id) end
            end
            if last == "" then
                local got, value = pcall(function() return descriptor:getSurname() end)
                if got then last = part(value, id) end
            end
        end
    end
    local name = (first .. " " .. last):match("^%s*(.-)%s*$")
    return first, last, name ~= "" and name or "Survivor"
end

return Names
