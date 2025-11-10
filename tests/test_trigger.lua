-- test_trigger.lua
-- Test for Lua implementation of reactive system - focusing on trigger functionality
print("========== Reactive System Trigger Tests ==========\n")

-- Load reactive system
local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local trigger = reactive.trigger

test('should not throw when triggering with no dependencies', function()
    local success = pcall(function()
        trigger(function() end)
    end)
    expect(success).toBe(true)
    print("test passed\n")
end)

test('should trigger updates for dependent computed signals', function()
    local arr = signal({})
    local length = computed(function()
        local a = arr()
        return #a
    end)

    expect(length()).toBe(0)

    table.insert(arr(), 1)
    expect(length()).toBe(0)

    trigger(arr)
    expect(length()).toBe(1)

    print("test passed\n")
end)

test('should trigger updates for the second source signal', function()
    local src1 = signal({})
    local src2 = signal({})
    local length = computed(function()
        return #src2()
    end)

    expect(length()).toBe(0)

    table.insert(src2(), 1)

    trigger(function()
        src1()
        src2()
    end)

    expect(length()).toBe(1)

    print("test passed\n")
end)

test('should trigger effect once', function()
    local src1 = signal({})
    local src2 = signal({})

    local triggers = 0

    effect(function()
        triggers = triggers + 1
        src1()
        src2()
    end)

    expect(triggers).toBe(1)

    trigger(function()
        src1()
        src2()
    end)

    expect(triggers).toBe(2)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")

