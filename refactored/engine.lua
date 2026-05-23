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

local activeSubscriber = nil
local runDepth = 0
local trackingVersion = 0
local stopInactiveNode = function() end

function engine.setStopInactiveNodeHandler(handler)
    stopInactiveNode = handler or function() end
end

function engine.setActiveSub(subscriber)
    local previousSubscriber = activeSubscriber
    activeSubscriber = subscriber
    return previousSubscriber
end

function engine.getActiveSub()
    return activeSubscriber
end

function engine.isInsideReactiveRun()
    return runDepth ~= 0
end

function engine.beginFreshTracking(subscriber, baseFlags, shouldAdvanceVersion)
    if shouldAdvanceVersion then
        trackingVersion = trackingVersion + 1
    end

    subscriber.depsTail = nil
    constants.setFlags(subscriber, bit.bor(baseFlags, ReactiveFlags.RecursedCheck))
end

function engine.finishFreshTracking(subscriber)
    constants.removeFlags(subscriber, ReactiveFlags.RecursedCheck)
    graph.removeStaleDependencyLinks(subscriber)
end

function engine.callWithSubscriber(subscriber, fn)
    local previousSubscriber = engine.setActiveSub(subscriber)
    runDepth = runDepth + 1
    local ok, result = pcall(fn)
    runDepth = runDepth - 1
    activeSubscriber = previousSubscriber
    return ok, result
end

function engine.trackDependencyRead(dependency)
    if activeSubscriber then
        graph.connectDependencyToSubscriber(dependency, activeSubscriber, trackingVersion)
    end
end

local function decidePropagationForSubscriber(subscriber, sourceLink, isWriteInsideReactiveRun)
    local flags = subscriber.flags or ReactiveFlags.None
    local isQueuedEffect = subscriber.isQueued == true

    if not isQueuedEffect and not constants.hasAnyFlagValue(flags, constants.TRACKABLE_FLAGS) then
        return ReactiveFlags.None
    end

    if not constants.hasAnyFlagValue(flags, constants.PROPAGATION_GUARD_FLAGS) then
        constants.setFlags(subscriber, bit.bor(flags, ReactiveFlags.Pending))
        if isWriteInsideReactiveRun then
            constants.addFlags(subscriber, ReactiveFlags.Recursed)
        end
        return flags
    end

    if not constants.hasAnyFlagValue(flags, constants.RECURSION_FLAGS) then
        return ReactiveFlags.None
    end

    if not constants.hasFlagValue(flags, ReactiveFlags.RecursedCheck) then
        constants.setFlags(
            subscriber,
            bit.bor(bit.band(flags, bit.bnot(ReactiveFlags.Recursed)), ReactiveFlags.Pending)
        )
        return flags
    end

    if not constants.hasAnyFlagValue(flags, constants.DIRTY_OR_PENDING_FLAGS)
        and graph.linkIsInsideCurrentDependencyPrefix(sourceLink, subscriber)
    then
        constants.setFlags(subscriber, bit.bor(flags, ReactiveFlags.Recursed, ReactiveFlags.Pending))
        return bit.band(flags, ReactiveFlags.Mutable)
    end

    return ReactiveFlags.None
end

