--[[
Test: Deep reactive object with shallow watchReactive
测试：深层响应式对象配合浅层 watchReactive

This test explores what happens when:
- HybridReactive.reactive() is called with shallow = false (deep reactive)
- HybridReactive.watchReactive() is called with shallow = true (shallow watch)

该测试探索以下情况：
- HybridReactive.reactive() 使用 shallow = false（深层响应式）
- HybridReactive.watchReactive() 使用 shallow = true（浅层监听）
]]

local utils = require('utils')
local HybridReactive = require('HybridReactive')
local test = utils.test
local expect = utils.expect

print("========== Deep Reactive + Shallow Watch Test ==========\n")

-- Test 1: Basic behavior - deep reactive with shallow watch
test('Deep reactive with shallow watch - basic behavior', function()
    local changes = {}

    -- Create deep reactive object
    local obj = HybridReactive.reactive({
        name = "Alice",
        user = {
            profile = {
                age = 25,
                settings = {
                    theme = "dark",
                    notifications = {
                        email = true,
                        push = false
                    }
                }
            },
            preferences = {
                language = "en"
            }
        },
        config = {
            version = "1.0",
            features = {
                advanced = true
            }
        }
    }, false)  -- shallow = false (deep reactive)

    -- Shallow watch on deep reactive object
    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            newValue = newValue,
            oldValue = oldValue,
            newValueIsReactive = HybridReactive.isReactive(newValue)
        })
    end, true)  -- shallow = true (shallow watch)

    print("Initial object structure:")
    print("obj.user is reactive:", HybridReactive.isReactive(obj.user))
    print("obj.user.profile is reactive:", HybridReactive.isReactive(obj.user.profile))
    print("obj.config is reactive:", HybridReactive.isReactive(obj.config))

    -- Test 1: Modify top-level property (should be detected)
    obj.name = "Bob"

    -- Test 2: Modify nested property (should NOT be detected by shallow watch)
    obj.user.profile.age = 30

    -- Test 3: Modify deeply nested property (should NOT be detected by shallow watch)
    obj.user.profile.settings.theme = "light"
    obj.user.profile.settings.notifications.email = false

    -- Test 4: Replace entire nested object (should be detected)
    obj.user = {
        profile = {
            age = 35,
            settings = {
                theme = "auto"
            }
        }
    }

    -- Test 5: Modify config nested property (should NOT be detected)
    obj.config.features.advanced = false

    -- Test 6: Replace config object (should be detected)
    obj.config = { version = "2.0", features = { advanced = false, beta = true } }

    print("\nChanges detected by shallow watch:")
    for i, change in ipairs(changes) do
        print(string.format("%d. Key: %s, Path: %s, NewValue reactive: %s", 
              i, change.key, change.path, tostring(change.newValueIsReactive)))
    end

    -- Expectations:
    -- 1. obj.name change should be detected (top-level)
    -- 2. obj.user.profile.age change should NOT be detected (nested)
    -- 3. obj.user.profile.settings.* changes should NOT be detected (deeply nested)
    -- 4. obj.user replacement should be detected (top-level)
    -- 5. obj.config.features.advanced change should NOT be detected (nested)
    -- 6. obj.config replacement should be detected (top-level)

    expect(#changes).toBe(3)  -- Only top-level changes should be detected
    expect(changes[1].key).toBe("name")
    expect(changes[2].key).toBe("user")
    expect(changes[3].key).toBe("config")

    stopWatcher()
    print("[OK] Deep reactive with shallow watch - basic behavior test passed")
end)

-- Test 2: Verify that nested objects are still reactive despite shallow watching
test('Nested objects remain reactive despite shallow watching', function()
    local nestedChanges = {}

    -- Create deep reactive object
    local obj = HybridReactive.reactive({
        data = {
            items = {
                count = 5,
                list = {
                    first = "item1",
                    second = "item2"
                }
            }
        }
    }, false)  -- deep reactive

    -- Shallow watch on the main object
    local stopMainWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        -- This should only detect top-level changes
    end, true)  -- shallow watch

    -- Deep watch directly on the nested object to verify it's still reactive
    local stopNestedWatcher = HybridReactive.watchReactive(obj.data, function(key, newValue, oldValue, path)
        table.insert(nestedChanges, {
            key = key,
            path = path
        })
    end, false)  -- deep watch on nested object

    print("\nNested object reactivity check:")
    print("obj.data is reactive:", HybridReactive.isReactive(obj.data))
    print("obj.data.items is reactive:", HybridReactive.isReactive(obj.data.items))
    print("obj.data.items.list is reactive:", HybridReactive.isReactive(obj.data.items.list))

    -- Modify nested properties
    obj.data.items.count = 10
    obj.data.items.list.first = "newItem1"
    obj.data.items.list.second = "newItem2"

    print("\nNested changes detected by direct deep watch:")
    for i, change in ipairs(nestedChanges) do
        print(string.format("%d. Key: %s, Path: %s", i, change.key, change.path))
    end

    -- The nested objects should still be reactive and detectable by direct watching
    expect(#nestedChanges).toBe(3)  -- All nested changes should be detected

    stopMainWatcher()
    stopNestedWatcher()
    print("[OK] Nested objects remain reactive test passed")
end)

