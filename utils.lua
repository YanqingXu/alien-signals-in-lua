--[[
 * Utils Module - Testing utilities for the reactive system
 * 工具模块 - 响应式系统的测试工具
 *
 * This module provides testing utilities for the reactive system's test files,
 * including test runner and assertion functions for unit testing.
 * 该模块为响应式系统的测试文件提供测试工具，
 * 包括测试运行器和用于单元测试的断言函数。
]]

local utils = {}

--[[
 * Simple test runner utility
 * 简单的测试运行器工具
 *
 * @param name: Test name to display / 要显示的测试名称
 * @param fn: Test function to execute / 要执行的测试函数
 *
 * This provides a basic testing framework for the reactive system's test files.
 * It simply prints the test name and executes the test function.
 * 这为响应式系统的测试文件提供了基本的测试框架。
 * 它简单地打印测试名称并执行测试函数。
]]
function utils.test(name, fn)
    print(name)
    fn()
end

--[[
 * Create an expectation object for testing assertions
 * 创建用于测试断言的期望对象
 *
 * @param actual: The actual value to test / 要测试的实际值
 * @return: Expectation object with assertion methods / 带有断言方法的期望对象
 *
 * This provides a Jest-like testing API for the reactive system's tests.
 * It supports basic equality assertions for both primitive values and objects.
 * The returned object has methods like toBe() and toEqual() for different types of comparisons.
 *
 * 这为响应式系统的测试提供了类似 Jest 的测试 API。
 * 它支持原始值和对象的基本相等断言。
 * 返回的对象具有 toBe() 和 toEqual() 等方法用于不同类型的比较。
]]
function utils.expect(actual)
    return {
        -- Strict equality assertion (===)
        -- 严格相等断言 (===)
        toBe = function(expected)
            assert(actual == expected)
        end,

        -- Deep equality assertion for objects and primitive values
        -- 对象和原始值的深度相等断言
        toEqual = function(expected)
            if type(actual) == "table" and type(expected) == "table" then
                for k, v in pairs(expected) do
                    assert(actual[k] == v)
                end
            else
                assert(actual == expected)
            end
        end,
    }
end

return utils