package.path = "g:/github/alien-signals-in-lua/?.lua;g:/github/alien-signals-in-lua/?/init.lua;" .. package.path

local s = require("refactored")

-- 开启追踪（这是你最强大的学习工具）
s.setTraceHandler(s.tracer.consoleHandler())

local count = s.signal(0, "count")
local doubled = s.computed(function() 
    return count() * 2 
end, "doubled")
local stop = s.effect(function() 
    print("count =", count(), "doubled =", doubled()) 
end, "logger")

print("----------------------  Signal Changed  ----------------------")
count(5)
count(10)