--[[
 * Tests for recursion prevention in effects and computed values
 * 副作用和计算值的递归防止测试
 *
 * These tests verify the recursion prevention mechanism added in v3.1.0
 * 这些测试验证 v3.1.0 中添加的递归防止机制
]]

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect

-- Test helper function
-- 测试辅助函数
local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

print("Running recursion prevention tests...")
print("运行递归防止测试...")

--[[
 * Test 1: Effect should not trigger itself during first run
 * 测试 1：副作用在首次运行时不应触发自身
]]
print("\nTest 1: Effect should not trigger itself during first run")
print("测试 1：副作用在首次运行时不应触发自身")
do
    local s = signal(0)
    local runCount = 0
    
    effect(function()
        runCount = runCount + 1
        local val = s()
        -- This would cause recursion without RecursedCheck
        -- 如果没有 RecursedCheck，这会导致递归
        if runCount == 1 then
            s(val + 1)
        end
    end)
    
    -- Effect should run only once during initialization
    -- 副作用在初始化期间应该只运行一次
    assertEquals(runCount, 1, "Effect should run once during initialization")
    assertEquals(s(), 1, "Signal should be updated to 1")
    
    print("✓ Test 1 passed")
    print("✓ 测试 1 通过")
end

--[[
 * Test 2: Computed should not trigger itself during first run
 * 测试 2：计算值在首次运行时不应触发自身
]]
print("\nTest 2: Computed should not trigger itself during first run")
print("测试 2：计算值在首次运行时不应触发自身")
do
    local s = signal(0)
    local computeCount = 0
    
    local c = computed(function()
        computeCount = computeCount + 1
        local val = s()
        -- This would cause recursion without RecursedCheck
        -- 如果没有 RecursedCheck，这会导致递归
        if computeCount == 1 then
            s(val + 1)
        end
        return val
    end)
    
    -- Access computed to trigger first run
    -- 访问计算值以触发首次运行
    local result = c()
    
    assertEquals(computeCount, 1, "Computed should run once during initialization")
    assertEquals(result, 0, "Computed should return initial value")
    assertEquals(s(), 1, "Signal should be updated to 1")
    
    print("✓ Test 2 passed")
    print("✓ 测试 2 通过")
end

--[[
 * Test 3: Effect does not trigger itself during execution (even after first run)
 * 测试 3：副作用在执行期间不会触发自身（即使在首次运行后）
]]
print("\nTest 3: Effect does not trigger itself during execution")
print("测试 3：副作用在执行期间不会触发自身")
do
    local s = signal(0)
    local runCount = 0

    effect(function()
        runCount = runCount + 1
        local val = s()
        -- Even after first run, modifying the signal during execution
        -- will not trigger the effect again (RecursedCheck prevents it)
        -- 即使在首次运行后，在执行期间修改信号也不会再次触发副作用
        if runCount == 2 then
            s(val + 1)
        end
    end)

    assertEquals(runCount, 1, "Effect should run once initially")

    -- Trigger the effect
    -- 触发副作用
    s(1)

    -- Effect should run twice: once for s(1), and the s(val+1) inside
    -- does not trigger it again because RecursedCheck is set
    -- 副作用应该运行两次：一次为 s(1)，内部的 s(val+1) 不会再次触发它
    assertEquals(runCount, 2, "Effect should run twice total")
    assertEquals(s(), 2, "Signal should be 2")

    print("✓ Test 3 passed")
    print("✓ 测试 3 通过")
end

--[[
 * Test 4: Nested effects should not cause recursion during initialization
 * 测试 4：嵌套副作用在初始化期间不应导致递归
]]
print("\nTest 4: Nested effects should not cause recursion during initialization")
print("测试 4：嵌套副作用在初始化期间不应导致递归")
do
    local s1 = signal(0)
    local s2 = signal(0)
    local runCount1 = 0
    local runCount2 = 0
    
    effect(function()
        runCount1 = runCount1 + 1
        local val = s1()
        
        effect(function()
            runCount2 = runCount2 + 1
            s2()
            if runCount2 == 1 then
                s1(val + 1)
            end
        end)
    end)
    
    -- Both effects should run once during initialization
    -- 两个副作用在初始化期间都应该只运行一次
    assertEquals(runCount1, 1, "Outer effect should run once")
    assertEquals(runCount2, 1, "Inner effect should run once")
    assertEquals(s1(), 1, "s1 should be updated to 1")
    
    print("✓ Test 4 passed")
    print("✓ 测试 4 通过")
end

--[[
 * Test 5: Multiple signals in effect should not cause recursion
 * 测试 5：副作用中的多个信号不应导致递归
]]
print("\nTest 5: Multiple signals in effect should not cause recursion")
print("测试 5：副作用中的多个信号不应导致递归")
do
    local s1 = signal(0)
    local s2 = signal(0)
    local runCount = 0
    
    effect(function()
        runCount = runCount + 1
        local val1 = s1()
        local val2 = s2()
        
        if runCount == 1 then
            s1(val1 + 1)
            s2(val2 + 1)
        end
    end)
    
    assertEquals(runCount, 1, "Effect should run once during initialization")
    assertEquals(s1(), 1, "s1 should be 1")
    assertEquals(s2(), 1, "s2 should be 1")
    
    print("✓ Test 5 passed")
    print("✓ 测试 5 通过")
end

print("\n" .. string.rep("=", 50))
print("All recursion prevention tests passed!")
print("所有递归防止测试通过！")
print(string.rep("=", 50))

