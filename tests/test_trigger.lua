--[[
 * Tests for trigger() function
 * trigger() 函数的测试
 *
 * These tests verify the manual triggering functionality added in v3.1.0
 * 这些测试验证 v3.1.0 中添加的手动触发功能
]]

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local trigger = reactive.trigger

-- Test helper function
-- 测试辅助函数
local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

print("Running trigger() tests...")
print("运行 trigger() 测试...")

--[[
 * Test 1: Should not throw when triggering with no dependencies
 * 测试 1：在没有依赖时触发不应抛出错误
]]
print("\nTest 1: Should not throw when triggering with no dependencies")
print("测试 1：在没有依赖时触发不应抛出错误")
do
    local success = pcall(function()
        trigger(function() end)
    end)
    assertEquals(success, true, "trigger() should not throw with empty function")
    print("✓ Test 1 passed")
    print("✓ 测试 1 通过")
end

--[[
 * Test 2: Should trigger updates for dependent computed signals
 * 测试 2：应该为依赖的计算信号触发更新
]]
print("\nTest 2: Should trigger updates for dependent computed signals")
print("测试 2：应该为依赖的计算信号触发更新")
do
    local arr = signal({})
    local length = computed(function()
        local a = arr()
        return #a
    end)
    
    assertEquals(length(), 0, "Initial length should be 0")
    
    -- Direct mutation doesn't automatically trigger updates
    -- 直接修改不会自动触发更新
    table.insert(arr(), 1)
    assertEquals(length(), 0, "Length should still be 0 before trigger")
    
    -- Manually trigger updates
    -- 手动触发更新
    trigger(arr)
    assertEquals(length(), 1, "Length should be 1 after trigger")
    
    print("✓ Test 2 passed")
    print("✓ 测试 2 通过")
end

--[[
 * Test 3: Should trigger updates for the second source signal
 * 测试 3：应该为第二个源信号触发更新
]]
print("\nTest 3: Should trigger updates for the second source signal")
print("测试 3：应该为第二个源信号触发更新")
do
    local src1 = signal({})
    local src2 = signal({})
    local length = computed(function()
        return #src2()
    end)
    
    assertEquals(length(), 0, "Initial length should be 0")
    
    table.insert(src2(), 1)
    
    trigger(function()
        src1()
        src2()
    end)
    
    assertEquals(length(), 1, "Length should be 1 after trigger")
    
    print("✓ Test 3 passed")
    print("✓ 测试 3 通过")
end

--[[
 * Test 4: Should trigger effect once
 * 测试 4：应该触发副作用一次
]]
print("\nTest 4: Should trigger effect once")
print("测试 4：应该触发副作用一次")
do
    local src1 = signal({})
    local src2 = signal({})
    
    local triggers = 0
    
    effect(function()
        triggers = triggers + 1
        src1()
        src2()
    end)
    
    assertEquals(triggers, 1, "Effect should run once initially")
    
    trigger(function()
        src1()
        src2()
    end)
    
    assertEquals(triggers, 2, "Effect should run once more after trigger")
    
    print("✓ Test 4 passed")
    print("✓ 测试 4 通过")
end

--[[
 * Test 5: Should work with multiple mutations
 * 测试 5：应该适用于多次修改
]]
print("\nTest 5: Should work with multiple mutations")
print("测试 5：应该适用于多次修改")
do
    local arr = signal({})
    local sum = computed(function()
        local total = 0
        for _, v in ipairs(arr()) do
            total = total + v
        end
        return total
    end)
    
    assertEquals(sum(), 0, "Initial sum should be 0")
    
    -- Multiple mutations
    -- 多次修改
    table.insert(arr(), 1)
    table.insert(arr(), 2)
    table.insert(arr(), 3)
    
    trigger(arr)
    
    assertEquals(sum(), 6, "Sum should be 6 after trigger")
    
    print("✓ Test 5 passed")
    print("✓ 测试 5 通过")
end

--[[
 * Test 6: Should work with nested computed values
 * 测试 6：应该适用于嵌套的计算值
]]
print("\nTest 6: Should work with nested computed values")
print("测试 6：应该适用于嵌套的计算值")
do
    local arr = signal({})
    local length = computed(function()
        return #arr()
    end)
    local doubled = computed(function()
        return length() * 2
    end)
    
    assertEquals(doubled(), 0, "Initial doubled should be 0")
    
    table.insert(arr(), 1)
    table.insert(arr(), 2)
    
    trigger(arr)
    
    assertEquals(doubled(), 4, "Doubled should be 4 after trigger")
    
    print("✓ Test 6 passed")
    print("✓ 测试 6 通过")
end

print("\n" .. string.rep("=", 50))
print("All trigger() tests passed!")
print("所有 trigger() 测试通过！")
print(string.rep("=", 50))

