--[[
primitives.lua

模块概述：
用户侧响应式原语模块。它把底层算法与图结构包装成 signal、computed、effect、
effectScope、trigger 等对外 API，并维持与单文件版本一致的公开调用方式。

设计动机与职责：
用户需要的是简单稳定的原语，而不是直接操作 Link、ReactiveFlags 或 trackingVersion。
primitives.lua 的职责是创建对应节点、组织 getter/setter 或 stop callable 的外部行为，
并把传播、脏值检查、调度与回收逻辑分别委托给 engine、graph 与 scheduler，使 API 层
保持薄而清晰，同时承担 effect 父子关系、scope 生命周期与手动 trigger 这类组装职责。

协作关系：
它直接依赖 constants、graph、scheduler、engine 与 tracer，最终由 init.lua 聚合导出给用户。
同时它会向 engine 注入 stop handler，让算法层在节点失去订阅者时能够回调到这里执行
effect 和 scope 的实际停止与 cleanup 流程。

核心概念：
本模块围绕各类节点构造、callable 与 node 的绑定关系、signal 的读写闭包、computed 的
懒读取、effect 的 cleanup、effectScope 的子树回收，以及 trigger 使用的临时 subscriber
等概念展开；节点上附带的 customLabel 也在这一层被写入，供 tracing 和调试使用。
]]

local bit = require("bit")

local constants = require("refactored.constants")
local graph = require("refactored.graph")
local scheduler = require("refactored.scheduler")
local engine = require("refactored.engine")
local tracer = require("refactored.tracer")

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
            local flagsBefore = signalNode.flags
            local previousValue = signalNode.pendingValue
            signalNode.pendingValue = nextValue
            constants.setFlags(signalNode, bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty))
            tracer.emit("signal:set", signalNode, {
                from = tracer.value(previousValue),
                to = tracer.value(nextValue),
                changed = true,
                flagsBefore = flagsBefore,
                flagsAfter = signalNode.flags,
            })

            if signalNode.subs then
                engine.propagate(signalNode.subs, engine.isInsideReactiveRun())
                if scheduler.getBatchDepth() == 0 then
                    scheduler.flush()
                end
            end
        else
            tracer.emit("signal:set-skip", signalNode, {
                value = tracer.value(nextValue),
                changed = false,
                reason = "same-pending-value",
            })
        end

        return nil
    end

    if constants.hasFlag(signalNode, ReactiveFlags.Dirty) then
        if engine.commitSignalValue(signalNode) and signalNode.subs then
            engine.markDirty(signalNode.subs)
        end
    end

    tracer.emit("signal:read", signalNode, {
        value = tracer.value(signalNode.currentValue),
    })
    engine.trackRead(signalNode)
    return signalNode.currentValue
end

-- 创建用户可调用的 signal。
function primitives.signal(initialValue, label)
    local signalNode = newDepNode(constants.SIGNAL_MARKER, ReactiveFlags.Mutable)
    signalNode.currentValue = initialValue
    signalNode.pendingValue = initialValue
    signalNode.customLabel = label

    tracer.emit("node:create", signalNode, {
        value = tracer.value(initialValue),
    })

    return constants.bind(signalOp, signalNode)
end

-- computed 的懒读取实现。
local function computedOp(computedNode)
    tracer.emit("computed:read", computedNode)

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
function primitives.computed(getter, label)
    local computedNode = newSubNode(constants.COMPUTED_MARKER, ReactiveFlags.None)
    computedNode.value = nil
    computedNode.getter = getter
    computedNode.customLabel = label

    tracer.emit("node:create", computedNode)

    return constants.bind(computedOp, computedNode)
end

-- 停止 effect：先停子树，再执行自身 cleanup。
local function stopEffect(effectNode)
    tracer.enter("effect:stop", effectNode)
    local ok, err = pcall(function()
        stopScopeNode(effectNode)
        if effectNode.cleanup then
            engine.runCleanup(effectNode)
        end
        constants.setFlags(effectNode, ReactiveFlags.None)
    end)
    tracer.leave("effect:stop", effectNode, {
        result = ok and "ok" or "error",
        flagsAfter = effectNode.flags,
    })

    if not ok then
        error(err)
    end
end

-- 创建立即执行并自动追踪依赖的 effect。
function primitives.effect(fn, label)
    local effectNode = newSubNode(
        constants.EFFECT_MARKER,
        bit.bor(ReactiveFlags.Watching, ReactiveFlags.RecursedCheck)
    )
    effectNode.fn = fn
    effectNode.cleanup = nil
    effectNode.customLabel = label

    tracer.emit("node:create", effectNode)

    local parentSubscriber = engine.getActiveSub()
    linkChild(effectNode, parentSubscriber)

    tracer.enter("effect:init", effectNode)
    local ok, cleanupOrError = engine.callWithSub(effectNode, fn)

    constants.removeFlags(effectNode, ReactiveFlags.RecursedCheck)
    graph.unlinkStaleDeps(effectNode)

    if not ok then
        stopScopeNode(effectNode)
        tracer.leave("effect:init", effectNode, {
            result = "error",
            flagsAfter = effectNode.flags,
        })
        error(cleanupOrError)
    end

    effectNode.cleanup = cleanupOrError
    tracer.leave("effect:init", effectNode, {
        result = "ok",
        flagsAfter = effectNode.flags,
    })
    return constants.bind(stopEffect, effectNode)
end

-- 停止 scope/effect 的共同清理流程。
stopScopeNode = function(scopeNode)
    tracer.emit("scope:stop", scopeNode)
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

    tracer.emit("node:create", scopeNode)

    local parentSubscriber = engine.setActiveSub(scopeNode)
    linkChild(scopeNode, parentSubscriber)

    tracer.enter("scope:init", scopeNode)
    local ok, err = pcall(fn)
    engine.setActiveSub(parentSubscriber)

    if not ok then
        stopScopeNode(scopeNode)
        tracer.leave("scope:init", scopeNode, {
            result = "error",
            flagsAfter = scopeNode.flags,
        })
        error(err)
    end

    tracer.leave("scope:init", scopeNode, {
        result = "ok",
        flagsAfter = scopeNode.flags,
    })
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

    tracer.enter("trigger", temporarySubscriber)
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
        tracer.leave("trigger", temporarySubscriber, {
            result = "error",
        })
        error(err)
    end

    tracer.leave("trigger", temporarySubscriber, {
        result = "ok",
    })
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
