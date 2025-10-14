-- debug_types.lua
-- Debug type detection

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed

local sig = signal(1)

print("Testing isSignal...")
print("sig type:", type(sig))

-- Try to inspect upvalues
local i = 1
while true do
    local name, value = debug.getupvalue(sig, i)
    if not name then break end
    print(string.format("Upvalue %d: name='%s', type=%s", i, name, type(value)))
    if type(value) == "table" then
        for k, v in pairs(value) do
            print(string.format("  %s: %s", tostring(k), tostring(v)))
        end
    end
    i = i + 1
end

local result = reactive.isSignal(sig)
print("isSignal(sig):", result)
