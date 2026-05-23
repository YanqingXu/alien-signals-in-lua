-- test_refactored_tracing.lua
-- Runtime tracing checks for the refactored implementation.
print("========== Refactored Runtime Tracing Tests ==========\n")

local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = package.loaded["alien_signals"] or require("refactored")
local tracer = require("refactored.tracer")

local function hasEvent(events, eventName)
    for _, event in ipairs(events) do
        if event.name == eventName then
            return true
        end
    end
    return false
end

local function findEvent(events, eventName)
    for _, event in ipairs(events) do
        if event.name == eventName then
            return event
        end
    end
    return nil
end

test("runtime tracing captures the signal-to-effect flow", function()
    tracer.reset()
    expect(reactive.tracer).toBe(tracer)

    local events = {}
    reactive.setTraceHandler(function(event)
        events[#events + 1] = event
    end)

    local source = reactive.signal(0)
    local observed
    local stopEffect = reactive.effect(function()
        observed = source()
    end)

    source(1)
    stopEffect()
    reactive.clearTraceHandler()

    expect(observed).toBe(1)
    expect(#events > 0).toBe(true)
    expect(hasEvent(events, "signal:set")).toBe(true)
    expect(hasEvent(events, "propagate:start")).toBe(true)
    expect(hasEvent(events, "effect:enqueue")).toBe(true)
    expect(hasEvent(events, "flush:start")).toBe(true)
    expect(hasEvent(events, "check:start")).toBe(true)
    expect(hasEvent(events, "effect:run:start")).toBe(true)

    local signalSet = findEvent(events, "signal:set")
    expect(signalSet.nodeType).toBe("signal")
    expect(type(tracer.formatEvent(signalSet))).toBe("string")

    print("test passed\n")
end)

test("tracer handler errors disable tracing without breaking updates", function()
    tracer.reset()
    tracer.setHandler(function()
        error("trace handler failure")
    end)

    local source = reactive.signal(0)
    source(1)

    expect(tracer.isEnabled()).toBe(false)
    expect(tracer.getLastError() ~= nil).toBe(true)
    tracer.clearHandler()

    print("test passed\n")
end)

print("========== Refactored Runtime Tracing Tests Complete ==========\n")
