--[[
 * Test for issue #48 regression
 * 测试问题 #48 的回归测试
 *
 * This test verifies a specific edge case where disposing an inner effect
 * created within a reaction should not cause issues.
 * 此测试验证一个特定的边缘情况，即在反应中创建的内部副作用被释放时不应导致问题。
]]

print("========== Issue #48 Regression Test ==========\n")

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local setActiveSub = reactive.setActiveSub

local utils = require("utils")
local test = utils.test
local expect = utils.expect

--[[
 * Helper function: untracked
 * 辅助函数：不追踪
 *
 * Executes a callback without tracking dependencies
 * 执行回调而不追踪依赖
]]
local function untracked(callback)
    local currentSub = setActiveSub(nil)
    local success, result = pcall(callback)
    setActiveSub(currentSub)
    if not success then
        error(result)
    end
    return result
end

--[[
 * Helper function: reaction
 * 辅助函数：反应
 *
 * Creates a reaction that watches a data function and executes an effect function
 * 创建一个反应，监视数据函数并执行副作用函数
]]
local function reaction(dataFn, effectFn, options)
    options = options or {}
    local scheduler = options.scheduler or function(fn) fn() end
    local equals = options.equals or function(a, b) return a == b end
    local onError = options.onError
    local once = options.once or false
    local fireImmediately = options.fireImmediately or false

    local prevValue
    local version = 0

    local tracked = computed(function()
        local success, result = pcall(dataFn)
        if not success then
            untracked(function()
                if onError then onError(result) end
            end)
            return prevValue
        end
        return result
    end)

    local dispose = nil
    dispose = effect(function()
        local current = tracked()
        if not fireImmediately and version == 0 then
            prevValue = current
        end
        version = version + 1
        if equals(current, prevValue) then return end
        local oldValue = prevValue
        prevValue = current
        untracked(function()
            scheduler(function()
                local success, err = pcall(function()
                    effectFn(current, oldValue)
                end)
                if not success then
                    if onError then onError(err) end
                end
                if once then
                    if fireImmediately and version > 1 then
                        dispose()
                    elseif not fireImmediately and version > 0 then
                        dispose()
                    end
                end
            end)
        end)
    end)

    return dispose
end

test('#48 - disposing inner effect in reaction should not cause issues', function()
    local source = signal(0)
    local disposeInner

    reaction(
        function() return source() end,
        function(val)
            if val == 1 then
                disposeInner = reaction(
                    function() return source() end,
                    function() end
                )
            elseif val == 2 then
                disposeInner()
            end
        end
    )

    -- This sequence should not cause any errors
    -- 这个序列不应导致任何错误
    source(1)
    source(2)
    source(3)

    print("test passed\n")
end)

print("========== Issue #48 Test Passed ==========\n")
print("====================================================\n")

