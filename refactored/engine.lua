--[[
engine.lua

模块概述：
响应式核心算法模块。它负责 active subscriber 管理、依赖追踪、失效传播、脏值检查、
computed 重算、effect 重跑与无订阅节点的回收，是整套运行时的决策中心。

设计动机与职责：
图结构维护、调度、用户 API 与 tracing 都需要共享同一套“谁正在读、谁可能变脏、
谁现在应该重算”的算法语义。engine.lua 把这些高频决策集中起来，通过 PUSH 阶段的
传播标记和 PULL 阶段的脏值确认，将 signal 写入、computed 惰性求值和 effect 刷新
统一到一套状态机中，同时避免 graph 与 scheduler 承担业务语义。

协作关系：
它直接依赖 constants、graph、scheduler 与 tracer，并向 graph 注入无人订阅时的回收回调，
向 scheduler 注入 runEffectHandler。primitives 依赖它实现 signal/computed/effect 的核心行为，
并通过 stop handler 反向补齐 effect/scope 的停止流程。

核心概念：
本模块处理的关键概念包括 activeSubscriber、runDepth、trackingVersion、Pending/Dirty/
RecursedCheck/Recursed 等状态位，以及 beginTrack、trackRead、propagate、checkDeps、
updateComputed、runQueuedEffect 这类围绕追踪版本与脏值状态机展开的核心算子。
]]

local bit = require("bit")

local constants = require("refactored.constants")
local graph = require("refactored.graph")
local scheduler = require("refactored.scheduler")
local tracer = require("refactored.tracer")

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

