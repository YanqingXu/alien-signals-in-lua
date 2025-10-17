-- test_untrack.lua
-- Test for Lua implementation of reactive system - focusing on untrack functionality
print("========== Reactive System Untrack Tests ==========\n")

-- Load reactive system
local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local effectScope = reactive.effectScope
local setActiveSub = reactive.setActiveSub

local utils = require("utils")
local test = utils.test
local expect = utils.expect

test('should pause tracking in computed', function()
    local src = signal(0)

    local computedTriggerTimes = 0
    local c = computed(function()
        computedTriggerTimes = computedTriggerTimes + 1
        local currentSub = setActiveSub(nil)
        local value = src()
        setActiveSub(currentSub)
        return value
    end)

    expect(c()).toBe(0)
    expect(computedTriggerTimes).toBe(1)

    src(1)
    src(2)
    src(3)
    expect(c()).toBe(0)
    expect(computedTriggerTimes).toBe(1)
    print("test passed\n")
end)

test('should pause tracking in effect', function()
    local src = signal(0)
    local is = signal(0)

    local effectTriggerTimes = 0
    effect(function()
        effectTriggerTimes = effectTriggerTimes + 1
        if is() ~= 0 then
            local currentSub = setActiveSub(nil)
            src()
            setActiveSub(currentSub)
        end
    end)

    expect(effectTriggerTimes).toBe(1)

    is(1)
    expect(effectTriggerTimes).toBe(2)

    src(1)
    src(2)
    src(3)
    expect(effectTriggerTimes).toBe(2)

    is(2)
    expect(effectTriggerTimes).toBe(3)

    src(4)
    src(5)
    src(6)
    expect(effectTriggerTimes).toBe(3)

    is(0)
    expect(effectTriggerTimes).toBe(4)

    src(7)
    src(8)
    src(9)
    expect(effectTriggerTimes).toBe(4)
    print("test passed\n")
end)

test('should pause tracking in effect scope', function()
    local src = signal(0)

    local effectTriggerTimes = 0
    effectScope(function()
        effect(function()
            effectTriggerTimes = effectTriggerTimes + 1
            local currentSub = setActiveSub(nil)
            src()
            setActiveSub(currentSub)
        end)
    end)

    expect(effectTriggerTimes).toBe(1)

    src(1)
    src(2)
    src(3)
    expect(effectTriggerTimes).toBe(1)
    print("test passed\n")
end)

print("========== All Untrack Tests Completed ==========\n")
