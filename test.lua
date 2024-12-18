require 'global'

local effect = require 'effect'
local signal = require 'signal'
local computed = require 'computed'
local effectScope = require 'effectScope'

local test = {
    it = function(name, fn)
        print(name)
        fn()
    end,
}

local expect = function(actual)
    return {
        toBe = function(expected)
            assert(actual == expected)
        end
    }
end

test.it("should clear subscriptions when untracked by all subscribers", function()
    local bRunTimes = 0

    local a = signal.signal(1, "signal_a")
    local b = computed.computed(function()
        bRunTimes = bRunTimes + 1
        return a:get() * 2
    end, "computed_b")
    local effect1 = effect.effect(function()
        b:get()
    end, "effect1")

    assert(bRunTimes == 1)
    a:set(2)
    assert(bRunTimes == 2)
    effect1:stop()
    a:set(3)
    assert(bRunTimes == 2)
end)

test.it("should not run untracked inner effect", function()
    local a = signal.signal(3, "signal_a")
    local b = computed.computed(function()
        return a:get() > 0
    end, "computed_b")

    effect.effect(function()
        if b:get() then
            effect.effect(function()
                if a:get() == 0 then
                    error("bad")
                end
            end, "inner effect")
        end
    end, "outer effect")

    local function decrement()
        a:set(a:get() - 1)
    end

    decrement()
    decrement()
    decrement()
end)

test.it("should run outer effect first", function()
    local a = signal.signal(1, "signal_a")
    local b = signal.signal(1, "signal_b")

    effect.effect(function()
        if a:get() then
            effect.effect(function()
                b:get()
                if a:get() == 0 then
                    error("bad")
                end
            end, "inner effect")
        end
    end, "outer effect")

    global.startBatch()
    b:set(0)
    a:set(0)
    global.endBatch()
end)

test.it("should not trigger inner effect when resolve maybe dirty", function()
    local a = signal.signal(0, "signal_a")
    local b = computed.computed(function()
        return a:get() % 2
    end, "computed_b")

    local innerTriggerTimes = 0

    effect.effect(function()
        effect.effect(function()
            b:get()
            innerTriggerTimes = innerTriggerTimes + 1
            if innerTriggerTimes > 1 then
                error("bad")
            end
        end, "inner effect")
    end, "outer effect")

    a:set(2)
end)

test.it("should trigger inner effects in sequence", function()
    local a = signal.signal(0, "signal_a")
    local b = signal.signal(0, "signal_b")
    local c = computed.computed(function()
        return a:get() - b:get()
    end, "computed_c")

    local order = {}
    effect.effect(function()
        c:get()

        effect.effect(function()
            table.insert(order, 'first inner')
            a:get()
        end, "inner effect 1")

        effect.effect(function()
            table.insert(order, 'last inner')
            a:get()
            b:get()
        end, "inner effect 2")
    end, "outer effect")

    order = {}

    global.startBatch()
    b:set(1)
    a:set(1)
    global.endBatch()

    assert(#order == 2)
    assert(order[1] == 'first inner')
    assert(order[2] == 'last inner')
end)

test.it("should trigger inner effects in sequence in effect scope", function()
    local a = signal.signal(0)
    local b = signal.signal(0)
    local scope = effectScope.effectScope()
    local order = {}

    scope:run(function()
        effect.effect(function()
            table.insert(order, 'first inner')
            a:get()
        end)

        effect.effect(function()
            table.insert(order, 'last inner')
            a:get()
            b:get()
        end)
    end)

    order = {}

    global.startBatch()
    b:set(1)
    a:set(1)
    global.endBatch()

    assert(#order == 2)
    assert(order[1] == 'first inner')
    assert(order[2] == 'last inner')
end)

test.it("should not trigger after stop", function()
    local count = signal.signal(1)
    local scope = effectScope.effectScope()

    local triggers = 0

    scope:run(function()
        effect.effect(function()
            triggers = triggers + 1
            count:get()
        end)
    end)

    expect(triggers).toBe(1)
    count:set(2)
    expect(triggers).toBe(2)
    scope:stop()
    count:set(3)
    expect(triggers).toBe(2)
end)