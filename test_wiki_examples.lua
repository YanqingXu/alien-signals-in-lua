--[[
Test examples from wiki_watch.md to ensure they work correctly
测试 wiki_watch.md 中的示例代码以确保其正确性
]]

local utils = require('utils')
local HybridReactive = require('HybridReactive')
local test = utils.test
local expect = utils.expect

print("========== Wiki Examples Validation Test ==========\n")

-- Test 1: Basic watch() example from wiki
test('Wiki example: Basic watch() usage', function()
    local user = HybridReactive.reactive({
        name = "Alice",
        age = 25,
        profile = {
            email = "alice@example.com",
            settings = {
                theme = "dark"
            }
        }
    })
    
    local watchCount = 0
    local lastOutput = ""
    
    local stopWatch = HybridReactive.watch(function()
        local name = user.name
        local email = user.profile.email
        lastOutput = string.format("User: %s (%s)", name, email)
        watchCount = watchCount + 1
    end)
    
    -- Initial execution
    expect(watchCount).toBe(1)
    expect(lastOutput).toBe("User: Alice (alice@example.com)")
    
    -- Test changes
    user.name = "Bob"
    expect(watchCount).toBe(2)
    expect(lastOutput).toBe("User: Bob (alice@example.com)")
    
    user.age = 30  -- Should not trigger (not accessed)
    expect(watchCount).toBe(2)
    
    user.profile.email = "bob@example.com"
    expect(watchCount).toBe(3)
    expect(lastOutput).toBe("User: Bob (bob@example.com)")
    
    stopWatch()
    print("[OK] Basic watch() example works correctly")
end)

-- Test 2: Basic watchReactive() example from wiki
test('Wiki example: Basic watchReactive() usage', function()
    local user = HybridReactive.reactive({
        name = "Alice",
        age = 25,
        profile = {
            email = "alice@example.com",
            settings = {
                theme = "dark"
            }
        }
    })
    
    local changes = {}
    
    local stopWatcher = HybridReactive.watchReactive(user, function(key, newValue, oldValue, path)
        table.insert(changes, {
            key = key,
            path = path,
            newValue = newValue,
            oldValue = oldValue
        })
    end, false)
    
    user.name = "Bob"
    user.age = 30
    user.profile.email = "bob@example.com"
    user.profile.settings.theme = "light"
    
    expect(#changes).toBe(4)
    expect(changes[1].key).toBe("name")
    expect(changes[1].path).toBe("name")
    expect(changes[2].key).toBe("age")
    expect(changes[3].key).toBe("email")
    expect(changes[3].path).toBe("profile.email")
    expect(changes[4].key).toBe("theme")
    expect(changes[4].path).toBe("profile.settings.theme")
    
    stopWatcher()
    print("[OK] Basic watchReactive() example works correctly")
end)

-- Test 3: Shallow vs Deep monitoring example
test('Wiki example: Shallow vs Deep monitoring', function()
    local obj = HybridReactive.reactive({
        user = {
            name = "Alice",
            profile = { age = 25 }
        },
        config = { theme = "dark" }
    }, false)  -- deep reactive
    
    local shallowChanges = {}
    local deepChanges = {}
    
    local stopShallow = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(shallowChanges, { key = key, path = path })
    end, true)  -- shallow = true
    
    local stopDeep = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        table.insert(deepChanges, { key = key, path = path })
    end, false)  -- shallow = false
    
    -- Top-level change (both should trigger)
    obj.user = { name = "Bob", profile = { age = 30 } }
    expect(#shallowChanges).toBe(1)
    expect(#deepChanges).toBe(1)
    
    -- Nested change (only deep should trigger)
    obj.user.name = "Charlie"
    expect(#shallowChanges).toBe(1)  -- unchanged
    expect(#deepChanges).toBe(2)     -- increased
    
    obj.user.profile.age = 35
    expect(#shallowChanges).toBe(1)  -- unchanged
    expect(#deepChanges).toBe(3)     -- increased
    
    stopShallow()
    stopDeep()
    print("[OK] Shallow vs Deep monitoring example works correctly")
end)

-- Test 4: Performance comparison example
test('Wiki example: Performance comparison', function()
    local obj = HybridReactive.reactive({
        a = 1, b = 2, c = 3, d = 4, e = 5,
        nested = { x = 10, y = 20, z = 30 }
    }, false)
    
    local watchCount = 0
    local watchReactiveCount = 0
    
    -- watch() - selective monitoring
    local stopWatch = HybridReactive.watch(function()
        local sum = obj.a + obj.nested.x
        watchCount = watchCount + 1
    end)
    
    -- watchReactive() - comprehensive monitoring
    local stopWatchReactive = HybridReactive.watchReactive(obj, function()
        watchReactiveCount = watchReactiveCount + 1
    end, false)
    
    -- Modify tracked properties
    obj.a = 10          -- Both should trigger
    obj.nested.x = 100  -- Both should trigger
    
    -- Modify untracked properties (by watch)
    obj.b = 20          -- Only watchReactive should trigger
    obj.c = 30          -- Only watchReactive should trigger
    
    expect(watchCount).toBe(3)  -- Initial + 2 tracked changes
    expect(watchReactiveCount).toBe(4)  -- All 4 changes
    
    stopWatch()
    stopWatchReactive()
    print("[OK] Performance comparison example works correctly")
end)

-- Test 5: Conditional dependency tracking
test('Wiki example: Conditional dependency tracking', function()
    local data = HybridReactive.reactive({
        input1 = 10,
        input2 = 20,
        config = { enabled = true },
        cache = { result = 0 }
    })
    
    local computationCount = 0
    
    HybridReactive.watch(function()
        if data.config.enabled then
            local result = data.input1 + data.input2
            data.cache.result = result
            computationCount = computationCount + 1
        end
    end)
    
    -- Initial computation
    expect(computationCount).toBe(1)
    expect(data.cache.result).toBe(30)
    
    -- Change input when enabled
    data.input1 = 15
    expect(computationCount).toBe(2)
    expect(data.cache.result).toBe(35)
    
    -- Disable computation
    data.config.enabled = false
    expect(computationCount).toBe(2)  -- No computation performed
    
    -- Change input when disabled (should not trigger computation)
    data.input2 = 25
    expect(computationCount).toBe(2)  -- Still no computation
    
    print("[OK] Conditional dependency tracking example works correctly")
end)

print("\n========== Wiki Examples Validation Summary ==========")
print("All wiki examples have been validated and work correctly!")
print("The documentation examples are accurate and functional.")
