-- test_effect_cleanup.lua
-- Regression tests for alien-signals 3.2.1 effect cleanup semantics
print("========== Reactive System Effect Cleanup Tests ==========\n")

local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = require("alien_signals")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect

local function expectArray(actual, expected)
    expect(#actual).toBe(#expected)
    for i = 1, #expected do
        expect(actual[i]).toBe(expected[i])
    end
end

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

test('cleanup order on outer re-run: inner before outer, before new run', function()
    local log = {}
    local a = signal(0)

    effect(function()
        a()
        table.insert(log, 'outer:run')
        effect(function()
            table.insert(log, 'inner:run')
            return function()
                table.insert(log, 'inner:cleanup')
            end
        end)
        return function()
            table.insert(log, 'outer:cleanup')
        end
    end)
    expectArray(log, {'outer:run', 'inner:run'})

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

test('cleanup order on dispose: inner before outer', function()
    local log = {}

    local dispose = effect(function()
        table.insert(log, 'outer:run')
        effect(function()
            table.insert(log, 'inner:run')
            return function()
                table.insert(log, 'inner:cleanup')
            end
        end)
        return function()
            table.insert(log, 'outer:cleanup')
        end
    end)

    log = {}
    dispose()
    expectArray(log, {'inner:cleanup', 'outer:cleanup'})

    print("test passed\n")
end)

test('sibling cleanup order on dispose: reverse creation (LIFO)', function()
    local log = {}

    local dispose = effect(function()
        effect(function()
            return function()
                table.insert(log, 'inner1:cleanup')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'inner2:cleanup')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'inner3:cleanup')
            end
        end)
        return function()
            table.insert(log, 'outer:cleanup')
        end
    end)

    dispose()
    expectArray(log, {
        'inner3:cleanup',
        'inner2:cleanup',
        'inner1:cleanup',
        'outer:cleanup',
    })

    print("test passed\n")
end)

test('sibling cleanup order on outer re-run: reverse creation (LIFO)', function()
    local log = {}
    local a = signal(0)

    effect(function()
        a()
        effect(function()
            return function()
                table.insert(log, 'inner1:cleanup')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'inner2:cleanup')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'inner3:cleanup')
            end
        end)
        return function()
            table.insert(log, 'outer:cleanup')
        end
    end)

    log = {}
    a(1)
    expectArray({log[1], log[2], log[3], log[4]}, {
        'inner3:cleanup',
        'inner2:cleanup',
        'inner1:cleanup',
        'outer:cleanup',
    })

    print("test passed\n")
end)

test('three-level nested cleanup on dispose: deepest first', function()
    local log = {}

    local dispose = effect(function()
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
        return function()
            table.insert(log, 'outer:cleanup')
        end
    end)

    dispose()
    expectArray(log, {
        'grandchild:cleanup',
        'child:cleanup',
        'outer:cleanup',
    })

    print("test passed\n")
end)

test('computed unwatched: child effect cleanups run in reverse creation (LIFO)', function()
    local log = {}
    local c = computed(function()
        effect(function()
            return function()
                table.insert(log, 'e1')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'e2')
            end
        end)
        effect(function()
            return function()
                table.insert(log, 'e3')
            end
        end)
        return 0
    end)

    local dispose = effect(function()
        c()
    end)

    log = {}
    dispose()
    expectArray(log, {'e3', 'e2', 'e1'})

    print("test passed\n")
end)

test('effect created inside computed: old inner cleanup runs before new inner setup', function()
    local a = signal(0)
    local log = {}

    local c = computed(function()
        table.insert(log, 'computed:eval')
        effect(function()
            table.insert(log, 'inner:run')
            return function()
                table.insert(log, 'inner:cleanup')
            end
        end)
        return a()
    end)

    effect(function()
        c()
    end)

    log = {}
    a(1)
    expectArray(log, {
        'inner:cleanup',
        'computed:eval',
        'inner:run',
    })

    print("test passed\n")
end)

test('cleanup order is correct after a prior inner-only re-run', function()
    local a = signal(0)
    local b = signal(0)
    local log = {}

    effect(function()
        a()
        table.insert(log, 'outer:run')
        effect(function()
            b()
            table.insert(log, 'inner:run')
            return function()
                table.insert(log, 'inner:cleanup')
            end
        end)
        return function()
            table.insert(log, 'outer:cleanup')
        end
    end)

    b(1)
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

test('outer effect keeps responding to its own dep after inner re-runs', function()
    local a = signal(0)
    local b = signal(0)
    local outerRuns = 0
    local innerRuns = 0

    effect(function()
        a()
        outerRuns = outerRuns + 1
        effect(function()
            b()
            innerRuns = innerRuns + 1
        end)
    end)

    expect(outerRuns).toBe(1)
    expect(innerRuns).toBe(1)

    b(1)
    expect(outerRuns).toBe(1)
    assert(innerRuns >= 2)

    a(1)
    expect(outerRuns).toBe(2)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")
