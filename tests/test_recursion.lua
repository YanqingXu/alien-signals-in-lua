-- test_recursion.lua
-- Tests for recursion prevention in effects and computed values
-- 副作用和计算值的递归防止测试
print("========== Reactive System Recursion Prevention Tests ==========\n")

-- Load reactive system
local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect

test('should not trigger effect itself during first run', function()
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
    expect(runCount).toBe(1)
    expect(s()).toBe(1)

    print("test passed\n")
end)

test('should not trigger computed itself during first run', function()
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

    expect(computeCount).toBe(1)
    expect(result).toBe(0)
    expect(s()).toBe(1)

    print("test passed\n")
end)

test('should not trigger effect itself during execution even after first run', function()
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

    expect(runCount).toBe(1)

    -- Trigger the effect
    -- 触发副作用
    s(1)

    -- Effect should run twice: once for s(1), and the s(val+1) inside
    -- does not trigger it again because RecursedCheck is set
    -- 副作用应该运行两次：一次为 s(1)，内部的 s(val+1) 不会再次触发它
    expect(runCount).toBe(2)
    expect(s()).toBe(2)

    print("test passed\n")
end)

test('should not cause recursion with nested effects during initialization', function()
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
    expect(runCount1).toBe(1)
    expect(runCount2).toBe(1)
    expect(s1()).toBe(1)

    print("test passed\n")
end)

test('should not cause recursion with multiple signals in effect', function()
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

    expect(runCount).toBe(1)
    expect(s1()).toBe(1)
    expect(s2()).toBe(1)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")

