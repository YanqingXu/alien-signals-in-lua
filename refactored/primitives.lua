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
local HAS_CHILD_EFFECT = constants.HAS_CHILD_EFFECT

local primitives = {}

local stopScopeNode
local stopNode

-- 创建只有下游订阅者链的节点。
local function newDepNode(marker, flags)
    return {
        __type = marker,
        subs = nil,
        subsTail = nil,
        flags = flags,
    }
end

-- 创建同时拥有 deps/subs 两条链的节点。
local function newSubNode(marker, flags)
    local node = newDepNode(marker, flags)
    node.deps = nil
    node.depsTail = nil
    return node
end

-- 把子 effect/scope 连接到当前父节点。
local function linkChild(childNode, parentSubscriber)
    if not parentSubscriber then
        return
    end

    graph.connect(childNode, parentSubscriber, 0)
    constants.addFlags(parentSubscriber, HAS_CHILD_EFFECT)
end

-- signal 的 getter/setter 实现。
local function signalOp(signalNode, ...)
    if select("#", ...) > 0 then
        local nextValue = select(1, ...)

        if nextValue ~= signalNode.pendingValue then
            signalNode.pendingValue = nextValue
            constants.setFlags(signalNode, bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty))

            if signalNode.subs then
                engine.propagate(signalNode.subs, engine.isInsideReactiveRun())
                if scheduler.getBatchDepth() == 0 then
                    scheduler.flush()
                end
            end
        end

        return nil
    end

    if constants.hasFlag(signalNode, ReactiveFlags.Dirty) then
        if engine.commitSignalValue(signalNode) and signalNode.subs then
            engine.markDirty(signalNode.subs)
        end
    end

    engine.trackRead(signalNode)
    return signalNode.currentValue
end

-- 创建用户可调用的 signal。
function primitives.signal(initialValue)
    local signalNode = newDepNode(constants.SIGNAL_MARKER, ReactiveFlags.Mutable)
    signalNode.currentValue = initialValue
    signalNode.pendingValue = initialValue

    return constants.bind(signalOp, signalNode)
end

-- computed 的懒读取实现。
local function computedOp(computedNode)
    if engine.computedNeedsRefresh(computedNode) then
        if engine.updateComputed(computedNode, true) and computedNode.subs then
            engine.markDirty(computedNode.subs)
        end
    elseif constants.isInactive(computedNode) then
        engine.initComputed(computedNode)
    end

    engine.trackRead(computedNode)
    return computedNode.value
end

-- 创建用户可调用的 computed。
function primitives.computed(getter)
    local computedNode = newSubNode(constants.COMPUTED_MARKER, ReactiveFlags.None)
    computedNode.value = nil
    computedNode.getter = getter

    return constants.bind(computedOp, computedNode)
end

-- 停止 effect：先停子树，再执行自身 cleanup。
local function stopEffect(effectNode)
    stopScopeNode(effectNode)
    if effectNode.cleanup then
        engine.runCleanup(effectNode)
    end
    constants.setFlags(effectNode, ReactiveFlags.None)
end

-- 创建立即执行并自动追踪依赖的 effect。
function primitives.effect(fn)
    local effectNode = newSubNode(
        constants.EFFECT_MARKER,
        bit.bor(ReactiveFlags.Watching, ReactiveFlags.RecursedCheck)
    )
    effectNode.fn = fn
    effectNode.cleanup = nil

    local parentSubscriber = engine.getActiveSub()
    linkChild(effectNode, parentSubscriber)

    local ok, cleanupOrError = engine.callWithSub(effectNode, fn)

    constants.removeFlags(effectNode, ReactiveFlags.RecursedCheck)
    graph.unlinkStaleDeps(effectNode)

    if not ok then
        stopScopeNode(effectNode)
        error(cleanupOrError)
    end

    effectNode.cleanup = cleanupOrError
    return constants.bind(stopEffect, effectNode)
end

-- 停止 scope/effect 的共同清理流程。
stopScopeNode = function(scopeNode)
    scopeNode.isQueued = false
    constants.setFlags(scopeNode, ReactiveFlags.None)
    graph.unlinkDepsReverse(scopeNode)

    while scopeNode.subs do
        graph.unlink(scopeNode.subs)
    end
end

-- 按节点类型分发失活停止逻辑。
stopNode = function(node)
    if constants.isEffectNode(node) then
        stopEffect(node)
        return
    end

    stopScopeNode(node)
end

-- 创建可批量停止子 effect 的 scope。
function primitives.effectScope(fn)
    local scopeNode = newSubNode(constants.EFFECT_SCOPE_MARKER, ReactiveFlags.Mutable)

    local parentSubscriber = engine.setActiveSub(scopeNode)
    linkChild(scopeNode, parentSubscriber)

    local ok, err = pcall(fn)
    engine.setActiveSub(parentSubscriber)

    if not ok then
        stopScopeNode(scopeNode)
        error(err)
    end

    return constants.bind(stopScopeNode, scopeNode)
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
        link = graph.unlink(link, temporarySubscriber)

        if dependency.subs then
            engine.propagate(dependency.subs, engine.isInsideReactiveRun())
            engine.markDirty(dependency.subs)
        end
    end

    if scheduler.getBatchDepth() == 0 then
        scheduler.flush()
    end

    if not ok then
        error(err)
    end
end

-- 判断 callable 是否是 signal。
function primitives.isSignal(value)
    local node = constants.nodeForCallable(value)
    return constants.isSignalNode(node)
end

-- 判断 callable 是否是 computed。
function primitives.isComputed(value)
    local node = constants.nodeForCallable(value)
    return constants.isComputedNode(node)
end

-- 判断 callable 是否是 effect stop 函数。
function primitives.isEffect(value)
    local node = constants.nodeForCallable(value)
    return constants.isEffectNode(node)
end

-- 判断 callable 是否是 effectScope stop 函数。
function primitives.isEffectScope(value)
    local node = constants.nodeForCallable(value)
    return constants.isEffectScopeNode(node)
end

engine.setStopHandler(stopNode)

return primitives