-- Test 3: Performance comparison - shallow watch vs deep watch on deep reactive
test('Performance comparison: shallow vs deep watch on deep reactive', function()
    local shallowChanges = {}
    local deepChanges = {}

    -- Create a complex deep reactive object
    local complexObj = HybridReactive.reactive({
        level1 = {
            level2 = {
                level3 = {
                    level4 = {
                        value = "deep"
                    }
                }
            },
            sibling = {
                data = "test"
            }
        },
        root = "value"
    }, false)  -- deep reactive

    -- Shallow watch
    local stopShallow = HybridReactive.watchReactive(complexObj, function(key, newValue, oldValue, path)
        table.insert(shallowChanges, { key = key, path = path })
    end, true)  -- shallow watch

    -- Deep watch
    local stopDeep = HybridReactive.watchReactive(complexObj, function(key, newValue, oldValue, path)
        table.insert(deepChanges, { key = key, path = path })
    end, false)  -- deep watch

    -- Perform various modifications
    complexObj.root = "modified"  -- Top-level (both should detect)
    complexObj.level1.sibling.data = "modified"  -- Nested (only deep should detect)
    complexObj.level1.level2.level3.level4.value = "very deep modified"  -- Deep nested (only deep should detect)

    print("\nPerformance comparison results:")
    print("Shallow watch detected changes:", #shallowChanges)
    print("Deep watch detected changes:", #deepChanges)

    print("\nShallow watch changes:")
    for i, change in ipairs(shallowChanges) do
        print(string.format("  %d. %s at %s", i, change.key, change.path))
    end

    print("\nDeep watch changes:")
    for i, change in ipairs(deepChanges) do
        print(string.format("  %d. %s at %s", i, change.key, change.path))
    end

    -- Shallow watch should detect fewer changes (better performance)
    expect(#shallowChanges).toBe(1)  -- Only root change
    expect(#deepChanges).toBe(3)     -- All changes

    stopShallow()
    stopDeep()
    print("[OK] Performance comparison test passed")
end)

-- Test 4: Mixed scenarios - replacing reactive objects
test('Mixed scenarios: replacing reactive objects in deep reactive', function()
    local changes = {}

    -- Create deep reactive object
    local obj = HybridReactive.reactive({
        section1 = { data = "original1" },
        section2 = { data = "original2" }
    }, false)  -- deep reactive

    -- Shallow watch
    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            newValueIsReactive = HybridReactive.isReactive(newValue),
            oldValueIsReactive = HybridReactive.isReactive(oldValue)
        })
    end, true)  -- shallow watch

    print("\nInitial state:")
    print("obj.section1 is reactive:", HybridReactive.isReactive(obj.section1))
    print("obj.section2 is reactive:", HybridReactive.isReactive(obj.section2))

    -- Replace with new reactive object
    local newReactiveSection = HybridReactive.reactive({ data = "new reactive" }, false)
    obj.section1 = newReactiveSection

    -- Replace with plain object (will be made reactive by deep reactive)
    obj.section2 = { data = "new plain" }

    print("\nAfter replacements:")
    print("obj.section1 is reactive:", HybridReactive.isReactive(obj.section1))
    print("obj.section2 is reactive:", HybridReactive.isReactive(obj.section2))

    print("\nChanges detected:")
    for i, change in ipairs(changes) do
        print(string.format("%d. Key: %s, NewValue reactive: %s, OldValue reactive: %s", 
              i, change.key, tostring(change.newValueIsReactive), tostring(change.oldValueIsReactive)))
    end

    expect(#changes).toBe(2)  -- Both replacements should be detected

    stopWatcher()
    print("[OK] Mixed scenarios test passed")
end)

print("\n========== Test Summary ==========")
print("Key findings:")
print("1. Deep reactive + shallow watch only detects TOP-LEVEL changes")
print("2. Nested objects remain fully reactive despite shallow watching")
print("3. Shallow watch provides performance benefits by ignoring nested changes")
print("4. You can still watch nested objects directly if needed")
print("5. Object replacements at top level are always detected")
print("6. The 'shallow' parameter of watchReactive() acts as a FILTER")
print("7. Deep reactive structure is preserved regardless of watch depth")
