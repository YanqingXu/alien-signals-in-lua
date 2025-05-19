-- test_computed.lua
-- Test for Lua implementation of reactive system - focusing on effect functionality
print("========== Reactive System Computed Tests ==========\n")

-- Load reactive system
require("bit")
require("global")
require("utils")
local computedModule = require("computed")
local signalModule = require("signal")

-- Get APIs
local signal = signalModule.signal
local computed = computedModule.computed

local test = utils.test
local expect = utils.expect

test('should correctly propagate changes through computed signals', function ()
    local src = signal(0)
    local c1 = computed(function() return src() % 2 end)
    local c2 = computed(function() return c1() end)
    local c3 = computed(function() return c2() end)

    c3()
    src(1) -- c1 -> dirty, c2 -> toCheckDirty, c3 -> toCheckDirty
    c2() -- c1 -> none, c2 -> none
    src(3) -- c1 -> dirty, c2 -> toCheckDirty

    expect(c3()).toBe(1)
    print("test passed\n")
end)

test('should propagate updated source value through chained computations', function ()
    local src = signal(0)
    local a = computed(function() return src() end)
    local b = computed(function() return a() % 2 end)
    local c = computed(function() return src() end)
    local d = computed(function() return b() + c() end)

    expect(d()).toBe(0)
    src(2)
    expect(d()).toBe(2)
    print("test passed\n")
end)

test('should handle flags are indirectly updated during checkDirty', function ()
    local a = signal(false)
    local b = computed(function() return a() end)
    local c = computed(function()
        b()
        return 0
    end)
    local d = computed(function()
        c()
        return b()
    end)

    expect(d()).toBe(false)
    a(true)
    expect(d()).toBe(true)
    print("test passed\n")
end)

test('should not update if the signal value is reverted', function ()
    local times = 0

    local src = signal(0)
    local c1 = computed(function()
        times = times + 1
        return src()
    end)
    c1()
    expect(times).toBe(1)
    src(1)
    src(0)
    c1()
    expect(times).toBe(1)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")