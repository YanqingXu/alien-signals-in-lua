--[[
primitives.lua

实现用户侧 API：signal、computed、effect、effectScope 和 trigger。这个模块只负责
创建具体节点与组织公开行为；依赖图、脏检查、调度等核心细节委托给其它模块。
]]

local bit = require("bit")

local constants = require("refactored.constants")
local graph = require("refactored.graph")
local scheduler = require("refactored.scheduler")
local engine = require("refactored.engine")

local ReactiveFlags = constants.ReactiveFlags

local primitives = {}

local stopEffectScopeNode

local function signalOperation(signalNode, ...)
    if select("#", ...) > 0 then
        local nextValue = select(1, ...)

        if nextValue ~= signalNode.pendingValue then
            signalNode.pendingValue = nextValue
            constants.setFlags(signalNode, bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty))

            if signalNode.subs then
                engine.propagateInvalidationFrom(signalNode.subs, engine.isInsideReactiveRun())
                if scheduler.getBatchDepth() == 0 then
                    scheduler.flush()
                end
            end
        end

        return nil
    end

    if constants.hasFlag(signalNode, ReactiveFlags.Dirty) then
        if engine.commitSignalValue(signalNode) and signalNode.subs then
            engine.markDirectSubscribersDirty(signalNode.subs)
        end
    end

    engine.trackDependencyRead(signalNode)
    return signalNode.currentValue
end

function primitives.signal(initialValue)
    local signalNode = {
        __type = constants.SIGNAL_MARKER,
        currentValue = initialValue,
        pendingValue = initialValue,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.Mutable,
    }

    return constants.bind(signalOperation, signalNode)
end

local function computedOperation(computedNode)
    if engine.computedNeedsRefresh(computedNode) then
        if engine.updateComputedValue(computedNode, true) and computedNode.subs then
            engine.markDirectSubscribersDirty(computedNode.subs)
        end
    elseif constants.isInactive(computedNode) then
        engine.runComputedForTheFirstTime(computedNode)
    end

    engine.trackDependencyRead(computedNode)
    return computedNode.value
end

function primitives.computed(getter)
    local computedNode = {
        __type = constants.COMPUTED_MARKER,
        value = nil,
        getter = getter,
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.None,
    }

    return constants.bind(computedOperation, computedNode)
end

local function stopEffectNode(effectNode)
    if effectNode.cleanup then
        engine.runCleanup(effectNode)
    end
    stopEffectScopeNode(effectNode)
end

function primitives.effect(fn)
    local effectNode = {
        __type = constants.EFFECT_MARKER,
        fn = fn,
        cleanup = nil,
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = bit.bor(ReactiveFlags.Watching, ReactiveFlags.RecursedCheck),
    }

    local parentSubscriber = engine.getActiveSub()
    if parentSubscriber then
        graph.connectDependencyToSubscriber(effectNode, parentSubscriber, 0)
    end

    local ok, cleanupOrError = engine.callWithSubscriber(effectNode, fn)

    constants.removeFlags(effectNode, ReactiveFlags.RecursedCheck)
    graph.removeStaleDependencyLinks(effectNode)

    if not ok then
        stopEffectScopeNode(effectNode)
        error(cleanupOrError)
    end

    effectNode.cleanup = cleanupOrError
    return constants.bind(stopEffectNode, effectNode)
end

stopEffectScopeNode = function(scopeNode)
    scopeNode.isQueued = false
    scopeNode.depsTail = nil
    constants.setFlags(scopeNode, ReactiveFlags.None)
    graph.removeStaleDependencyLinks(scopeNode)

    while scopeNode.subs do
        graph.removeDependencyLink(scopeNode.subs)
    end
end

function primitives.effectScope(fn)
    local scopeNode = {
        __type = constants.EFFECT_SCOPE_MARKER,
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.Mutable,
    }

    local parentSubscriber = engine.setActiveSub(scopeNode)
    if parentSubscriber then
        graph.connectDependencyToSubscriber(scopeNode, parentSubscriber, 0)
    end

    local ok, err = pcall(fn)
    engine.setActiveSub(parentSubscriber)

    if not ok then
        stopEffectScopeNode(scopeNode)
        error(err)
    end

    return constants.bind(stopEffectScopeNode, scopeNode)
end

--[[
trigger 用一个临时 subscriber 收集被访问的依赖源，然后对这些依赖源手动发起传播。
它适合 “signal 内部 table 被原地修改” 这种 setter 无法感知的场景。
]]
function primitives.trigger(fn)
    local temporarySubscriber = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.Watching,
    }

    local previousSubscriber = engine.setActiveSub(temporarySubscriber)
    local ok, err = pcall(fn)
    engine.setActiveSub(previousSubscriber)

    constants.setFlags(temporarySubscriber, ReactiveFlags.None)

    local link = temporarySubscriber.deps
    while link do
        local dependency = link.dep
        link = graph.removeDependencyLink(link, temporarySubscriber)

        if dependency.subs then
            engine.propagateInvalidationFrom(dependency.subs, engine.isInsideReactiveRun())
            engine.markDirectSubscribersDirty(dependency.subs)
        end
    end

    if scheduler.getBatchDepth() == 0 then
        scheduler.flush()
    end

    if not ok then
        error(err)
    end
end

function primitives.isSignal(value)
    local node = constants.nodeForCallable(value)
    return node ~= nil and node.__type == constants.SIGNAL_MARKER
end

function primitives.isComputed(value)
    local node = constants.nodeForCallable(value)
    return node ~= nil and node.__type == constants.COMPUTED_MARKER
end

function primitives.isEffect(value)
    local node = constants.nodeForCallable(value)
    return node ~= nil and node.__type == constants.EFFECT_MARKER
end

function primitives.isEffectScope(value)
    local node = constants.nodeForCallable(value)
    return node ~= nil and node.__type == constants.EFFECT_SCOPE_MARKER
end

engine.setStopInactiveNodeHandler(stopEffectScopeNode)

return primitives
