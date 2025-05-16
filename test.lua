-- test_effect.lua
-- Test for Lua implementation of reactive system - focusing on effect functionality
print("========== Reactive System Effect Tests ==========\n")

-- Load reactive system
require("bit")
require("global")
local effectModule = require("effect")
local computedModule = require("computed")
local signalModule = require("signal")

-- Get APIs
local signal = signalModule.signal
local computed = computedModule.computed
local effect = effectModule.effect

local test = function(name, fn)
        print(name)
        fn()
    end

local expect = function(actual)
    return {
        toBe = function(expected)
            assert(actual == expected)
        end
    }
end

test('should clear subscriptions when untracked by all subscribers', function ()
    local bRunTimes = 0

    local a = signal(1)
    local b = computed(function()
        bRunTimes = bRunTimes + 1
        return a() * 2
    end)

    local stopEffect = effect(function()
        b()
    end)
    expect(bRunTimes).toBe(1)
    a(2)
    expect(bRunTimes).toBe(2)
    stopEffect()
    a(3)
    expect(bRunTimes).toBe(2)
    print("test passed\n")
end)

test('should not run untracked inner effect', function ()
    local a = signal(3)
    local b = computed(function()
        return a() > 0
    end)

    effect(function()
        if b() then
            effect(function()
                if a() == 0 then
                    error("bad")
                end
            end)
        end
    end)

    a(2)
    a(1)
    a(0)
    print("test passed\n")
end)

-- TODO