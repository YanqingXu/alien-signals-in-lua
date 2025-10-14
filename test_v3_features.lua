-- test_v3_features.lua
-- Test new features in version 3.0.0

print("========== Testing v3.0.0 New Features ==========\n")

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local effectScope = reactive.effectScope
local getBatchDepth = reactive.getBatchDepth
local getActiveSub = reactive.getActiveSub
local isSignal = reactive.isSignal
local isComputed = reactive.isComputed
local isEffect = reactive.isEffect
local isEffectScope = reactive.isEffectScope

local utils = require("utils")
local test = utils.test
local expect = utils.expect

-- Test 1: Type checking functions
test('isSignal, isComputed, isEffect, isEffectScope should work correctly', function()
    local sig = signal(1)
    local comp = computed(function() return sig() * 2 end)
    local eff = effect(function() sig() end)
    local scope = effectScope(function() end)
    
    expect(isSignal(sig)).toBe(true)
    expect(isSignal(comp)).toBe(false)
    
    expect(isComputed(comp)).toBe(true)
    expect(isComputed(sig)).toBe(false)
    
    expect(isEffect(eff)).toBe(true)
    expect(isEffect(sig)).toBe(false)
    
    expect(isEffectScope(scope)).toBe(true)
    expect(isEffectScope(eff)).toBe(false)
    
    print("test passed\n")
end)

-- Test 2: getBatchDepth function
test('getBatchDepth should track batch depth correctly', function()
    expect(getBatchDepth()).toBe(0)
    
    reactive.startBatch()
    expect(getBatchDepth()).toBe(1)
    
    reactive.startBatch()
    expect(getBatchDepth()).toBe(2)
    
    reactive.endBatch()
    expect(getBatchDepth()).toBe(1)
    
    reactive.endBatch()
    expect(getBatchDepth()).toBe(0)
    
    print("test passed\n")
end)

-- Test 3: getActiveSub function
test('getActiveSub should return current active subscriber', function()
    expect(getActiveSub() == nil).toBe(true)
    
    local sig = signal(1)
    local activeSub = nil
    
    effect(function()
        sig()
        activeSub = getActiveSub()
    end)
    
    expect(activeSub ~= nil).toBe(true)
    expect(getActiveSub() == nil).toBe(true)
    
    print("test passed\n")
end)

-- Test 4: Computed fast path (first access)
test('computed should use fast path on first access', function()
    local callCount = 0
    local sig = signal(1)
    
    local comp = computed(function()
        callCount = callCount + 1
        return sig() * 2
    end)
    
    expect(callCount).toBe(0) -- Not called yet
    
    local value = comp() -- First access triggers fast path
    expect(callCount).toBe(1)
    expect(value).toBe(2)
    
    -- Second access should not recalculate
    value = comp()
    expect(callCount).toBe(1)
    expect(value).toBe(2)
    
    -- After signal changes, should recalculate
    sig(2)
    value = comp()
    expect(callCount).toBe(2)
    expect(value).toBe(4)
    
    print("test passed\n")
end)

-- Test 5: Effect scope parent-child relationship
test('effect scope should establish parent-child hierarchy', function()
    local innerEffectRan = false
    local outerEffectRan = false
    
    local sig = signal(1)
    
    local stopScope = effectScope(function()
        effect(function()
            outerEffectRan = true
            sig()
        end)
        
        effect(function()
            innerEffectRan = true
            sig()
        end)
    end)
    
    expect(outerEffectRan).toBe(true)
    expect(innerEffectRan).toBe(true)
    
    -- Reset flags
    outerEffectRan = false
    innerEffectRan = false
    
    -- Trigger effects
    sig(2)
    expect(outerEffectRan).toBe(true)
    expect(innerEffectRan).toBe(true)
    
    -- Stop scope should stop both effects
    stopScope()
    outerEffectRan = false
    innerEffectRan = false
    
    sig(3)
    expect(outerEffectRan).toBe(false)
    expect(innerEffectRan).toBe(false)
    
    print("test passed\n")
end)

print("========== All v3.0.0 Feature Tests Passed! ==========\n")
