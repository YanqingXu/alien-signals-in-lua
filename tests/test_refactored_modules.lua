-- test_refactored_modules.lua
-- Module-level checks for the refactored implementation internals.
print("========== Refactored Module Tests ==========\n")

local utils = require("utils")
local test = utils.test
local expect = utils.expect

local reactive = package.loaded["alien_signals"] or require("refactored")
local constants = require("refactored.constants")
local graph = require("refactored.graph")

local ReactiveFlags = constants.ReactiveFlags

local function expectArray(actual, expected)
    expect(#actual).toBe(#expected)
    for i = 1, #expected do
        expect(actual[i]).toBe(expected[i])
    end
end

local function assertGraphOk(ok, err)
    if not ok then
        error(err)
    end
end

test("node type helpers identify bound callables", function()
    local source = reactive.signal(1)
    local doubled = reactive.computed(function()
        return source() * 2
    end)
    local stopEffect = reactive.effect(function()
        doubled()
    end)
    local stopScope = reactive.effectScope(function() end)

    local signalNode = constants.nodeForCallable(source)
    local computedNode = constants.nodeForCallable(doubled)
    local effectNode = constants.nodeForCallable(stopEffect)
    local scopeNode = constants.nodeForCallable(stopScope)

    expect(constants.isSignalNode(signalNode)).toBe(true)
    expect(constants.isComputedNode(computedNode)).toBe(true)
    expect(constants.isEffectNode(effectNode)).toBe(true)
    expect(constants.isEffectScopeNode(scopeNode)).toBe(true)
    expect(constants.isValueProducerNode(signalNode)).toBe(true)
    expect(constants.isValueProducerNode(computedNode)).toBe(true)
    expect(constants.isValueProducerNode(effectNode)).toBe(false)
    expect(constants.isSignalNode({})).toBe(false)
    expect(constants.nodeForCallable({})).toBe(nil)

    stopEffect()
    stopScope()
    print("test passed\n")
end)

test("nested effect and scope mark their parent as having child effects", function()
    local stopOuter = reactive.effect(function()
        reactive.effect(function() end)
    end)
    local outerNode = constants.nodeForCallable(stopOuter)
    expect(constants.hasFlag(outerNode, constants.HAS_CHILD_EFFECT)).toBe(true)
    stopOuter()

    local stopScope = reactive.effectScope(function()
        reactive.effect(function() end)
    end)
    local scopeNode = constants.nodeForCallable(stopScope)
    expect(constants.hasFlag(scopeNode, constants.HAS_CHILD_EFFECT)).toBe(true)
    stopScope()

    print("test passed\n")
end)

test("graph validators accept valid dual-linked dependency edges", function()
    local subscriber = {
        __type = constants.COMPUTED_MARKER,
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.Mutable,
    }
    local dependencies = {
        { name = "a", __type = constants.SIGNAL_MARKER, subs = nil, subsTail = nil, flags = ReactiveFlags.Mutable },
        { name = "b", __type = constants.SIGNAL_MARKER, subs = nil, subsTail = nil, flags = ReactiveFlags.Mutable },
        { name = "c", __type = constants.SIGNAL_MARKER, subs = nil, subsTail = nil, flags = ReactiveFlags.Mutable },
    }

    for index, dependency in ipairs(dependencies) do
        graph.connect(dependency, subscriber, index)
        assertGraphOk(graph.validateDeps(subscriber))
        assertGraphOk(graph.validateSubs(dependency))
    end

    print("test passed\n")
end)

test("unlinkDepsReverse removes links in LIFO dependency order", function()
    local subscriber = {
        __type = constants.COMPUTED_MARKER,
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.Mutable,
    }
    local dependencies = {
        { name = "a", __type = constants.SIGNAL_MARKER, subs = nil, subsTail = nil, flags = ReactiveFlags.Mutable },
        { name = "b", __type = constants.SIGNAL_MARKER, subs = nil, subsTail = nil, flags = ReactiveFlags.Mutable },
        { name = "c", __type = constants.SIGNAL_MARKER, subs = nil, subsTail = nil, flags = ReactiveFlags.Mutable },
    }

    for index, dependency in ipairs(dependencies) do
        graph.connect(dependency, subscriber, index)
    end

    local removed = {}
    graph.unlinkDepsReverse(subscriber, function(dependency)
        removed[#removed + 1] = dependency.name
        return true
    end)

    expectArray(removed, { "c", "b", "a" })
    assertGraphOk(graph.validateDeps(subscriber))
    for _, dependency in ipairs(dependencies) do
        assertGraphOk(graph.validateSubs(dependency))
        expect(dependency.subs).toBe(nil)
        expect(dependency.subsTail).toBe(nil)
    end

    print("test passed\n")
end)

print("========== Refactored Module Tests Complete ==========\n")
