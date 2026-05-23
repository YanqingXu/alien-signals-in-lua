--[[
engine.lua

响应式系统的核心算法层。这里负责依赖追踪、失效传播和脏值检查，但不创建用户
直接调用的 signal/computed/effect 函数；这些原语放在 primitives.lua。
]]

local bit = require("bit")

local constants = require("refactored.constants")
local graph = require("refactored.graph")
local scheduler = require("refactored.scheduler")

local ReactiveFlags = constants.ReactiveFlags
local HAS_CHILD_EFFECT = constants.HAS_CHILD_EFFECT

local engine = {}

local PropagationAction = {
    None = 0,
    ScheduleEffect = 1,
    VisitChildren = 2,
}

local activeSubscriber = nil
local runDepth = 0
local trackingVersion = 0
local stopNodeHandler = function() end

-- 把当前 flags 翻译成传播动作。
local function actionFromFlags(flags)
    local action = PropagationAction.None

    if constants.hasBit(flags, ReactiveFlags.Watching) then
        action = bit.bor(action, PropagationAction.ScheduleEffect)
    end

    if constants.hasBit(flags, ReactiveFlags.Mutable) then
        action = bit.bor(action, PropagationAction.VisitChildren)
    end

    return action
end

-- 判断动作集合是否包含某个动作。
local function actionIncludes(action, expectedAction)
    return bit.band(action, expectedAction) ~= 0
end

-- 注入节点失活时的停止逻辑。
function engine.setStopHandler(handler)
    stopNodeHandler = handler or function() end
end

-- 切换当前正在收集依赖的 subscriber。
function engine.setActiveSub(subscriber)
    local previousSubscriber = activeSubscriber
    activeSubscriber = subscriber
    return previousSubscriber
end

-- 读取当前 active subscriber。
function engine.getActiveSub()
    return activeSubscriber
end

-- 判断当前是否处在 effect/computed 执行栈中。
function engine.isInsideReactiveRun()
    return runDepth ~= 0
end

-- 开始一轮新的依赖追踪。
function engine.beginTrack(subscriber, baseFlags, shouldAdvanceVersion)
    if shouldAdvanceVersion then
        trackingVersion = trackingVersion + 1
    end

    subscriber.depsTail = nil
    constants.setFlags(subscriber, bit.bor(baseFlags, ReactiveFlags.RecursedCheck))
end

-- 收尾追踪并清理旧依赖。
function engine.finishTrack(subscriber)
    constants.removeFlags(subscriber, ReactiveFlags.RecursedCheck)
    graph.unlinkStaleDeps(subscriber)
end

-- 在指定 subscriber 上下文中安全执行函数。
function engine.callWithSub(subscriber, fn)
    local previousSubscriber = engine.setActiveSub(subscriber)
    runDepth = runDepth + 1
    local ok, result = pcall(fn)
    runDepth = runDepth - 1
    activeSubscriber = previousSubscriber
    return ok, result
end

-- 把一次依赖读取连到当前 active subscriber。
function engine.trackRead(dependency)
    if activeSubscriber then
        graph.connect(dependency, activeSubscriber, trackingVersion)
    end
end

-- 决定一个 subscriber 在传播中要执行哪些动作。
local function decidePropagation(subscriber, sourceLink, isWriteInsideReactiveRun)
    local flags = subscriber.flags or ReactiveFlags.None
    local isQueuedEffect = subscriber.isQueued == true

    if not isQueuedEffect and not constants.hasAnyBits(flags, constants.TRACKABLE_FLAGS) then
        return PropagationAction.None
    end

    if not constants.hasAnyBits(flags, constants.PROPAGATION_GUARD_FLAGS) then
        constants.setFlags(subscriber, bit.bor(flags, ReactiveFlags.Pending))
        if isWriteInsideReactiveRun then
            constants.addFlags(subscriber, ReactiveFlags.Recursed)
        end
        return actionFromFlags(flags)
    end

    if not constants.hasAnyBits(flags, constants.RECURSION_FLAGS) then
        return PropagationAction.None
    end

    if not constants.hasBit(flags, ReactiveFlags.RecursedCheck) then
        constants.setFlags(
            subscriber,
            bit.bor(bit.band(flags, bit.bnot(ReactiveFlags.Recursed)), ReactiveFlags.Pending)
        )
        return actionFromFlags(flags)
    end

    if not constants.hasAnyBits(flags, constants.DIRTY_OR_PENDING_FLAGS)
        and graph.isLinkInCurrentDeps(sourceLink, subscriber)
    then
        constants.setFlags(subscriber, bit.bor(flags, ReactiveFlags.Recursed, ReactiveFlags.Pending))
        return actionFromFlags(bit.band(flags, ReactiveFlags.Mutable))
    end

    return PropagationAction.None
end

