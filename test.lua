package.path = package.path .. ";../?.lua"
require 'global'

local effect = require 'effect'
local signal = require 'signal'
local computed = require 'computed'
local effectScope = require 'effectScope'

local function test1()
    local bRunTimes = 0

    local a = signal.signal(1)
    local b = computed.computed(function()
        bRunTimes = bRunTimes + 1
        return a:get() * 2
    end)
    local effect1 = effect.effect(function()
        b:get()
    end)

    assert(bRunTimes == 1)
    a:set(2)
    assert(bRunTimes == 2)
    effect1:stop()
    a:set(3)
    assert(bRunTimes == 2)
end

local function test2()
    local a = signal.signal(3)
    local b = computed.computed(function()
        return a:get() > 0
    end)

    effect.effect(function()
        if b:get() then
            effect.effect(function()
                if a:get() == 0 then
                    error("bad")
                end
            end)
        end
    end)

    local function decrement()
        a:set(a:get() - 1)
    end

    decrement()
    decrement()
    decrement()
end

local function test3()
    local a = signal.signal(1)
    local b = signal.signal(1)

    effect.effect(function()
        if a:get() then
            effect.effect(function()
                b:get()
                if a:get() == 0 then
                    error("bad")
                end
            end)
        else
        end
    end)

    global.startBatch()
    b:set(0)
    a:set(0)
    global.endBatch()
end

local function test4()
    local a = signal.signal(0)
    local b = computed.computed(function()
        return a:get() % 2
    end)

    local innerTriggerTimes = 0

    effect.effect(function()
        effect.effect(function()
            b:get()
            innerTriggerTimes = innerTriggerTimes + 1
            if innerTriggerTimes > 1 then
                error("bad")
            end
        end)
    end)

    a:set(2)
end

local function test5()
    local a = signal.signal(0)
    local b = signal.signal(0)
    local c = computed.computed(function()
        return a:get() - b:get()
    end)

    local order = {}
    effect.effect(function()
        c:get()

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
end

local function test6()
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
end

test1()
test2()
test3()
test4()
test5()
test6()

