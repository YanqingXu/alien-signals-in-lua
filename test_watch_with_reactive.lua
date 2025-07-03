--[[
Test: HybridReactive.watch() function with reactive objects
测试：HybridReactive.watch() 函数与响应式对象的交互

This test explores how HybridReactive.watch() (which is reactive.effect) 
works with reactive objects, compared to watchReactive().

该测试探索 HybridReactive.watch()（即 reactive.effect）
如何与响应式对象工作，以及与 watchReactive() 的对比。
]]

local utils = require('utils')
local HybridReactive = require('HybridReactive')
local test = utils.test
local expect = utils.expect

print("========== HybridReactive.watch() with Reactive Objects Test ==========\n")

-- Test 1: Basic watch vs watchReactive behavior
test('Basic watch vs watchReactive behavior', function()
    local watchChanges = {}
    local watchReactiveChanges = {}

    -- Create reactive object
    local obj = HybridReactive.reactive({
        name = "Alice",
        age = 25,
        profile = {
            email = "alice@example.com",
            settings = {
                theme = "dark"
            }
        }
    }, false)  -- deep reactive

    -- Using HybridReactive.watch (which is reactive.effect)
    local stopWatch = HybridReactive.watch(function()
        -- Access properties to establish dependencies
        local name = obj.name
        local age = obj.age
        local email = obj.profile.email
        local theme = obj.profile.settings.theme

        table.insert(watchChanges, {
            name = name,
            age = age,
            email = email,
            theme = theme,
            timestamp = os.clock()
        })
    end)

    -- Using HybridReactive.watchReactive
    local stopWatchReactive = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(watchReactiveChanges, {
            key = key,
            path = path,
            newValue = newValue,
            oldValue = oldValue
        })
    end, false)  -- deep watch

    print("Initial state:")
    print("watch() changes:", #watchChanges)
    print("watchReactive() changes:", #watchReactiveChanges)

    -- Make changes
    obj.name = "Bob"
    obj.age = 30
    obj.profile.email = "bob@example.com"
    obj.profile.settings.theme = "light"

    print("\nAfter changes:")
    print("watch() changes:", #watchChanges)
    print("watchReactive() changes:", #watchReactiveChanges)

    print("\nwatch() captured states:")
    for i, change in ipairs(watchChanges) do
        print(string.format("  %d. name=%s, age=%s, email=%s, theme=%s", 
              i, change.name, change.age, change.email, change.theme))
    end

    print("\nwatchReactive() captured changes:")
    for i, change in ipairs(watchReactiveChanges) do
        print(string.format("  %d. %s at %s: %s -> %s", 
              i, change.key, change.path, tostring(change.oldValue), tostring(change.newValue)))
    end

    -- watch() should capture the complete state each time any dependency changes
    -- watchReactive() should capture individual property changes
    expect(#watchChanges >= 4).toBe(true)  -- Initial + 4 changes
    expect(#watchReactiveChanges).toBe(4)  -- 4 individual property changes

    stopWatch()
    stopWatchReactive()
    print("[OK] Basic watch vs watchReactive behavior test passed")
end)

-- Test 2: Selective dependency tracking with watch()
test('Selective dependency tracking with watch()', function()
    local watchChanges = {}

    local obj = HybridReactive.reactive({
        watched = "initial",
        unwatched = "initial",
        nested = {
            watched = "nested initial",
            unwatched = "nested initial"
        }
    }, false)

    -- watch() only tracks dependencies that are actually accessed
    local stopWatch = HybridReactive.watch(function()
        -- Only access specific properties
        local watched = obj.watched
        local nestedWatched = obj.nested.watched
        -- Note: obj.unwatched and obj.nested.unwatched are NOT accessed

        table.insert(watchChanges, {
            watched = watched,
            nestedWatched = nestedWatched,
            changeCount = #watchChanges + 1
        })
    end)

    print("Testing selective dependency tracking:")

    -- Change watched properties (should trigger)
    obj.watched = "changed"
    obj.nested.watched = "nested changed"

    -- Change unwatched properties (should NOT trigger)
    obj.unwatched = "this should not trigger"
    obj.nested.unwatched = "this should also not trigger"

    print("Changes captured by selective watch():", #watchChanges)
    for i, change in ipairs(watchChanges) do
        print(string.format("  %d. watched=%s, nestedWatched=%s", 
              i, change.watched, change.nestedWatched))
    end

    -- Should only capture changes to accessed properties
    expect(#watchChanges).toBe(3)  -- Initial + 2 watched changes

    stopWatch()
    print("[OK] Selective dependency tracking test passed")
end)

-- Test 3: Performance comparison - watch vs watchReactive
test('Performance comparison: watch vs watchReactive', function()
    local watchCount = 0
    local watchReactiveCount = 0

    local obj = HybridReactive.reactive({
        a = 1, b = 2, c = 3, d = 4, e = 5,
        nested = {
            x = 10, y = 20, z = 30
        }
    }, false)

    -- watch() - only tracks accessed properties
    local stopWatch = HybridReactive.watch(function()
        -- Only access a few properties
        local sum = obj.a + obj.nested.x
        watchCount = watchCount + 1
    end)

    -- watchReactive() - tracks all properties
    local stopWatchReactive = HybridReactive.watchReactive(obj, function()
        watchReactiveCount = watchReactiveCount + 1
    end, false)

    print("Performance test - modifying various properties:")

    -- Modify tracked properties
    obj.a = 10      -- Both should trigger
    obj.nested.x = 100  -- Both should trigger

    -- Modify untracked properties (by watch)
    obj.b = 20      -- Only watchReactive should trigger
    obj.c = 30      -- Only watchReactive should trigger
    obj.nested.y = 200  -- Only watchReactive should trigger
    obj.nested.z = 300  -- Only watchReactive should trigger

    print("watch() triggers:", watchCount)
    print("watchReactive() triggers:", watchReactiveCount)

    -- watch() should trigger less (only for accessed properties)
    expect(watchCount).toBe(3)  -- Initial + 2 tracked changes
    expect(watchReactiveCount).toBe(6)  -- All 6 changes

    stopWatch()
    stopWatchReactive()
    print("[OK] Performance comparison test passed")
end)

-- Test 4: Complex dependency patterns with watch()
test('Complex dependency patterns with watch()', function()
    local computationResults = {}

    local obj = HybridReactive.reactive({
        base = 10,
        multiplier = 2,
        config = {
            enabled = true,
            factor = 3
        }
    }, false)

    -- Complex computation that depends on multiple properties
    local stopWatch = HybridReactive.watch(function()
        local result
        if obj.config.enabled then
            result = obj.base * obj.multiplier * obj.config.factor
        else
            result = obj.base
        end

        table.insert(computationResults, {
            result = result,
            base = obj.base,
            multiplier = obj.multiplier,
            enabled = obj.config.enabled,
            factor = obj.config.factor
        })
    end)

    print("Complex dependency tracking:")

    -- Test various changes
    obj.base = 20           -- Should trigger
    obj.multiplier = 3      -- Should trigger
    obj.config.factor = 4   -- Should trigger
    obj.config.enabled = false  -- Should trigger (changes computation logic)
    obj.base = 30           -- Should trigger (even though logic is simpler now)
    obj.multiplier = 5      -- Should NOT trigger (not used when enabled = false)

    print("Computation results:")
    for i, result in ipairs(computationResults) do
        print(string.format("  %d. result=%d (base=%d, mult=%d, enabled=%s, factor=%d)", 
              i, result.result, result.base, result.multiplier, 
              tostring(result.enabled), result.factor))
    end

    -- Should capture all relevant changes
    expect(#computationResults >= 5).toBe(true)

    stopWatch()
    print("[OK] Complex dependency patterns test passed")
end)

-- Test 5: watch() with shallow vs deep reactive objects
test('watch() with shallow vs deep reactive objects', function()
    local shallowChanges = {}
    local deepChanges = {}

    -- Shallow reactive object
    local shallowObj = HybridReactive.reactive({
        data = { value = 10, nested = { count = 5 } }
    }, true)  -- shallow

    -- Deep reactive object
    local deepObj = HybridReactive.reactive({
        data = { value = 10, nested = { count = 5 } }
    }, false)  -- deep

    -- watch() on shallow reactive
    local stopShallowWatch = HybridReactive.watch(function()
        -- Try to access nested properties
        local value = shallowObj.data.value
        local count = shallowObj.data.nested.count
        table.insert(shallowChanges, { value = value, count = count })
    end)

    -- watch() on deep reactive
    local stopDeepWatch = HybridReactive.watch(function()
        local value = deepObj.data.value
        local count = deepObj.data.nested.count
        table.insert(deepChanges, { value = value, count = count })
    end)

    print("Reactivity check:")
    print("shallowObj.data is reactive:", HybridReactive.isReactive(shallowObj.data))
    print("deepObj.data is reactive:", HybridReactive.isReactive(deepObj.data))

    -- Modify nested properties
    shallowObj.data.value = 20      -- Won't trigger (data is not reactive)
    shallowObj.data.nested.count = 10  -- Won't trigger (nested is not reactive)

    deepObj.data.value = 20         -- Will trigger (data is reactive)
    deepObj.data.nested.count = 10  -- Will trigger (nested is reactive)

    print("Shallow reactive + watch() changes:", #shallowChanges)
    print("Deep reactive + watch() changes:", #deepChanges)

    -- Only deep reactive should trigger nested changes
    expect(#shallowChanges).toBe(1)  -- Only initial
    expect(#deepChanges).toBe(3)     -- Initial + 2 changes

    stopShallowWatch()
    stopDeepWatch()
    print("[OK] watch() with shallow vs deep reactive test passed")
end)

print("\n========== Test Summary ==========")
print("Key findings about HybridReactive.watch() with reactive objects:")
print("1. watch() is an alias for reactive.effect() - tracks dependencies automatically")
print("2. watch() only tracks properties that are ACTUALLY ACCESSED in the effect function")
print("3. watch() captures complete state snapshots vs watchReactive() captures individual changes")
print("4. watch() can be more efficient for complex computations (selective dependency tracking)")
print("5. watch() behavior is limited by the reactive structure (shallow vs deep)")
print("6. watch() provides fine-grained control over what dependencies to track")
print("7. watchReactive() is specialized for monitoring all property changes")
print("8. Choose watch() for computed-like behavior, watchReactive() for change monitoring")
