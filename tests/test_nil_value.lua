-- test_nil_value.lua
-- Test for Lua implementation of reactive system - focusing on nil and falsy values
print("========== Reactive System Nil and Falsy Value Tests ==========\n")

-- Load reactive system
local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect

test('should handle computed when signal value changes to nil', function()
    local s = signal(10)
    local computedCallCount = 0
    local lastComputedValue = "unset"

    local c = computed(function()
        computedCallCount = computedCallCount + 1
        local val = s()
        lastComputedValue = val
        if val == nil then
            return "value is nil"
        else
            return "value is " .. tostring(val)
        end
    end)

    -- 初始计算
    expect(c()).toBe("value is 10")
    expect(computedCallCount).toBe(1)

    -- 将 signal 设为 nil
    s(nil)
    expect(c()).toBe("value is nil")
    expect(lastComputedValue).toBe(nil)
    expect(computedCallCount).toBe(2)

    -- 再次设置为有值
    s(20)
    expect(c()).toBe("value is 20")
    expect(computedCallCount).toBe(3)

    print("test passed\n")
end)

test('should handle computed when signal value changes to false', function()
    local s = signal(10)
    local computedCallCount = 0
    local lastComputedValue = nil

    local c = computed(function()
        computedCallCount = computedCallCount + 1
        local val = s()
        lastComputedValue = val
        if val == false then
            return "value is false"
        else
            return "value is " .. tostring(val)
        end
    end)

    expect(c()).toBe("value is 10")
    expect(computedCallCount).toBe(1)

    s(false)
    expect(c()).toBe("value is false")
    expect(lastComputedValue).toBe(false)
    expect(computedCallCount).toBe(2)

    s(20)
    expect(c()).toBe("value is 20")
    expect(computedCallCount).toBe(3)

    print("test passed\n")
end)

test('should handle effect when signal value changes to nil', function()
    local s = signal(10)
    local effectCallCount = 0
    local capturedValue1, capturedValue2, capturedValue3, capturedValue4

    local dispose = effect(function()
        effectCallCount = effectCallCount + 1
        local val = s()
        if effectCallCount == 1 then
            capturedValue1 = val
        elseif effectCallCount == 2 then
            capturedValue2 = val
        elseif effectCallCount == 3 then
            capturedValue3 = val
        elseif effectCallCount == 4 then
            capturedValue4 = val
        end
    end)

    expect(effectCallCount).toBe(1)
    expect(capturedValue1).toBe(10)

    s(nil)
    expect(effectCallCount).toBe(2)
    expect(capturedValue2).toBe(nil)

    s(30)
    expect(effectCallCount).toBe(3)
    expect(capturedValue3).toBe(30)

    s(nil)
    expect(effectCallCount).toBe(4)
    expect(capturedValue4).toBe(nil)

    dispose()
    print("test passed\n")
end)

test('should handle effect when signal value changes to false', function()
    local s = signal(10)
    local effectCallCount = 0
    local capturedValues = {}

    local dispose = effect(function()
        effectCallCount = effectCallCount + 1
        local val = s()
        table.insert(capturedValues, val)
    end)

    expect(effectCallCount).toBe(1)
    expect(capturedValues[1]).toBe(10)

    s(false)
    expect(effectCallCount).toBe(2)
    expect(capturedValues[2]).toBe(false)

    s(30)
    expect(effectCallCount).toBe(3)
    expect(capturedValues[3]).toBe(30)

    s(false)
    expect(effectCallCount).toBe(4)
    expect(capturedValues[4]).toBe(false)

    dispose()
    print("test passed\n")
end)

test('should handle computed chain when intermediate signal becomes nil', function()
    local s1 = signal(5)
    local s2 = signal(10)

    local c1 = computed(function()
        local val = s1()
        if val == nil then
            return nil
        else
            return val * 2
        end
    end)

    local c2 = computed(function()
        local val1 = c1()
        local val2 = s2()
        if val1 == nil then
            return val2
        else
            return val1 + val2
        end
    end)

    expect(c2()).toBe(20)

    s1(nil)
    expect(c1()).toBe(nil)
    expect(c2()).toBe(10)

    s1(8)
    expect(c1()).toBe(16)
    expect(c2()).toBe(26)

    print("test passed\n")
end)

test('should handle computed chain when intermediate signal becomes 0', function()
    local s1 = signal(5)
    local s2 = signal(10)

    local c1 = computed(function()
        local val = s1()
        return val * 2
    end)

    local c2 = computed(function()
        local val1 = c1()
        local val2 = s2()
        return val1 + val2
    end)

    expect(c2()).toBe(20)

    s1(0)
    expect(c1()).toBe(0)
    expect(c2()).toBe(10)

    s1(8)
    expect(c1()).toBe(16)
    expect(c2()).toBe(26)

    print("test passed\n")
end)

test('should handle effect with multiple signals when one becomes nil', function()
    local s1 = signal(3)
    local s2 = signal(7)
    local result1, result2, result3, result4, result5
    local callCount = 0

    local dispose = effect(function()
        callCount = callCount + 1
        local v1 = s1()
        local v2 = s2()
        local result
        if v1 == nil or v2 == nil then
            result = "has nil"
        else
            result = v1 + v2
        end

        if callCount == 1 then
            result1 = result
        elseif callCount == 2 then
            result2 = result
        elseif callCount == 3 then
            result3 = result
        elseif callCount == 4 then
            result4 = result
        elseif callCount == 5 then
            result5 = result
        end
    end)

    expect(result1).toBe(10)

    s1(nil)
    expect(result2).toBe("has nil")

    s2(nil)
    expect(result3).toBe("has nil")

    s1(4)
    expect(result4).toBe("has nil")

    s2(6)
    expect(result5).toBe(10)

    dispose()
    print("test passed\n")
end)

test('should handle effect with multiple signals when one becomes empty string', function()
    local s1 = signal("hello")
    local s2 = signal("world")
    local effectResults = {}

    local dispose = effect(function()
        local v1 = s1()
        local v2 = s2()
        local result = v1 .. " " .. v2
        table.insert(effectResults, result)
    end)

    expect(effectResults[1]).toBe("hello world")

    s1("")
    expect(effectResults[2]).toBe(" world")

    s2("")
    expect(effectResults[3]).toBe(" ")

    s1("foo")
    expect(effectResults[4]).toBe("foo ")

    s2("bar")
    expect(effectResults[5]).toBe("foo bar")

    dispose()
    print("test passed\n")
end)

test('should handle signal with initial nil value', function()
    local s = signal(nil)
    local computedCallCount = 0

    local c = computed(function()
        computedCallCount = computedCallCount + 1
        local val = s()
        return val == nil and "nil" or tostring(val)
    end)

    expect(c()).toBe("nil")
    expect(computedCallCount).toBe(1)

    s(42)
    expect(c()).toBe("42")
    expect(computedCallCount).toBe(2)

    s(nil)
    expect(c()).toBe("nil")
    expect(computedCallCount).toBe(3)

    print("test passed\n")
end)

test('should handle signal toggling between true and false', function()
    local s = signal(true)
    local computedCallCount = 0

    local c = computed(function()
        computedCallCount = computedCallCount + 1
        local val = s()
        return val and "on" or "off"
    end)

    expect(c()).toBe("on")
    expect(computedCallCount).toBe(1)

    s(false)
    expect(c()).toBe("off")
    expect(computedCallCount).toBe(2)

    s(true)
    expect(c()).toBe("on")
    expect(computedCallCount).toBe(3)

    s(false)
    expect(c()).toBe("off")
    expect(computedCallCount).toBe(4)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================")
