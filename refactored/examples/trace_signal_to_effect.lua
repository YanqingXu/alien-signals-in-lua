--[[
Run with:
  lua refactored/examples/trace_signal_to_effect.lua

This example turns on runtime tracing and then performs one signal update.
The output shows the full PUSH/PULL path from signal write to effect rerun.
]]

local function ensurePackagePath(pattern)
    if not string.find(package.path, pattern, 1, true) then
        package.path = pattern .. ";" .. package.path
    end
end

ensurePackagePath("./?.lua")
ensurePackagePath("./?/init.lua")

local reactive = require("refactored")
local tracer = require("refactored.tracer")

tracer.reset()
tracer.setHandler(tracer.consoleHandler())

local count = reactive.signal(0)
local doubled = reactive.computed(function()
    return count() * 2
end)

local stop = reactive.effect(function()
    doubled()
end)

count(1)
stop()

tracer.clearHandler()
