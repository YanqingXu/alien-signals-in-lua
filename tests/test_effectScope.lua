-- test_effectScope.lua
-- Test for Lua implementation of reactive system - focusing on effect scope functionality
print("========== Reactive System Effect Scope Tests ==========\n")

-- Load reactive system
local reactive = require("alien_signals")
local signal = reactive.signal
local effect = reactive.effect
local effectScope = reactive.effectScope


local utils = require("utils")
local test = utils.test
local expect = utils.expect

local function expectArray(actual, expected)
    expect(#actual).toBe(#expected)
    for i = 1, #expected do
        expect(actual[i]).toBe(expected[i])
    end
end

test('should not trigger after stop', function ()
    local count = signal(1)

    local triggers = 0
    local effect1 = nil

    local stopScope = effectScope(function()
        effect1 = effect(function()
            triggers = triggers + 1
            count()
        end)
        expect(triggers).toBe(1)

        count(2)
        expect(triggers).toBe(2)
    end)

    count(3)
    expect(triggers).toBe(3)
    stopScope()
    count(4)
    expect(triggers).toBe(3)

    print("test passed\n")
end)

test('should dispose inner effects if created in an effect', function()
    local source = signal(1)

    local triggers = 0

    effect(function()
        local dispose = effectScope(function()
            effect(function()
                source()
                triggers = triggers + 1
            end)
        end)
        expect(triggers).toBe(1)

        source(2)
        expect(triggers).toBe(2)
        dispose()
        source(3)
        expect(triggers).toBe(2)
    end)

    print("test passed\n")
end)

test('should track signal updates in an inner scope when accessed by an outer effect', function()
    local source = signal(1)

    local triggers = 0

    effect(function()
        effectScope(function()
            source()
        end)
        triggers = triggers + 1
    end)

    expect(triggers).toBe(1)
    source(2)
    expect(triggers).toBe(2)

    print("test passed\n")
end)

test('scope dispose runs child effect cleanup', function()
    local log = {}
    local dispose = effectScope(function()
        effect(function()
            return function()
                table.insert(log, 'inner:cleanup')
            end
        end)
    end)

    dispose()
    expectArray(log, {'inner:cleanup'})

    print("test passed\n")
end)

test('scope dispose: sibling effects clean up in reverse creation (LIFO)', function()
    local log = {}
    local dispose = effectScope(function()
        effect(function()
            return function()
                table.insert(log, 'e1:cleanup')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'e2:cleanup')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'e3:cleanup')
            end
        end)
    end)

    dispose()
    expectArray(log, {'e3:cleanup', 'e2:cleanup', 'e1:cleanup'})

    print("test passed\n")
end)

test('scope dispose: nested effect cleanup runs depth-first reverse', function()
    local log = {}
    local dispose = effectScope(function()
        effect(function()
            effect(function()
                return function()
                    table.insert(log, 'grandchild:cleanup')
                end
            end)
            return function()
                table.insert(log, 'child:cleanup')
            end
        end)
    end)

    dispose()
    expectArray(log, {'grandchild:cleanup', 'child:cleanup'})

    print("test passed\n")
end)

test('scope as intermediate parent: cleanup order respects nesting', function()
    local a = signal(0)
    local log = {}

    effect(function()
        a()
        table.insert(log, 'outer:run')
        effectScope(function()
            effect(function()
                table.insert(log, 'inner:run')
                return function()
                    table.insert(log, 'inner:cleanup')
                end
            end)
        end)
        return function()
            table.insert(log, 'outer:cleanup')
        end
    end)

    log = {}
    a(1)
    expectArray(log, {
        'inner:cleanup',
        'outer:cleanup',
        'outer:run',
        'inner:run',
    })

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")

