--[[
Test: Shallow reactive object with deep watchReactive
测试：浅层响应式对象配合深层 watchReactive

This test explores what happens when:
- HybridReactive.reactive() is called with shallow = true
- HybridReactive.watchReactive() is called with shallow = false

该测试探索以下情况：
- HybridReactive.reactive() 使用 shallow = true
- HybridReactive.watchReactive() 使用 shallow = false
]]

local utils = require('utils')
local HybridReactive = require('HybridReactive')
local test = utils.test
local expect = utils.expect

print("========== Shallow Reactive + Deep Watch Test ==========\n")

-- Test 1: Basic behavior - shallow reactive with deep watch
test('Shallow reactive with deep watch - basic behavior', function()
    local changes = {}

    -- Create shallow reactive object
    local obj = HybridReactive.reactive({
        name = "Alice",
        user = {
            profile = {
                age = 25,
                settings = {
                    theme = "dark"
                }
            }
        },
        config = {
            language = "en"
        }
    }, true)  -- shallow = true

    -- Deep watch on shallow reactive object
    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            newValue = newValue,
            oldValue = oldValue,
            newValueIsReactive = HybridReactive.isReactive(newValue)
        })
    end, false)  -- shallow = false (deep watch)

    print("Initial object structure:")
    print("obj.user is reactive:", HybridReactive.isReactive(obj.user))
    print("obj.config is reactive:", HybridReactive.isReactive(obj.config))

    -- Test 1: Modify top-level property (should work)
    obj.name = "Bob"

    -- Test 2: Replace entire nested object (should work)
    obj.user = {
        profile = {
            age = 30,
            settings = {
                theme = "light"
            }
        }
    }

    -- Test 3: Try to modify nested property (should NOT trigger because user is not reactive)
    obj.user.profile.age = 35  -- This won't trigger because obj.user is not reactive

    -- Test 4: Replace config object
    obj.config = { language = "zh", region = "CN" }

    -- Test 5: Try to modify config property (should NOT trigger)
    obj.config.language = "fr"  -- This won't trigger because obj.config is not reactive

    print("\nChanges detected:")
    for i, change in ipairs(changes) do
        print(string.format("%d. Key: %s, Path: %s, NewValue reactive: %s", 
              i, change.key, change.path, tostring(change.newValueIsReactive)))
    end

    -- Expectations:
    -- 1. obj.name change should be detected
    -- 2. obj.user replacement should be detected
    -- 3. obj.user.profile.age change should NOT be detected (user is not reactive)
    -- 4. obj.config replacement should be detected
    -- 5. obj.config.language change should NOT be detected (config is not reactive)

    expect(#changes).toBe(3)  -- Only top-level changes should be detected
    expect(changes[1].key).toBe("name")
    expect(changes[2].key).toBe("user")
    expect(changes[3].key).toBe("config")

    stopWatcher()
    print("[OK] Shallow reactive with deep watch - basic behavior test passed")
end)

-- Test 2: What happens when we assign reactive objects to shallow reactive
test('Assigning reactive objects to shallow reactive', function()
    local changes = {}

    -- Create shallow reactive object
    local shallowObj = HybridReactive.reactive({
        data = { value = 10 }
    }, true)  -- shallow = true

    -- Create a separate deep reactive object
    local deepReactiveData = HybridReactive.reactive({
        nested = {
            count = 5,
            settings = {
                enabled = true
            }
        }
    }, false)  -- deep reactive

    -- Deep watch on shallow reactive object
    local stopWatcher = HybridReactive.watchReactive(shallowObj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            newValueIsReactive = HybridReactive.isReactive(newValue)
        })
    end, false)  -- deep watch

    print("\nBefore assignment:")
    print("shallowObj.data is reactive:", HybridReactive.isReactive(shallowObj.data))
    print("deepReactiveData is reactive:", HybridReactive.isReactive(deepReactiveData))

    -- Assign the deep reactive object to shallow reactive
    shallowObj.data = deepReactiveData

    print("\nAfter assignment:")
    print("shallowObj.data is reactive:", HybridReactive.isReactive(shallowObj.data))
    print("shallowObj.data === deepReactiveData:", shallowObj.data == deepReactiveData)

    -- Now try to modify the nested reactive object
    shallowObj.data.nested.count = 10  -- This SHOULD trigger because data is now reactive
    shallowObj.data.nested.settings.enabled = false  -- This SHOULD also trigger

    print("\nChanges after reactive assignment:")
    for i, change in ipairs(changes) do
        print(string.format("%d. Key: %s, Path: %s, NewValue reactive: %s", 
              i, change.key, change.path, tostring(change.newValueIsReactive)))
    end

    -- The key insight: when we assign a reactive object to a shallow reactive,
    -- the deep watcher can now watch the assigned reactive object
    expect(#changes >= 1).toBe(true)  -- At least the assignment should be detected

    stopWatcher()
    print("[OK] Assigning reactive objects to shallow reactive test passed")
end)

-- Test 3: Comparison with deep reactive + deep watch
test('Comparison: deep reactive vs shallow reactive with deep watch', function()
    local shallowChanges = {}
    local deepChanges = {}

    -- Shallow reactive object
    local shallowObj = HybridReactive.reactive({
        user = { name = "Alice", age = 25 }
    }, true)  -- shallow = true

    -- Deep reactive object
    local deepObj = HybridReactive.reactive({
        user = { name = "Alice", age = 25 }
    }, false)  -- deep = false (default)

    -- Both with deep watch
    local stopShallow = HybridReactive.watchReactive(shallowObj, function(key, newValue, oldValue, path)
        table.insert(shallowChanges, { key = key, path = path })
    end, false)  -- deep watch

    local stopDeep = HybridReactive.watchReactive(deepObj, function(key, newValue, oldValue, path)
        table.insert(deepChanges, { key = key, path = path })
    end, false)  -- deep watch

    print("\nReactivity check:")
    print("shallowObj.user is reactive:", HybridReactive.isReactive(shallowObj.user))
    print("deepObj.user is reactive:", HybridReactive.isReactive(deepObj.user))

    -- Modify nested properties
    shallowObj.user.name = "Bob"  -- Won't trigger (user is not reactive)
    deepObj.user.name = "Bob"     -- Will trigger (user is reactive)

    shallowObj.user.age = 30      -- Won't trigger (user is not reactive)
    deepObj.user.age = 30         -- Will trigger (user is reactive)

    print("\nShallow reactive + deep watch changes:", #shallowChanges)
    print("Deep reactive + deep watch changes:", #deepChanges)

    -- The shallow reactive with deep watch should detect fewer changes
    expect(#shallowChanges).toBe(0)  -- No nested changes detected
    expect(#deepChanges).toBe(2)     -- Both nested changes detected

    stopShallow()
    stopDeep()
    print("[OK] Comparison test passed")
end)

print("\n========== Test Summary ==========")
print("Key findings:")
print("1. Shallow reactive + deep watch only detects top-level changes")
print("2. Nested objects in shallow reactive are NOT reactive")
print("3. Deep watch cannot watch non-reactive nested objects")
print("4. Assigning reactive objects to shallow reactive enables deep watching of those objects")
print("5. The 'shallow' parameter of reactive() determines object structure reactivity")
print("6. The 'shallow' parameter of watchReactive() determines watching depth")
print("7. Deep watching is limited by the actual reactivity of the object structure")