-- 处理一条被失效传播触达的 Link。
local function processInvalidated(link, isWriteInsideReactiveRun)
    local subscriber = link.sub
    local propagationAction = decidePropagation(
        subscriber,
        link,
        isWriteInsideReactiveRun
    )

    if actionIncludes(propagationAction, PropagationAction.ScheduleEffect) then
        scheduler.enqueueEffect(subscriber)
    end

    if actionIncludes(propagationAction, PropagationAction.VisitChildren) then
        return subscriber.subs
    end

    return nil
end

--[[
传播阶段只做“标记”和“入队”，不做昂贵重算。

signal 写入后，从它的 subs 链开始向下游走：
- effect 被放入调度队列。
- computed 被标记为 pending，并继续把 pending 传播给更下游的订阅者。

真正是否需要重算，留到 computed 被读取或 effect 被刷新时再由脏值检查确认。
]]
function engine.propagate(firstSubscriberLink, isWriteInsideReactiveRun)
    if not firstSubscriberLink then
        return
    end

    local currentLink = firstSubscriberLink
    local nextLink = currentLink.nextSub
    local stack = nil

    while currentLink do
        local childSubscriberLink = processInvalidated(
            currentLink,
            isWriteInsideReactiveRun
        )

        if childSubscriberLink then
            currentLink = childSubscriberLink

            local childNextLink = childSubscriberLink.nextSub
            if childNextLink then
                stack = { value = nextLink, previous = stack }
                nextLink = childNextLink
            end
        else
            currentLink = nextLink
            if currentLink then
                nextLink = currentLink.nextSub
            else
                while stack and not currentLink do
                    currentLink = stack.value
                    stack = stack.previous
                end
                if currentLink then
                    nextLink = currentLink.nextSub
                end
            end
        end
    end
end

-- 把直接下游从 Pending 升级为 Dirty。
function engine.markDirty(firstSubscriberLink)
    local link = firstSubscriberLink

    while link do
        local subscriber = link.sub
        local flags = subscriber.flags or ReactiveFlags.None

        if bit.band(flags, constants.DIRTY_OR_PENDING_FLAGS) == ReactiveFlags.Pending then
            constants.setFlags(subscriber, bit.bor(flags, ReactiveFlags.Dirty))

            if constants.hasBit(flags, ReactiveFlags.Watching)
                and not constants.hasBit(flags, ReactiveFlags.RecursedCheck)
            then
                scheduler.enqueueEffect(subscriber)
            end
        end

        link = link.nextSub
    end
end

-- 提交 signal 的 pendingValue。
function engine.commitSignalValue(signalNode)
    constants.setFlags(signalNode, ReactiveFlags.Mutable)

    if signalNode.currentValue == signalNode.pendingValue then
        return false
    end

    signalNode.currentValue = signalNode.pendingValue
    return true
end

-- 释放 subscriber 下由 effect/scope 形成的子树。
local function unlinkChildDeps(subscriber)
    graph.unlinkDepsReverse(subscriber, function(dependency)
        return not constants.isValueProducerNode(dependency)
    end)
end

-- 重新计算 computed，并返回值是否真的变化。
function engine.updateComputed(computedNode, shouldPassOldValue)
    local oldValue = computedNode.value

    if constants.hasFlag(computedNode, HAS_CHILD_EFFECT) then
        unlinkChildDeps(computedNode)
    end

    engine.beginTrack(computedNode, ReactiveFlags.Mutable, true)

    local ok, newValue = engine.callWithSub(computedNode, function()
        if shouldPassOldValue then
            return computedNode.getter(oldValue)
        end
        return computedNode.getter()
    end)

    engine.finishTrack(computedNode)

    if not ok then
        constants.addFlags(computedNode, ReactiveFlags.Dirty)
        error(newValue)
    end

    computedNode.value = newValue
    return newValue ~= oldValue
end

-- 根据节点类型提交 signal 或刷新 computed。
function engine.updateNode(node)
    if constants.isComputedNode(node) then
        return engine.updateComputed(node, true)
    end

    if constants.isSignalNode(node) then
        return engine.commitSignalValue(node)
    end

    constants.setFlags(node, ReactiveFlags.Mutable)
    return true
end

-- 当 dependency 有多个下游时，同步升级脏标记。
local function markDirtyMaybe(firstSubscriberLink)
    if firstSubscriberLink and firstSubscriberLink.nextSub then
        engine.markDirty(firstSubscriberLink)
    end
end

-- 更新依赖，并把结果转换成 checkDeps 的返回值。
local function updateDepAndReport(dependency, subscriber)
    local dependencySubscribers = dependency.subs

    if not engine.updateNode(dependency) then
        return false, false
    end

    markDirtyMaybe(dependencySubscribers)
    return true, not constants.isInactive(subscriber)
end

-- 递归确认 Pending 依赖是否真的变化。
local function pendingDepChanged(dependency)
    if engine.checkDeps(dependency.deps, dependency) then
        return true
    end

    constants.removeFlags(dependency, ReactiveFlags.Pending)
    return false
