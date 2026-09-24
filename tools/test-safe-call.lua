local root = arg[1] or "."
local safe = dofile(root .. "/mod/42/media/lua/shared/KS_SafeCall.lua")
local function check(object, name, expected, reason, ...)
    local value, why, method, err = safe.invoke(object, name, ...)
    assert(value == expected and why == reason and method == name,
        tostring(value) .. "/" .. tostring(why) .. "/" .. tostring(method))
    if reason == "lua_error" then assert(err ~= nil) end
end
check(nil, "read", nil, "nil_target")
check({}, "read", nil, "nil_method")
check(setmetatable({}, {__index=function() error("lookup failed") end}), "read", nil, "lua_error")
check({read=function() error("call failed") end}, "read", nil, "lua_error")
check({read=42}, "read", nil, "lua_error")
check({read=function() return false end}, "read", false, nil)
check({read=function() return nil end}, "read", nil, nil)
local receiver = {}
receiver.read = function(self, first, middle, last)
    assert(self == receiver and first == 1 and middle == nil and last == 3)
    return "first", "not-a-reason"
end
check(receiver, "read", "first", nil, 1, nil, 3)
assert(safe.isUsable(nil, function() error("must not run") end, "fallback") == "fallback")
assert(safe.isUsable({}, function() error("predicate failed") end, "fallback") == "fallback")
assert(safe.isUsable({}, function() return nil end, "fallback") == "fallback")
assert(safe.isUsable({}, function() return false end, true) == false)
print("Safe call PASS lookup=true invocation=true false=true nil=true varargs=true contract=true")
