-- test_computed_chain.lua
-- Test for deep computed chain propagation through multiple dependency levels
-- Regression test for: dirty variable scoping bug in processDirtyCheckStep
print("========== Reactive System Computed Chain Tests ==========\n")

-- Load reactive system and test utilities
local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = require("alien_signals")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect

test('should propagate changes through 3-level computed chain', function()
    -- Build a 3-level dependency chain: signals → asSigs → asSigs2 → effect
    -- checkDepth reaches 2 during checkDirty traversal
    local sigs = {}
    for idx = 1, 10 do
        table.insert(sigs, signal(idx))
    end

    local asSigsValues = {}
    local asSigs = computed(function()
        local vs = 0
        for idx = 1, 10 do
            vs = vs + sigs[idx]()
        end
        local midV = vs / 10
        table.insert(asSigsValues, midV)
        return midV
    end)

    local asSigs2Values = {}
    local asSigs2 = computed(function()
        local midV = asSigs()
        table.insert(asSigs2Values, midV)
        return midV * 10
    end)

    local effectValues = {}
    effect(function()
        local v = asSigs2()
        table.insert(effectValues, v)
    end)

    -- Initial values: (1+2+3+4+5+6+7+8+9+10)/10 = 5.5, *10 = 55
    expect(#asSigsValues).toBe(1)
    expect(asSigsValues[1]).toBe(5.5)
    expect(#asSigs2Values).toBe(1)
    expect(asSigs2Values[1]).toBe(5.5)
    expect(#effectValues).toBe(1)
    expect(effectValues[1]).toBe(55)

    -- Update sig[5]: 5 -> 100, average becomes 15
    -- This should propagate through all 3 levels
    sigs[5](100)
    expect(#asSigsValues).toBe(2)
    expect(asSigsValues[2]).toBe(15)
    expect(#asSigs2Values).toBe(2)
    expect(asSigs2Values[2]).toBe(15)
    expect(#effectValues).toBe(2)
    expect(effectValues[2]).toBe(150)

    -- Update sig[6]: 6 -> 123, average becomes 26.7
    -- Each level should execute exactly once more
    sigs[6](123)
    expect(#asSigsValues).toBe(3)
    expect(asSigsValues[3]).toBe(26.7)
    expect(#asSigs2Values).toBe(3)
    expect(asSigs2Values[3]).toBe(26.7)
    expect(#effectValues).toBe(3)
    expect(effectValues[3]).toBe(267)

    print("test passed\n")
end)

test('should not recompute downstream when upstream value unchanged', function()
    local s = signal(10)
    local compValues = {}
    local c = computed(function()
        local v = s()
        table.insert(compValues, v)
        return v * 2
    end)

    local effectRuns = 0
    effect(function()
        effectRuns = effectRuns + 1
        c()
    end)

    -- Initial run
    expect(#compValues).toBe(1)
    expect(effectRuns).toBe(1)

    -- Same value, should not trigger recomputation
    s(10)
    expect(#compValues).toBe(1)
    expect(effectRuns).toBe(1)

    print("test passed\n")
end)

test('should propagate through computed that depends on multiple signals', function()
    local a = signal(1)
    local b = signal(2)
    local cValues = {}
    local c = computed(function()
        local v = a() + b()
        table.insert(cValues, v)
        return v
    end)

    local dValues = {}
    local d = computed(function()
        local v = c() * 10
        table.insert(dValues, v)
        return v
    end)

    local effectValues = {}
    effect(function()
        table.insert(effectValues, d())
    end)

    -- Initial: (1+2)*10 = 30
    expect(#cValues).toBe(1)
    expect(cValues[1]).toBe(3)
    expect(#dValues).toBe(1)
    expect(dValues[1]).toBe(30)
    expect(#effectValues).toBe(1)
    expect(effectValues[1]).toBe(30)

    -- Update a: (5+2)*10 = 70
    a(5)
    expect(#cValues).toBe(2)
    expect(cValues[2]).toBe(7)
    expect(#dValues).toBe(2)
    expect(dValues[2]).toBe(70)
    expect(#effectValues).toBe(2)
    expect(effectValues[2]).toBe(70)

    -- Update b: (5+10)*10 = 150
    b(10)
    expect(#cValues).toBe(3)
    expect(cValues[3]).toBe(15)
    expect(#dValues).toBe(3)
    expect(dValues[3]).toBe(150)
    expect(#effectValues).toBe(3)
    expect(effectValues[3]).toBe(150)

    print("test passed\n")
end)

test('should handle same-value writes at multiple chain levels', function()
    local a = signal(1)
    local b = computed(function() return a() * 2 end)
    local c = computed(function() return b() * 10 end)

    local effectRuns = 0
    effect(function()
        effectRuns = effectRuns + 1
        c()
    end)

    expect(effectRuns).toBe(1)
    expect(c()).toBe(20)

    -- Same value, no propagation
    a(1)
    expect(effectRuns).toBe(1)
    expect(c()).toBe(20)

    -- Different value, full propagation
    a(2)
    expect(effectRuns).toBe(2)
    expect(c()).toBe(40)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