-- 把传播动作格式化成 trace 可读文本。
local function actionText(action)
    if action == PropagationAction.None then
        return "None"
    end

    local actions = {}

    if actionIncludes(action, PropagationAction.ScheduleEffect) then
        actions[#actions + 1] = "ScheduleEffect"
    end

    if actionIncludes(action, PropagationAction.VisitChildren) then
        actions[#actions + 1] = "VisitChildren"
    end

    return table.concat(actions, "|")
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

    local flagsBefore = subscriber.flags
    subscriber.depsTail = nil
    constants.setFlags(subscriber, bit.bor(baseFlags, ReactiveFlags.RecursedCheck))

    tracer.emit("track:begin", subscriber, {
        flagsBefore = flagsBefore,
        flagsAfter = subscriber.flags,
        reason = shouldAdvanceVersion and "advance-version" or "keep-version",
    })
end

-- 收尾追踪并清理旧依赖。
function engine.finishTrack(subscriber)
    local flagsBefore = subscriber.flags
    constants.removeFlags(subscriber, ReactiveFlags.RecursedCheck)
    graph.unlinkStaleDeps(subscriber)

    tracer.emit("track:end", subscriber, {
        flagsBefore = flagsBefore,
        flagsAfter = subscriber.flags,
    })
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
        tracer.emit("track:read", dependency, {
            dep = dependency,
            sub = activeSubscriber,
        })
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
    local flagsBefore = subscriber.flags
    local propagationAction = decidePropagation(
        subscriber,
        link,
        isWriteInsideReactiveRun
    )

    tracer.emit("propagate:visit", subscriber, {
        link = link,
        dep = link.dep,
        sub = subscriber,
        action = actionText(propagationAction),
        flagsBefore = flagsBefore,
        flagsAfter = subscriber.flags,
    })

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

    tracer.enter("propagate", firstSubscriberLink.dep, {
        link = firstSubscriberLink,
        dep = firstSubscriberLink.dep,
        reason = isWriteInsideReactiveRun and "inside-reactive-run" or "outside-reactive-run",
    })

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

    tracer.leave("propagate", firstSubscriberLink.dep, {
        link = firstSubscriberLink,
        dep = firstSubscriberLink.dep,
    })
end

-- 把直接下游从 Pending 升级为 Dirty。
function engine.markDirty(firstSubscriberLink)
    local link = firstSubscriberLink

    while link do
        local subscriber = link.sub
        local flags = subscriber.flags or ReactiveFlags.None

        if bit.band(flags, constants.DIRTY_OR_PENDING_FLAGS) == ReactiveFlags.Pending then
            constants.setFlags(subscriber, bit.bor(flags, ReactiveFlags.Dirty))
            tracer.emit("mark:dirty", subscriber, {
                link = link,
                dep = link.dep,
                sub = subscriber,
                flagsBefore = flags,
                flagsAfter = subscriber.flags,
            })

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
    local oldValue = signalNode.currentValue
    local nextValue = signalNode.pendingValue
    local flagsBefore = signalNode.flags
    constants.setFlags(signalNode, ReactiveFlags.Mutable)

    if oldValue == nextValue then
        tracer.emit("signal:commit", signalNode, {
            from = tracer.value(oldValue),
            to = tracer.value(nextValue),
            changed = false,
            flagsBefore = flagsBefore,
            flagsAfter = signalNode.flags,
        })
        return false
    end

    signalNode.currentValue = nextValue
    tracer.emit("signal:commit", signalNode, {
        from = tracer.value(oldValue),
        to = tracer.value(nextValue),
        changed = true,
        flagsBefore = flagsBefore,
        flagsAfter = signalNode.flags,
    })
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

    tracer.enter("computed:update", computedNode, {
        value = tracer.value(oldValue),
    })

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
        tracer.leave("computed:update", computedNode, {
            result = "error",
            flagsAfter = computedNode.flags,
        })
        error(newValue)
    end

    computedNode.value = newValue
    local changed = newValue ~= oldValue
    tracer.leave("computed:update", computedNode, {
        from = tracer.value(oldValue),
        to = tracer.value(newValue),
        changed = changed,
        flagsAfter = computedNode.flags,
    })
    return changed
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
        tracer.emit("check:unchanged", subscriber, {
            dep = dependency,
            sub = subscriber,
            changed = false,
        })
        return false, false
    end

    markDirtyMaybe(dependencySubscribers)
    tracer.emit("check:changed", subscriber, {
        dep = dependency,
        sub = subscriber,
        changed = true,
    })
    return true, not constants.isInactive(subscriber)
end

-- 递归确认 Pending 依赖是否真的变化。
local function pendingDepChanged(dependency)
    tracer.emit("check:pending", dependency, {
        dep = dependency,
        reason = "check-upstream-deps",
    })

    if engine.checkDeps(dependency.deps, dependency) then
        return true
    end

    constants.removeFlags(dependency, ReactiveFlags.Pending)
    tracer.emit("check:pending-clear", dependency, {
        dep = dependency,
        flagsAfter = dependency.flags,
    })
    return false
end

-- 检查单个依赖是否会让 subscriber 需要刷新。
local function checkDep(dependency, subscriber)
    if constants.isDirtyValue(dependency) then
        tracer.emit("check:dirty", subscriber, {
            dep = dependency,
            sub = subscriber,
            flagsAfter = dependency.flags,
        })
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
    tracer.enter("check", subscriber, {
        sub = subscriber,
    })

    local link = firstDependencyLink

    while link do
        if constants.hasFlag(subscriber, ReactiveFlags.Dirty) then
            local result = not constants.isInactive(subscriber)
            tracer.leave("check", subscriber, {
                result = result,
                reason = "subscriber-already-dirty",
            })
            return result
        end

        tracer.emit("check:dep", subscriber, {
            link = link,
            dep = link.dep,
            sub = subscriber,
        })

        -- shouldReturn 表示已经确认当前链路的答案，dependencyChanged 是要返回的结果。
        local shouldReturn, dependencyChanged = checkDep(
            link.dep,
            subscriber
        )
        if shouldReturn then
            tracer.leave("check", subscriber, {
                result = dependencyChanged,
                reason = dependencyChanged and "dependency-changed" or "dependency-unchanged",
            })
            return dependencyChanged
        end

        link = link.nextDep
    end

    tracer.leave("check", subscriber, {
        result = false,
        reason = "no-changed-deps",
    })
    return false
end

-- 判断 computed 是否需要刷新。
function engine.computedNeedsRefresh(computedNode)
    if constants.hasFlag(computedNode, ReactiveFlags.Dirty) then
        tracer.emit("computed:needs-refresh", computedNode, {
            result = true,
            reason = "dirty",
        })
        return true
    end

    if not constants.hasFlag(computedNode, ReactiveFlags.Pending) then
        tracer.emit("computed:needs-refresh", computedNode, {
            result = false,
            reason = "not-pending",
        })
        return false
    end

    if engine.checkDeps(computedNode.deps, computedNode) then
        tracer.emit("computed:needs-refresh", computedNode, {
            result = true,
            reason = "dependency-changed",
        })
        return true
    end

    constants.removeFlags(computedNode, ReactiveFlags.Pending)
    tracer.emit("computed:needs-refresh", computedNode, {
        result = false,
        reason = "pending-cleared",
        flagsAfter = computedNode.flags,
    })
    return false
end

-- 首次激活 lazy computed。
function engine.initComputed(computedNode)
    tracer.enter("computed:init", computedNode)
    engine.beginTrack(computedNode, ReactiveFlags.Mutable, false)

    local ok, initialValue = engine.callWithSub(computedNode, function()
        return computedNode.getter()
    end)

    engine.finishTrack(computedNode)

    if not ok then
        constants.addFlags(computedNode, ReactiveFlags.Dirty)
        tracer.leave("computed:init", computedNode, {
            result = "error",
            flagsAfter = computedNode.flags,
        })
        error(initialValue)
    end

    computedNode.value = initialValue
    tracer.leave("computed:init", computedNode, {
        value = tracer.value(initialValue),
        result = "ok",
    })
end

-- 执行并清空 effect cleanup。
function engine.runCleanup(effectNode)
    local cleanup = effectNode.cleanup
    effectNode.cleanup = nil

    if type(cleanup) ~= "function" then
        return
    end

    tracer.enter("effect:cleanup", effectNode)
    local previousSubscriber = activeSubscriber
    activeSubscriber = nil
    local ok, err = pcall(cleanup)
    activeSubscriber = previousSubscriber

    if not ok then
        tracer.leave("effect:cleanup", effectNode, {
            result = "error",
        })
        error(err)
    end

    tracer.leave("effect:cleanup", effectNode, {
        result = "ok",
    })
end

-- 执行 effect 主体并重建依赖。
function engine.runEffectBody(effectNode)
    tracer.enter("effect:run", effectNode)
    engine.beginTrack(effectNode, ReactiveFlags.Watching, true)

    local ok, cleanupOrError = engine.callWithSub(effectNode, effectNode.fn)

    engine.finishTrack(effectNode)

    if not ok then
        tracer.leave("effect:run", effectNode, {
            result = "error",
            flagsAfter = effectNode.flags,
        })
        error(cleanupOrError)
    end

    effectNode.cleanup = cleanupOrError
    tracer.leave("effect:run", effectNode, {
        result = "ok",
        flagsAfter = effectNode.flags,
    })
end

-- 判断入队 effect 是否真的需要运行。
function engine.shouldRunEffect(effectNode)
    if constants.hasFlag(effectNode, ReactiveFlags.Dirty) then
        tracer.emit("effect:should-run", effectNode, {
            result = true,
            reason = "dirty",
        })
        return true
    end

    if not constants.hasFlag(effectNode, ReactiveFlags.Pending) then
        tracer.emit("effect:should-run", effectNode, {
            result = false,
            reason = "not-pending",
        })
        return false
    end

    local shouldRun = engine.checkDeps(effectNode.deps, effectNode)
    tracer.emit("effect:should-run", effectNode, {
        result = shouldRun,
        reason = shouldRun and "dependency-changed" or "dependency-unchanged",
    })
    return shouldRun
end

-- scheduler 调用的 effect 执行入口。
function engine.runQueuedEffect(effectNode)
    effectNode.isQueued = false
    local flagsBeforeRun = effectNode.flags or ReactiveFlags.None

    tracer.emit("effect:dequeue", effectNode, {
        flagsBefore = flagsBeforeRun,
        flagsAfter = effectNode.flags,
    })

    if not engine.shouldRunEffect(effectNode) then
        if not constants.isInactive(effectNode) then
            constants.setFlags(
                effectNode,
                bit.bor(ReactiveFlags.Watching, bit.band(flagsBeforeRun, HAS_CHILD_EFFECT))
            )
        end
        tracer.emit("effect:skip", effectNode, {
            reason = "deps-unchanged",
            flagsAfter = effectNode.flags,
        })
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
    tracer.emit("node:unwatched", node, {
        reason = constants.isMutableNode(node) and "mutable-node" or "inactive-node",
    })

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