local function processOneInvalidatedSubscriber(link, isWriteInsideReactiveRun)
    local subscriber = link.sub
    local propagationFlags = decidePropagationForSubscriber(
        subscriber,
        link,
        isWriteInsideReactiveRun
    )

    if constants.hasFlagValue(propagationFlags, ReactiveFlags.Watching) then
        scheduler.enqueueEffect(subscriber)
    end

    if constants.hasFlagValue(propagationFlags, ReactiveFlags.Mutable) then
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
function engine.propagateInvalidationFrom(firstSubscriberLink, isWriteInsideReactiveRun)
    if not firstSubscriberLink then
        return
    end

    local currentLink = firstSubscriberLink
    local nextLink = currentLink.nextSub
    local stack = nil

    while currentLink do
        local childSubscriberLink = processOneInvalidatedSubscriber(
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

function engine.markDirectSubscribersDirty(firstSubscriberLink)
    local link = firstSubscriberLink

    while link do
        local subscriber = link.sub
        local flags = subscriber.flags or ReactiveFlags.None

        if bit.band(flags, constants.DIRTY_OR_PENDING_FLAGS) == ReactiveFlags.Pending then
            constants.setFlags(subscriber, bit.bor(flags, ReactiveFlags.Dirty))

            if constants.hasFlagValue(flags, ReactiveFlags.Watching)
                and not constants.hasFlagValue(flags, ReactiveFlags.RecursedCheck)
            then
                scheduler.enqueueEffect(subscriber)
            end
        end

        link = link.nextSub
    end
end

function engine.commitSignalValue(signalNode)
    constants.setFlags(signalNode, ReactiveFlags.Mutable)

    if signalNode.currentValue == signalNode.pendingValue then
        return false
    end

    signalNode.currentValue = signalNode.pendingValue
    return true
end

local function isSignalOrComputedNode(node)
    return node.__type == constants.SIGNAL_MARKER
        or node.__type == constants.COMPUTED_MARKER
        or node.getter ~= nil
end

local function disposeChildDependencyLinks(subscriber)
    graph.removeDependencyLinksInReverse(subscriber, function(dependency)
        return not isSignalOrComputedNode(dependency)
    end)
end

function engine.updateComputedValue(computedNode, shouldPassOldValue)
    local oldValue = computedNode.value

    if constants.hasFlag(computedNode, HAS_CHILD_EFFECT) then
        disposeChildDependencyLinks(computedNode)
    end

    engine.beginFreshTracking(computedNode, ReactiveFlags.Mutable, true)

    local ok, newValue = engine.callWithSubscriber(computedNode, function()
        if shouldPassOldValue then
            return computedNode.getter(oldValue)
        end
        return computedNode.getter()
    end)

    engine.finishFreshTracking(computedNode)

    if not ok then
        constants.addFlags(computedNode, ReactiveFlags.Dirty)
        error(newValue)
    end

    computedNode.value = newValue
    return newValue ~= oldValue
end

function engine.updateReactiveValue(node)
    if node.__type == constants.COMPUTED_MARKER or node.getter then
        return engine.updateComputedValue(node, true)
    end

    if node.__type == constants.SIGNAL_MARKER then
        return engine.commitSignalValue(node)
    end

    constants.setFlags(node, ReactiveFlags.Mutable)
    return true
end

local function markDownstreamSubscribersDirtyIfNeeded(firstSubscriberLink)
    if firstSubscriberLink and firstSubscriberLink.nextSub then
        engine.markDirectSubscribersDirty(firstSubscriberLink)
    end
end

local function updateDependencyAndReportChange(dependency, subscriber)
    local dependencySubscribers = dependency.subs

    if not engine.updateReactiveValue(dependency) then
        return false, false
    end

    markDownstreamSubscribersDirtyIfNeeded(dependencySubscribers)
    return true, not constants.isInactive(subscriber)
end

local function pendingDependencyReallyChanged(dependency)
    if engine.checkDependencyChainForChanges(dependency.deps, dependency) then
        return true
    end

    constants.removeFlags(dependency, ReactiveFlags.Pending)
    return false
end

local function checkSingleDependencyForChanges(dependency, subscriber)
    if constants.isMutableAndDirty(dependency) then
        return updateDependencyAndReportChange(dependency, subscriber)
    end

    if constants.isMutableAndPending(dependency) then
        if pendingDependencyReallyChanged(dependency) then
            return updateDependencyAndReportChange(dependency, subscriber)
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
function engine.checkDependencyChainForChanges(firstDependencyLink, subscriber)
    local link = firstDependencyLink

    while link do
        if constants.hasFlag(subscriber, ReactiveFlags.Dirty) then
            return not constants.isInactive(subscriber)
        end

        -- shouldReturn 表示已经确认当前链路的答案，dependencyChanged 是要返回的结果。
        local shouldReturn, dependencyChanged = checkSingleDependencyForChanges(
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

function engine.computedNeedsRefresh(computedNode)
    if constants.hasFlag(computedNode, ReactiveFlags.Dirty) then
        return true
    end

    if not constants.hasFlag(computedNode, ReactiveFlags.Pending) then
        return false
    end

    if engine.checkDependencyChainForChanges(computedNode.deps, computedNode) then
        return true
    end

    constants.removeFlags(computedNode, ReactiveFlags.Pending)
    return false
end

function engine.runComputedForTheFirstTime(computedNode)
    engine.beginFreshTracking(computedNode, ReactiveFlags.Mutable, false)

    local ok, initialValue = engine.callWithSubscriber(computedNode, function()
        return computedNode.getter()
    end)

    engine.finishFreshTracking(computedNode)

    if not ok then
        constants.addFlags(computedNode, ReactiveFlags.Dirty)
        error(initialValue)
    end

    computedNode.value = initialValue
end

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

function engine.runEffectBody(effectNode)
    engine.beginFreshTracking(effectNode, ReactiveFlags.Watching, true)

    local ok, cleanupOrError = engine.callWithSubscriber(effectNode, effectNode.fn)

    engine.finishFreshTracking(effectNode)

    if not ok then
        error(cleanupOrError)
    end

    effectNode.cleanup = cleanupOrError
end

function engine.effectNeedsToRun(effectNode)
    if constants.hasFlag(effectNode, ReactiveFlags.Dirty) then
        return true
    end

    if not constants.hasFlag(effectNode, ReactiveFlags.Pending) then
        return false
    end

    return engine.checkDependencyChainForChanges(effectNode.deps, effectNode)
end

function engine.runScheduledEffect(effectNode)
    effectNode.isQueued = false
    local flagsBeforeRun = effectNode.flags or ReactiveFlags.None

    if not engine.effectNeedsToRun(effectNode) then
        if not constants.isInactive(effectNode) then
            constants.setFlags(
                effectNode,
                bit.bor(ReactiveFlags.Watching, bit.band(flagsBeforeRun, HAS_CHILD_EFFECT))
            )
        end
        return
    end

    if constants.hasFlag(effectNode, HAS_CHILD_EFFECT) then
        disposeChildDependencyLinks(effectNode)
    end

    if effectNode.cleanup then
        engine.runCleanup(effectNode)
        if constants.isInactive(effectNode) then
            return
        end
    end

    engine.runEffectBody(effectNode)
end

function engine.handleNodeWithoutSubscribers(node)
    if not constants.isMutableNode(node) then
        stopInactiveNode(node)
        return
    end

    if node.depsTail then
        constants.setFlags(node, bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty))
        graph.removeDependencyLinksInReverse(node)
    end
end

scheduler.setRunEffectHandler(engine.runScheduledEffect)
graph.setUnwatchedHandler(engine.handleNodeWithoutSubscribers)

return engine
