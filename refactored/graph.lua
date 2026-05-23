--[[
graph.lua

负责维护响应式图的底层连接结构。这里不关心 signal/computed/effect 的业务语义，
只关心 Link 如何同时挂进两条双向链表，以及如何被安全移除。
]]

local graph = {}

local onDependencyBecameUnwatched = function() end

function graph.setUnwatchedHandler(handler)
    onDependencyBecameUnwatched = handler or function() end
end

--[[
Link 字段词汇表

一个 Link 是 dependency -> subscriber 这条边，但它同时属于两条链：

1. dependency.subs 链：从依赖源找到所有订阅者。
   - dep/sub 表示这条边两端的节点。
   - prevSub/nextSub 是 Link 在 dependency.subs 链里的前后指针。

2. subscriber.deps 链：从订阅者找到本轮读取过的依赖。
   - prevDep/nextDep 是同一个 Link 在 subscriber.deps 链里的前后指针。

因此 Sub/Dep 后缀说的是“这根指针服务哪条链”，不是 Link 另一端的节点类型。
删除 Link 时必须同时修复这两条链，否则会留下悬挂引用。
]]
function graph.createLink(
    dependency,
    subscriber,
    previousSubscriberLink,
    nextSubscriberLink,
    previousDependencyLink,
    nextDependencyLink
)
    return {
        version = 0,
        dep = dependency,
        sub = subscriber,
        prevSub = previousSubscriberLink,
        nextSub = nextSubscriberLink,
        prevDep = previousDependencyLink,
        nextDep = nextDependencyLink,
    }
end

local function insertIntoSubscriberDependencies(
    subscriber,
    link,
    previousDependencyLink,
    nextDependencyLink
)
    if previousDependencyLink then
        previousDependencyLink.nextDep = link
    else
        subscriber.deps = link
    end

    if nextDependencyLink then
        nextDependencyLink.prevDep = link
    end

    subscriber.depsTail = link
end

local function appendIntoDependencySubscribers(dependency, link, previousSubscriberLink)
    if previousSubscriberLink then
        previousSubscriberLink.nextSub = link
    else
        dependency.subs = link
    end

    dependency.subsTail = link
end

--[[
建立 dependency -> subscriber 的依赖关系。

一个 Link 会同时存在于两条链中：
- dependency.subs：从依赖源出发，找到所有订阅者。
- subscriber.deps：从订阅者出发，找到它读取过的所有依赖源。

重跑 effect/computed 时，subscriber.depsTail 从 nil 重新向后推进；如果本轮读取
顺序与上一轮一致，可以复用旧 Link。重跑结束后，depsTail 后方的旧 Link 就是
“本轮没有再读取”的陈旧依赖。
]]
function graph.connectDependencyToSubscriber(dependency, subscriber, version)
    local previousDependencyLink = subscriber.depsTail

    if previousDependencyLink and previousDependencyLink.dep == dependency then
        return
    end

    local nextDependencyLink
    if previousDependencyLink then
        nextDependencyLink = previousDependencyLink.nextDep
    else
        nextDependencyLink = subscriber.deps
    end

    if nextDependencyLink and nextDependencyLink.dep == dependency then
        nextDependencyLink.version = version
        subscriber.depsTail = nextDependencyLink
        return
    end

    local previousSubscriberLink = dependency.subsTail
    if previousSubscriberLink
        and previousSubscriberLink.version == version
        and previousSubscriberLink.sub == subscriber
    then
        return
    end

    local link = graph.createLink(
        dependency,
        subscriber,
        previousSubscriberLink,
        nil,
        previousDependencyLink,
        nextDependencyLink
    )
    link.version = version

    insertIntoSubscriberDependencies(subscriber, link, previousDependencyLink, nextDependencyLink)
    appendIntoDependencySubscribers(dependency, link, previousSubscriberLink)
end

--[[
从两条链中同时移除 Link。

这是双向链表方案最需要谨慎的地方：只拆一边会留下悬挂引用，导致后续传播或清理
走到已经无效的订阅者。移除后如果 dependency 已经没有任何订阅者，会通知上层
算法清理它的上游依赖。
]]
function graph.removeDependencyLink(link, explicitSubscriber)
    local subscriber = explicitSubscriber or link.sub
    local dependency = link.dep

    local previousDependencyLink = link.prevDep
    local nextDependencyLink = link.nextDep
    local previousSubscriberLink = link.prevSub
    local nextSubscriberLink = link.nextSub

    if previousDependencyLink then
        previousDependencyLink.nextDep = nextDependencyLink
    else
        subscriber.deps = nextDependencyLink
    end

    if nextDependencyLink then
        nextDependencyLink.prevDep = previousDependencyLink
    else
        subscriber.depsTail = previousDependencyLink
    end

    if previousSubscriberLink then
        previousSubscriberLink.nextSub = nextSubscriberLink
    else
        dependency.subs = nextSubscriberLink
    end

    if nextSubscriberLink then
        nextSubscriberLink.prevSub = previousSubscriberLink
    else
        dependency.subsTail = previousSubscriberLink
    end

    link.prevDep = nil
    link.nextDep = nil
    link.prevSub = nil
    link.nextSub = nil

    if dependency.subs == nil then
        onDependencyBecameUnwatched(dependency)
    end

    return nextDependencyLink
end

function graph.removeStaleDependencyLinks(subscriber)
    local firstStaleLink
    if subscriber.depsTail then
        firstStaleLink = subscriber.depsTail.nextDep
    else
        firstStaleLink = subscriber.deps
    end

    while firstStaleLink do
        firstStaleLink = graph.removeDependencyLink(firstStaleLink, subscriber)
    end
end

function graph.linkIsInsideCurrentDependencyPrefix(linkToFind, subscriber)
    local link = subscriber.depsTail
    while link do
        if link == linkToFind then
            return true
        end
        link = link.prevDep
    end
    return false
end

return graph
