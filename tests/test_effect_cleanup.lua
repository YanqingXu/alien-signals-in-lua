-- test_effect_cleanup.lua
-- Regression tests for alien-signals 3.2.0 effect cleanup semantics
print("========== Reactive System Effect Cleanup Tests ==========\n")

local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = require("alien_signals")
local signal = reactive.signal
local effect = reactive.effect

test('should run returned cleanup before rerun and on stop', function()
    local source = signal(0)
    local runs = 0
    local cleanups = 0

    local stop = effect(function()
        source()
        runs = runs + 1
        return function()
            cleanups = cleanups + 1
        end
    end)

    expect(runs).toBe(1)
    expect(cleanups).toBe(0)

    source(1)
    expect(runs).toBe(2)
    expect(cleanups).toBe(1)

    stop()
    expect(cleanups).toBe(2)

    source(2)
    expect(runs).toBe(2)
    expect(cleanups).toBe(2)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")
