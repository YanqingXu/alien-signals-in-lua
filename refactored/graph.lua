--[[
graph.lua

模块概述：
依赖图维护模块。它实现响应式系统最底层的边管理逻辑，负责创建、复用、插入和解绑
Link 节点，并维护 dependency 与 subscriber 两个方向上的双向链表结构。

设计动机与职责：
响应式传播既要能从依赖源快速找到所有订阅者，又要能从订阅者回溯并清理旧依赖；
graph.lua 通过“一条边对应一个 Link，且同时挂在两条链上”的方式解决这个问题，
从而支持 O(1) 连接/移除、按追踪版本复用旧 Link，以及 effect/computed 重跑后的
陈旧依赖清理，而不把任何 signal、computed、effect 的业务语义混入图层实现。

协作关系：
它直接依赖 tracer 提供可选的结构化调试事件，并接收由 engine 注入的
onDependencyBecameUnwatched 回调；engine 依赖它完成 trackRead、清理依赖和失活回收，
primitives 也通过它建立父子 effect 或 scope 的连接关系。

核心概念：
本模块的关键数据结构是 Link 节点，以及 dep.subs / subsTail 与 sub.deps / depsTail
两条正交的双向链表。除此之外，Link.version、反向解绑顺序和“当前追踪前缀”的判定
也是支撑增量追踪与依赖复用的核心概念。
]]

local graph = {}

local tracer = require("refactored.tracer")

local onDependencyBecameUnwatched = function() end

-- 注入依赖源无人订阅时的回调。
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
-- 创建一条同时挂入两条链的边。
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

-- 把 Link 接到 subscriber.deps 链上。
local function insertDepLink(
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

-- 把 Link 追加到 dependency.subs 链上。
local function appendSubLink(dependency, link, previousSubscriberLink)
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
function graph.connect(dependency, subscriber, version)
    local previousDependencyLink = subscriber.depsTail

    if previousDependencyLink and previousDependencyLink.dep == dependency then
        tracer.emit("graph:reuse", dependency, {
            link = previousDependencyLink,
            dep = dependency,
            sub = subscriber,
            reason = "same-tail-dependency",
        })
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
        tracer.emit("graph:reuse", dependency, {
            link = nextDependencyLink,
            dep = dependency,
            sub = subscriber,
            reason = "next-dependency-link",
        })
        return
    end

    local previousSubscriberLink = dependency.subsTail
    if previousSubscriberLink
        and previousSubscriberLink.version == version
        and previousSubscriberLink.sub == subscriber
    then
        tracer.emit("graph:reuse", dependency, {
            link = previousSubscriberLink,
            dep = dependency,
            sub = subscriber,
            reason = "same-version-subscriber",
        })
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

    insertDepLink(subscriber, link, previousDependencyLink, nextDependencyLink)
    appendSubLink(dependency, link, previousSubscriberLink)

    tracer.emit("graph:connect", dependency, {
        link = link,
        dep = dependency,
        sub = subscriber,
    })
end

--[[
从两条链中同时移除 Link。

这是双向链表方案最需要谨慎的地方：只拆一边会留下悬挂引用，导致后续传播或清理
走到已经无效的订阅者。移除后如果 dependency 已经没有任何订阅者，会通知上层
算法清理它的上游依赖。
]]
function graph.unlink(link, explicitSubscriber)
    local subscriber = explicitSubscriber or link.sub
    local dependency = link.dep

    tracer.emit("graph:unlink", dependency, {
        link = link,
        dep = dependency,
        sub = subscriber,
    })

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
        tracer.emit("graph:unwatched", dependency, {
            dep = dependency,
        })
        onDependencyBecameUnwatched(dependency)
    end

    return nextDependencyLink
end

-- 从 depsTail 反向摘除依赖，常用于 LIFO cleanup。
function graph.unlinkDepsReverse(subscriber, shouldRemoveDependency)
    local link = subscriber.depsTail

    while link do
        local previousDependencyLink = link.prevDep

        if not shouldRemoveDependency or shouldRemoveDependency(link.dep, link) then
            graph.unlink(link, subscriber)
        end

        link = previousDependencyLink
    end
end

-- 在 dependency.subs 链里查找指定 Link。
local function hasSubLink(dependency, linkToFind)
    local link = dependency.subs
    while link do
        if link == linkToFind then
            return true
        end
        link = link.nextSub
    end
    return false
end

-- 在 subscriber.deps 链里查找指定 Link。
local function hasDepLink(subscriber, linkToFind)
    local link = subscriber.deps
    while link do
        if link == linkToFind then
            return true
        end
        link = link.nextDep
    end
    return false
end

-- 校验 subscriber.deps 链是否自洽。
function graph.validateDeps(subscriber)
    local previousLink = nil
    local link = subscriber.deps

    if link == nil and subscriber.depsTail ~= nil then
        return false, "subscriber.depsTail is set while subscriber.deps is nil"
    end

    while link do
        if link.sub ~= subscriber then
            return false, "dependency link points at a different subscriber"
        end

        if link.prevDep ~= previousLink then
            return false, "dependency prevDep pointer is inconsistent"
        end

        if link.dep == nil or not hasSubLink(link.dep, link) then
            return false, "dependency link is missing from dependency.subs"
        end

        previousLink = link
        link = link.nextDep
    end

    if previousLink ~= subscriber.depsTail then
        return false, "subscriber.depsTail does not point at the last dependency link"
    end

    return true
end

-- 校验 dependency.subs 链是否自洽。
function graph.validateSubs(dependency)
    local previousLink = nil
    local link = dependency.subs

    if link == nil and dependency.subsTail ~= nil then
        return false, "dependency.subsTail is set while dependency.subs is nil"
    end

    while link do
        if link.dep ~= dependency then
            return false, "subscriber link points at a different dependency"
        end

        if link.prevSub ~= previousLink then
            return false, "subscriber prevSub pointer is inconsistent"
        end

        if link.sub == nil or not hasDepLink(link.sub, link) then
            return false, "subscriber link is missing from subscriber.deps"
        end

        previousLink = link
        link = link.nextSub
    end

    if previousLink ~= dependency.subsTail then
        return false, "dependency.subsTail does not point at the last subscriber link"
    end

    return true
end

-- 移除本轮追踪没有再次读到的旧依赖。
function graph.unlinkStaleDeps(subscriber)
    local firstStaleLink
    if subscriber.depsTail then
        firstStaleLink = subscriber.depsTail.nextDep
    else
        firstStaleLink = subscriber.deps
    end

    while firstStaleLink do
        firstStaleLink = graph.unlink(firstStaleLink, subscriber)
    end
end

-- 判断 Link 是否在本轮已重新追踪的前缀内。
function graph.isLinkInCurrentDeps(linkToFind, subscriber)
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