end

-- 检查单个依赖是否会让 subscriber 需要刷新。
local function checkDep(dependency, subscriber)
    if constants.isDirtyValue(dependency) then
        return updateDepAndReport(dependency, subscriber)
    end

    if constants.isPendingValue(dependency) then
        if pendingDepChanged(dependency) then
            return updateDepAndReport(dependency, subscriber)
        end
    end

    return false, false
end

--[[
脏值检查：把“可能变了”还原成“真的变了 / 其实没变”。

pending 是写入传播时留下的低成本标记。检查时沿 subscriber.deps 逐个确认：
- 上游 signal dirty：提交 pendingValue；值没变则不继续污染下游。
- 上游 computed dirty：重新计算；只有返回值变了才继续确认下游。
- 上游 computed pending：递归检查它自己的 deps。

这让 “先写成新值，再写回旧值” 不会触发无意义的 computed 重算。
]]
function engine.checkDeps(firstDependencyLink, subscriber)
    local link = firstDependencyLink

    while link do
        if constants.hasFlag(subscriber, ReactiveFlags.Dirty) then
            return not constants.isInactive(subscriber)
        end

        -- shouldReturn 表示已经确认当前链路的答案，dependencyChanged 是要返回的结果。
        local shouldReturn, dependencyChanged = checkDep(
            link.dep,
            subscriber
        )
        if shouldReturn then
            return dependencyChanged
        end

        link = link.nextDep
    end

    return false
end

-- 判断 computed 是否需要刷新。
function engine.computedNeedsRefresh(computedNode)
    if constants.hasFlag(computedNode, ReactiveFlags.Dirty) then
        return true
    end

    if not constants.hasFlag(computedNode, ReactiveFlags.Pending) then
        return false
    end

    if engine.checkDeps(computedNode.deps, computedNode) then
        return true
    end

    constants.removeFlags(computedNode, ReactiveFlags.Pending)
    return false
end

-- 首次激活 lazy computed。
function engine.initComputed(computedNode)
    engine.beginTrack(computedNode, ReactiveFlags.Mutable, false)

    local ok, initialValue = engine.callWithSub(computedNode, function()
        return computedNode.getter()
    end)

    engine.finishTrack(computedNode)

    if not ok then
        constants.addFlags(computedNode, ReactiveFlags.Dirty)
        error(initialValue)
    end

    computedNode.value = initialValue
end

-- 执行并清空 effect cleanup。
function engine.runCleanup(effectNode)
    local cleanup = effectNode.cleanup
    effectNode.cleanup = nil

    if type(cleanup) ~= "function" then
        return
    end

    local previousSubscriber = activeSubscriber
    activeSubscriber = nil
    local ok, err = pcall(cleanup)
    activeSubscriber = previousSubscriber

    if not ok then
        error(err)
    end
end

-- 执行 effect 主体并重建依赖。
function engine.runEffectBody(effectNode)
    engine.beginTrack(effectNode, ReactiveFlags.Watching, true)

    local ok, cleanupOrError = engine.callWithSub(effectNode, effectNode.fn)

    engine.finishTrack(effectNode)

    if not ok then
        error(cleanupOrError)
    end

    effectNode.cleanup = cleanupOrError
end

-- 判断入队 effect 是否真的需要运行。
function engine.shouldRunEffect(effectNode)
    if constants.hasFlag(effectNode, ReactiveFlags.Dirty) then
        return true
    end

    if not constants.hasFlag(effectNode, ReactiveFlags.Pending) then
        return false
    end

    return engine.checkDeps(effectNode.deps, effectNode)
end

-- scheduler 调用的 effect 执行入口。
function engine.runQueuedEffect(effectNode)
    effectNode.isQueued = false
    local flagsBeforeRun = effectNode.flags or ReactiveFlags.None

    if not engine.shouldRunEffect(effectNode) then
        if not constants.isInactive(effectNode) then
            constants.setFlags(
                effectNode,
                bit.bor(ReactiveFlags.Watching, bit.band(flagsBeforeRun, HAS_CHILD_EFFECT))
            )
        end
        return
    end

    if constants.hasFlag(effectNode, HAS_CHILD_EFFECT) then
        unlinkChildDeps(effectNode)
    end

    if effectNode.cleanup then
        engine.runCleanup(effectNode)
        if constants.isInactive(effectNode) then
            return
        end
    end

    engine.runEffectBody(effectNode)
end

-- 处理依赖源失去最后一个订阅者的情况。
function engine.handleUnwatched(node)
    if not constants.isMutableNode(node) then
        stopNodeHandler(node)
        return
    end

    if node.depsTail then
        constants.setFlags(node, bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty))
        graph.unlinkDepsReverse(node)
    end
end

scheduler.setRunEffectHandler(engine.runQueuedEffect)
graph.setUnwatchedHandler(engine.handleUnwatched)

return engine
