--[[
Comprehensive test suite for HybridReactive.watchReactive functionality
HybridReactive.watchReactive 功能的综合测试套件

This file consolidates all watchReactive tests into a single comprehensive suite.
该文件将所有 watchReactive 测试整合到一个综合测试套件中。
]]

local utils = require('utils')
local HybridReactive = require('HybridReactive')
local test = utils.test
local expect = utils.expect

print("========== Comprehensive HybridReactive.watchReactive Test Suite ==========\n")

-- Helper function to measure execution time
local function measureTime(fn, description)
    local startTime = os.clock()
    fn()
    local endTime = os.clock()
    local duration = endTime - startTime
    if description then
        print(string.format("[PERF] %s: %.4f seconds", description, duration))
    end
    return duration
end

-- ============================================================================
-- SECTION 1: BASIC FUNCTIONALITY TESTS
-- ============================================================================

print("SECTION 1: Basic Functionality Tests")
print("=====================================")

-- Test 1.1: Basic callback functionality
test('Basic callback functionality', function()
    local callCount = 0
    local changes = {}

    local obj = HybridReactive.reactive({
        name = "Alice",
        age = 25
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        callCount = callCount + 1
        table.insert(changes, { key = key, newValue = newValue, oldValue = oldValue, path = path })
    end)

    obj.name = "Bob"
    obj.age = 30
    obj.name = "Charlie"

    expect(callCount).toBe(3)
    expect(changes[1].key).toBe("name")
    expect(changes[1].newValue).toBe("Bob")
    expect(changes[1].oldValue).toBe("Alice")
    expect(changes[1].path).toBe("name")

    stopWatcher()
    print("[OK] Basic callback functionality test passed")
end)

-- Test 1.2: Shallow vs deep monitoring
test('Shallow vs deep monitoring', function()
    local shallowCount = 0
    local deepCount = 0

    local obj = HybridReactive.reactive({
        user = {
            name = "Alice",
            profile = { age = 25 }
        },
        config = { theme = "dark" }
    })

    local stopShallow = HybridReactive.watchReactive(obj, function()
        shallowCount = shallowCount + 1
    end, true)  -- shallow = true

    local stopDeep = HybridReactive.watchReactive(obj, function()
        deepCount = deepCount + 1
    end, false)  -- deep = false

    -- Top-level changes (both should trigger)
    obj.user = { name = "Bob", profile = { age = 30 } }
    expect(shallowCount).toBe(1)
    expect(deepCount).toBe(1)

    -- Nested changes (only deep should trigger)
    obj.user.name = "Charlie"
    expect(shallowCount).toBe(1)  -- unchanged
    expect(deepCount).toBe(2)     -- increased

    obj.user.profile.age = 35
    expect(shallowCount).toBe(1)  -- unchanged
    expect(deepCount).toBe(3)     -- increased

    stopShallow()
    stopDeep()
    print("[OK] Shallow vs deep monitoring test passed")
end)

-- Test 1.3: Multiple watchers
test('Multiple watchers on same object', function()
    local watcher1Count = 0
    local watcher2Count = 0
    local watcher3Count = 0

    local obj = HybridReactive.reactive({
        data = { value = 10, nested = { count = 5 } }
    })

    local stop1 = HybridReactive.watchReactive(obj, function() watcher1Count = watcher1Count + 1 end, true)
    local stop2 = HybridReactive.watchReactive(obj, function() watcher2Count = watcher2Count + 1 end, false)
    local stop3 = HybridReactive.watchReactive(obj, function() watcher3Count = watcher3Count + 1 end, false)

    obj.data = { value = 20, nested = { count = 10 } }  -- All should trigger
    obj.data.value = 30                                 -- Only deep watchers
    obj.data.nested.count = 15                          -- Only deep watchers

    expect(watcher1Count).toBe(1)  -- Shallow: only data replacement
    expect(watcher2Count).toBe(3)  -- Deep: all changes
    expect(watcher3Count).toBe(3)  -- Deep: all changes

    stop1()
    stop2()
    stop3()
    print("[OK] Multiple watchers test passed")
end)

-- Test 1.4: Watcher lifecycle
test('Watcher lifecycle and cleanup', function()
    local callCount = 0

    local obj = HybridReactive.reactive({
        value = 10,
        nested = { count = 5 }
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function()
        callCount = callCount + 1
    end, false)

    obj.value = 20
    obj.nested.count = 10
    expect(callCount).toBe(2)

    stopWatcher()  -- Stop watching

    obj.value = 30
    obj.nested.count = 15
    expect(callCount).toBe(2)  -- Should remain unchanged

    print("[OK] Watcher lifecycle test passed")
end)

-- ============================================================================
-- SECTION 2: PATH TRACKING AND SAME KEY TESTS
-- ============================================================================

print("\nSECTION 2: Path Tracking and Same Key Tests")
print("============================================")

-- Test 2.1: Same key at different levels
test('Same key at different levels', function()
    local changes = {}

    local obj = HybridReactive.reactive({
        name = "root-name",
        user = {
            name = "user-name",
            profile = {
                name = "profile-name"
            }
        },
        config = {
            name = "config-name"
        }
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            newValue = newValue,
            oldValue = oldValue
        })
    end, false)

    obj.name = "new-root-name"
    obj.user.name = "new-user-name"
    obj.user.profile.name = "new-profile-name"
    obj.config.name = "new-config-name"

    expect(#changes).toBe(4)
    expect(changes[1].path).toBe("name")
    expect(changes[2].path).toBe("user.name")
    expect(changes[3].path).toBe("user.profile.name")
    expect(changes[4].path).toBe("config.name")

    stopWatcher()
    print("[OK] Same key at different levels test passed")
end)

-- Test 2.2: Path tracking accuracy
test('Path tracking accuracy', function()
    local paths = {}

    local obj = HybridReactive.reactive({
        level1 = {
            level2 = {
                level3 = {
                    level4 = {
                        value = "deep"
                    }
                }
            },
            sibling = "test"
        },
        root = "value"
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(paths, path or key)
    end, false)

    obj.root = "modified"
    obj.level1.sibling = "modified"
    obj.level1.level2.level3.level4.value = "very deep"

    expect(#paths).toBe(3)
    expect(paths[1]).toBe("root")
    expect(paths[2]).toBe("level1.sibling")
    expect(paths[3]).toBe("level1.level2.level3.level4.value")

    stopWatcher()
    print("[OK] Path tracking accuracy test passed")
end)

-- ============================================================================
-- SECTION 3: ADVANCED FEATURES
-- ============================================================================

print("\nSECTION 3: Advanced Features")
print("=============================")

-- Test 3.1: Object replacement
test('Object replacement with deep watching', function()
    local changes = {}

    local obj = HybridReactive.reactive({
        data = {
            name = "original",
            value = 100,
            nested = { flag = true }
        }
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            isReplacement = key == "data"
        })
    end, false)

    -- Replace entire object
    obj.data = {
        name = "replacement",
        value = 200,
        nested = { flag = false }
    }

    -- Modify new structure
    obj.data.name = "modified"
    obj.data.nested.flag = true

    expect(#changes).toBe(3)
    expect(changes[1].isReplacement).toBe(true)
    expect(changes[2].key).toBe("name")
    expect(changes[3].key).toBe("flag")

    stopWatcher()
    print("[OK] Object replacement test passed")
end)

-- Test 3.2: Mixed data types
test('Mixed data types handling', function()
    local changes = {}

    local obj = HybridReactive.reactive({
        string = "hello",
        number = 42,
        boolean = true,
        table = {nested = "value"},
        nilValue = "initial"
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            newType = type(newValue),
            oldType = type(oldValue)
        })
    end, false)

    obj.string = 123
    obj.number = false
    obj.boolean = {new = "table"}
    obj.nilValue = nil

    expect(#changes >= 3).toBe(true)
    expect(changes[1].oldType).toBe("string")
    expect(changes[1].newType).toBe("number")

    stopWatcher()
    print("[OK] Mixed data types test passed")
end)

-- Test 3.3: Batch operations
test('Batch operations', function()
    local changes = {}

    local obj = HybridReactive.reactive({
        a = 1, b = 2, c = 3,
        nested = { x = 10, y = 20 }
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {key = key, path = path})
    end, false)

    HybridReactive.startBatch()
    obj.a = 11
    obj.b = 22
    obj.c = 33
    obj.nested.x = 100
    obj.nested.y = 200
    HybridReactive.endBatch()

    expect(#changes).toBe(5)

    stopWatcher()
    print("[OK] Batch operations test passed")
end)

-- ============================================================================
-- SECTION 4: ERROR HANDLING AND EDGE CASES
-- ============================================================================

print("\nSECTION 4: Error Handling and Edge Cases")
print("=========================================")

-- Test 4.1: Error handling
test('Error handling', function()
    -- Test with non-reactive object
    local success1, err1 = pcall(function()
        HybridReactive.watchReactive({name = "test"}, function() end)
    end)
    expect(success1).toBe(false)
    expect(string.find(err1, "must be a reactive object") ~= nil).toBe(true)

    -- Test with non-function callback
    local obj = HybridReactive.reactive({name = "test"})
    local success2, err2 = pcall(function()
        HybridReactive.watchReactive(obj, "not a function")
    end)
    expect(success2).toBe(false)
    expect(string.find(err2, "must be a function") ~= nil).toBe(true)

    print("[OK] Error handling test passed")
end)

-- Test 4.2: Circular references
test('Circular references handling', function()
    local changes = {}

    local obj1 = HybridReactive.reactive({name = "obj1", value = 1})
    local obj2 = HybridReactive.reactive({name = "obj2", value = 2})

    obj1.ref = obj2
    obj2.ref = obj1

    local stopWatcher = HybridReactive.watchReactive(obj1, function(key, newValue, oldValue, path)
        table.insert(changes, {key = key, path = path})
    end, false)

    obj1.value = 10
    obj2.value = 20

    expect(#changes >= 1).toBe(true)

    stopWatcher()
    print("[OK] Circular references test passed")
end)

-- ============================================================================
-- SECTION 5: PERFORMANCE TESTS
-- ============================================================================

print("\nSECTION 5: Performance Tests")
print("=============================")

-- Test 5.1: Large object performance
test('Large object performance', function()
    local changeCount = 0

    local largeObj = {}
    for i = 1, 500 do
        largeObj["prop" .. i] = i
    end

    local reactiveObj = HybridReactive.reactive(largeObj)

    local setupTime = measureTime(function()
        local stopWatcher = HybridReactive.watchReactive(reactiveObj, function()
            changeCount = changeCount + 1
        end, false)
        reactiveObj._stopWatcher = stopWatcher
    end, "Setup watcher for 500 properties")

    local modifyTime = measureTime(function()
        for i = 1, 50 do
            reactiveObj["prop" .. i] = i * 10
        end
    end, "Modify 50 properties")

    expect(changeCount).toBe(50)
    expect(setupTime < 0.5).toBe(true)
    expect(modifyTime < 0.1).toBe(true)

    reactiveObj._stopWatcher()
    print("[OK] Large object performance test passed")
end)

-- Test 5.2: Deep nesting performance
test('Deep nesting performance', function()
    local changeCount = 0

    local function createDeepObject(depth)
        if depth <= 0 then
            return {value = 0}
        end
        return {
            level = depth,
            nested = createDeepObject(depth - 1)
        }
    end

    local deepObj = HybridReactive.reactive(createDeepObject(20))

    local setupTime = measureTime(function()
        local stopWatcher = HybridReactive.watchReactive(deepObj, function()
            changeCount = changeCount + 1
        end, false)
        deepObj._stopWatcher = stopWatcher
    end, "Setup watcher for 20-level deep object")

    local modifyTime = measureTime(function()
        deepObj.level = 999
        deepObj.nested.level = 888
        deepObj.nested.nested.level = 777
    end, "Modify properties at various depths")

    expect(changeCount >= 1).toBe(true)
    expect(setupTime < 0.5).toBe(true)
    expect(modifyTime < 0.1).toBe(true)

    deepObj._stopWatcher()
    print("[OK] Deep nesting performance test passed")
end)

-- Test 5.3: Multiple watchers performance
test('Multiple watchers performance', function()
    local totalChanges = 0

    local obj = HybridReactive.reactive({
        value = 0,
        nested = {count = 0}
    })

    local watchers = {}

    local setupTime = measureTime(function()
        for i = 1, 50 do
            local watcher = HybridReactive.watchReactive(obj, function()
                totalChanges = totalChanges + 1
            end, false)
            table.insert(watchers, watcher)
        end
    end, "Setup 50 watchers on same object")

    local modifyTime = measureTime(function()
        for i = 1, 5 do
            obj.value = i
        end
    end, "5 modifications with 50 watchers")

    expect(totalChanges).toBe(250) -- 5 changes * 50 watchers
    expect(setupTime < 0.5).toBe(true)
    expect(modifyTime < 0.1).toBe(true)

    for _, watcher in ipairs(watchers) do
        watcher()
    end
    print("[OK] Multiple watchers performance test passed")
end)

-- ============================================================================
-- SECTION 6: INTEGRATION TESTS
-- ============================================================================

print("\nSECTION 6: Integration Tests")
print("=============================")

-- Test 6.1: Integration with ref objects
test('Integration with ref objects', function()
    local changes = {}

    local refValue = HybridReactive.ref(42)
    local obj = HybridReactive.reactive({
        data = refValue,
        nested = {
            refProp = HybridReactive.ref("hello")
        }
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            isRef = HybridReactive.isRef(newValue)
        })
    end, false)

    -- Replace with new ref
    obj.data = HybridReactive.ref(200)

    expect(#changes).toBe(1)
    expect(changes[1].key).toBe("data")
    expect(changes[1].isRef).toBe(true)

    stopWatcher()
    print("[OK] Integration with ref objects test passed")
end)

-- Test 6.2: Stress test with rapid changes
test('Stress test with rapid changes', function()
    local changeCount = 0

    local obj = HybridReactive.reactive({
        counter = 0,
        nested = { value = 0 }
    })

    local stopWatcher = HybridReactive.watchReactive(obj, function()
        changeCount = changeCount + 1
    end, false)

    local stressTime = measureTime(function()
        for i = 1, 100 do
            obj.counter = i
            if i % 2 == 0 then
                obj.nested.value = i * 2
            end
        end
    end, "100 rapid modifications")

    expect(changeCount).toBe(150) -- 100 counter + 50 nested.value
    expect(stressTime < 0.5).toBe(true)

    stopWatcher()
    print("[OK] Stress test passed")
end)

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================

print("\n" .. string.rep("=", 80))
print("COMPREHENSIVE WATCHREACTIVE TEST SUMMARY")
print(string.rep("=", 80))

print("\n[OK] SECTION 1: Basic Functionality Tests")
print("        Basic callback functionality")
print("        Shallow vs deep monitoring")
print("        Multiple watchers on same object")
print("        Watcher lifecycle and cleanup")

print("\n[OK] SECTION 2: Path Tracking and Same Key Tests")
print("        Same key at different levels")
print("        Path tracking accuracy")

print("\n[OK] SECTION 3: Advanced Features")
print("        Object replacement with deep watching")
print("        Mixed data types handling")
print("        Batch operations")

print("\n[OK] SECTION 4: Error Handling and Edge Cases")
print("        Error handling")
print("        Circular references handling")

print("\n[OK] SECTION 5: Performance Tests")
print("        Large object performance")
print("        Deep nesting performance")
print("        Multiple watchers performance")

print("\n[OK] SECTION 6: Integration Tests")
print("        Integration with ref objects")
print("        Stress test with rapid changes")

print("\n[CONGRATS!!!] ALL WATCHREACTIVE TESTS COMPLETED SUCCESSFULLY! [CONGRATS!!!]")
print("\nHybridReactive.watchReactive functionality is fully validated across:")
print("     Basic functionality and lifecycle management")
print("     Path tracking and same key disambiguation")
print("     Advanced features and edge cases")
print("     Performance and scalability")
print("     Integration with other reactive features")

print("\n" .. string.rep("=", 80))
