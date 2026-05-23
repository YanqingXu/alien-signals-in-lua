# 从朴素 Map 到双链 Link

这篇文档用一个逐步推导的方式解释：为什么响应式图没有用
`dependency -> subscribers` 的朴素表结构，而是用一个同时挂进两条链的 `Link`。

## 起点：只需要传播失效

最容易想到的数据结构是：

```text
subscribersByDependency = {
  signalA = { effectE, effectF },
  signalB = { effectE },
}
```

它能很好地回答第一个问题：

> signalA 写入后，哪些 subscriber 需要收到通知？

沿着 `subscribersByDependency[signalA]` 走一遍即可。对于只有静态依赖的玩具系统，
这已经够用。

## 第一个问题：动态依赖需要反向清理

真实 effect 的依赖会变：

```lua
effect(function()
    if enabled() then
        print(name())
    end
end)
```

第一轮 `enabled() == true` 时，effect 订阅了 `enabled` 和 `name`。
第二轮 `enabled() == false` 时，effect 不再读取 `name`。

如果只有 `dependency -> subscribers`，系统很难知道：

> effect 本轮没有再读取哪些旧依赖？

因此还需要一份反向索引：

```text
dependenciesBySubscriber = {
  effectE = { enabled, name },
}
```

重跑 effect 后，可以对比“上一轮读过的依赖”和“本轮读过的依赖”，把旧依赖从
`subscribersByDependency` 中删除。

## 第二个问题：两张表要保持一致

加上反向索引后，每条边同时存在于两张表里：

```text
enabled -> effectE
effectE -> enabled
```

这会带来一个一致性问题：删除一条边时，必须同时从两边删除。用数组或 set
当然也能做，但通常会遇到这些成本：

| 操作 | 朴素数组/Set 的代价 |
| --- | --- |
| 从 dependency 的 subscribers 删除某个 subscriber | 需要查找对应条目 |
| 从 subscriber 的 dependencies 删除某个 dependency | 也需要查找对应条目 |
| effect 每次重跑后清理旧依赖 | 需要额外集合对比或标记 |
| 高频增删边 | 容易产生更多临时表和 GC 压力 |

响应式系统的热路径恰好就是“读依赖、写 signal、清理动态依赖”。所以这里值得为
边本身设计一个更直接的数据结构。

## Link：把一条边变成一个对象

当前实现把每条 `dependency -> subscriber` 边表示成一个 `Link`：

```text
Link(A -> E)
  dep  = Signal A
  sub  = Effect E
```

关键点是：这个 `Link` 不只记录边两端，还带有两组前后指针：

```text
dependency.subs 链使用： prevSub / nextSub
subscriber.deps 链使用： prevDep / nextDep
```

也就是说，同一个 Link 同时出现在两条链上：

```text
Signal A.subs  -> [Link A->E] <-> [Link A->F]
                    |
                    | 同一个 Link
                    v
Effect E.deps  -> [Link A->E] <-> [Link B->E]
```

这让系统同时拥有两个方向的遍历能力：

| 入口 | 走哪条链 | 用途 |
| --- | --- | --- |
| signal/computed 写入或变脏 | `dependency.subs` | 向下游传播 `Pending`，收集 effect |
| effect/computed 重跑结束 | `subscriber.deps` | 清理本轮没再读取的旧依赖 |

## 为什么是双向链表

`Link` 需要能被 O(1) 删除。删除时已经拿到了 Link 本身，因此只要改四根指针：

```text
subscriber.deps 链： prevDep <-> nextDep
dependency.subs 链： prevSub <-> nextSub
```

不需要在线性数组里搜索，不需要再从另一张表里反查。`graph.unlink`
正是把这四根指针同步接回去。

## 为什么保留读取顺序

`subscriber.deps` 链不是随便排列的，它按 getter/effect 的读取顺序排列。
重跑前，`depsTail` 被置为 `nil`；重跑过程中每读到一个依赖，`depsTail` 就向前
推进一次。

如果两轮读取顺序一样：

```text
上一轮：A -> B -> C
本一轮：A -> B -> C
```

`connect` 可以直接复用旧 Link，只刷新 `version` 并推进
游标，几乎没有分配。

如果本轮少读了 `C`：

```text
上一轮：A -> B -> C
本一轮：A -> B
```

重跑结束后，`depsTail` 停在 `B`，`depsTail.nextDep` 开始的部分就是陈旧依赖。
这就是 `unlinkStaleDeps` 的起点。

## 和 HashMap 方案的取舍

HashMap/Set 方案更直观，适合教学版的第一步；双链 Link 更适合高频响应式运行时：

| 维度 | Map/Set | 双链 Link |
| --- | --- | --- |
| 概念门槛 | 低 | 中等，需要理解一条边挂两条链 |
| 从依赖找订阅者 | 快 | 快 |
| 从订阅者找依赖 | 需要第二张表 | 天然支持 |
| 删除一条已知边 | 取决于容器实现 | O(1)，只改指针 |
| 动态依赖清理 | 常需要集合对比 | `depsTail` 后方就是旧依赖 |
| 分配压力 | 容器和临时集合更多 | 依赖顺序稳定时可复用 Link |

所以当前实现不是为了“链表更酷”，而是因为响应式系统最频繁的操作正好是：

1. 读取依赖时连接边。
2. 写入时从依赖向下游传播。
3. 重跑后从订阅者侧清理旧边。
4. 依赖顺序不变时复用上一轮的边。

双链 `Link` 用一个对象同时覆盖这四个需求。

## 读源码时的定位法

读 `graph.lua` 可以按下面的问题定位：

| 想知道什么 | 看哪里 |
| --- | --- |
| 一条边长什么样 | `createLink` |
| 读到依赖时如何连边 | `connect` |
| 两条链如何同时摘除 | `unlink` |
| 本轮没读到的旧依赖如何清理 | `unlinkStaleDeps` |
| 递归追踪时如何判断 link 是否已覆盖 | `isLinkInCurrentDeps` |

掌握这张图之后，再看 `engine` 的 PUSH/PULL 算法会轻松很多：`engine` 只是决定
什么时候沿 `subs` 走、什么时候沿 `deps` 走；真正保证图结构正确的是 `Link`。
