# ReactiveFlags 状态机

这篇文档把 `ReactiveFlags` 从“几个 bit 位”翻译成“节点处于生命周期的哪一步”。
读 `engine.lua` 时，如果只看 `bit.band` / `bit.bor`，很容易迷路；更好的入口是
先按节点类型理解状态迁移。

## 先记住三组问题

| 问题 | 对应标志 | 含义 |
| --- | --- | --- |
| 这个节点能产出值并继续向下游传播吗？ | `Mutable` | signal、激活后的 computed、scope |
| 这个 effect 还活着，失效时要入队吗？ | `Watching` | effect 的监听态 |
| 这个节点只是可能受影响，还是自己确定要检查？ | `Pending` / `Dirty` | PUSH/PULL 分离的核心 |

`RecursedCheck` 和 `Recursed` 先放到最后看。它们服务递归保护，不是普通脏值状态。

## Signal 状态迁移

signal 是最简单的值生产者，创建后一直是 `Mutable`。

| 阶段 | flags | 触发入口 | 含义 |
| --- | --- | --- | --- |
| 初始/干净 | `Mutable` | `signal(initialValue)` | 可被追踪，当前值可信 |
| 写入后 | `Mutable | Dirty` | `s(nextValue)` | `pendingValue` 已变，等待提交到 `currentValue` |
| 读取/检查后 | `Mutable` | `commitSignalValue` | 提交 pending；若值真的变了，再通知下游 |

对应流程：

```text
Mutable
  -- s(nextValue) -->
Mutable | Dirty
  -- commitSignalValue -->
Mutable
```

signal 的 `Dirty` 很直接：它表示“我有一个待提交的新值”。如果新值和旧值相等，
`commitSignalValue` 会返回 false，下游不会被继续污染。

## Computed 状态迁移

computed 是 lazy 的：创建时不立刻执行 getter。

| 阶段 | flags | 触发入口 | 含义 |
| --- | --- | --- | --- |
| 尚未激活 | `None` | `computed(getter)` | 没有值，也没有上游依赖 |
| 首次读取中 | `Mutable | RecursedCheck` | `initComputed` | 正在执行 getter 并收集依赖 |
| 已激活/干净 | `Mutable` | 首次读取完成或刷新完成 | 有缓存值，可作为依赖源 |
| 上游可能变了 | `Mutable | Pending` | PUSH 阶段传播 | 下次被读取时再确认 |
| 确认需要重算 | `Mutable | Dirty` 或含 `Dirty` | 上游确认变化、失去观察者、错误后重试 | 下次读取必须刷新自己 |

常见流程：

```text
None
  -- first read -->
Mutable | RecursedCheck
  -- getter finished -->
Mutable
  -- upstream write propagates -->
Mutable | Pending
  -- pull confirms changed -->
Mutable | RecursedCheck
  -- getter finished -->
Mutable
```

如果 PULL 阶段发现上游其实没变：

```text
Mutable | Pending
  -- checkDeps returns false -->
Mutable
```

这就是 `Pending` 的意义：它让 computed 先便宜地标记“可能变了”，等真正需要值时
再沿 `deps` 链确认。

## Effect 状态迁移

effect 不产出值，它负责被调度重跑。因此它的核心状态是 `Watching`。

| 阶段 | flags / 字段 | 触发入口 | 含义 |
| --- | --- | --- | --- |
| 首次运行中 | `Watching | RecursedCheck` | `effect(fn)` | 正在执行 fn 并收集依赖 |
| 监听中 | `Watching` | 首次运行完成或重跑完成 | 上游变化时需要入队 |
| 已入队 | `Pending`, `isQueued = true` | `scheduler.enqueueEffect` | 已经在队列里，临时移除 `Watching` 去重 |
| 需要重跑 | `Dirty` 或 pull 确认变化 | `runQueuedEffect` | 先 cleanup，再执行 effect body |
| 已停止 | `None` | stop callable / 失去父订阅者 | 不再参与传播 |

简化流程：

```text
Watching
  -- upstream write -->
Pending + isQueued
  -- scheduler.flush -->
runQueuedEffect
  -- effect body finished -->
Watching
```

入队时移除 `Watching` 是去重技巧：同一批更新里，一个 effect 即使被多个上游击中，
也只会进入队列一次。重跑结束后才恢复 `Watching`。

## EffectScope 状态迁移

scope 更像一个可停止的父节点，而不是会重跑的 effect。

| 阶段 | flags | 触发入口 | 含义 |
| --- | --- | --- | --- |
| 活跃 | `Mutable` | `effectScope(fn)` | 可作为子 effect 的父节点被追踪 |
| 拥有子节点 | `Mutable | HAS_CHILD_EFFECT` | scope 内创建 effect/scope | 停止时要先释放子树 |
| 已停止 | `None` | stop callable / 父节点释放 | 子 effect 已按逆序 cleanup |

scope 使用 `Mutable` 不是因为它有用户可读的值，而是因为它需要作为依赖源挂住子
effect，从而复用 `Link` 图结构做统一清理。

## `Pending` 和 `Dirty` 的端到端差异

假设有：

```lua
local count = signal(0)
local double = computed(function()
    return count() * 2
end)

effect(function()
    print(double())
end)
```

执行 `count(1)` 后，系统先进入 PUSH 阶段：

```text
count   : Mutable | Dirty
double  : Mutable | Pending
effect  : Pending + isQueued
```

这时没有任何 getter 被调用。`double` 只是“可能变了”。

等 scheduler 刷新 effect 时，进入 PULL 阶段：

```text
shouldRunEffect(effect)
  -> check double
     -> check count
        -> commit count: Dirty -> Mutable, value changed
     -> update double: Pending -> Mutable, value changed
  -> effect 确认需要重跑
```

如果 count 在同一个 batch 里先写成 `1` 又写回 `0`，PULL 阶段会发现最终值没有
变化，`Pending` 会被撤掉，effect 不会重跑。这就是 `Pending` 不等于 `Dirty`。

## 递归相关 flags

`RecursedCheck` 和 `Recursed` 只在“节点正在执行时又被触达”的场景里有意义。

| 标志 | 什么时候出现 | 解决的问题 |
| --- | --- | --- |
| `RecursedCheck` | effect/computed 正在执行 body/getter，依赖链正在重建 | 告诉传播算法：这个节点处于敏感的追踪窗口 |
| `Recursed` | 写入发生在响应式运行内部，传播又碰到正在执行的节点 | 避免自触发导致无限重入，同时保留必要的 pending 标记 |

普通读法：

```text
RecursedCheck = “我正在收集依赖，别把我当成普通干净节点处理”
Recursed      = “传播路径已经绕回执行中的节点，需要延后处理”
```

看到这两个 flag 时，建议直接跳到 `decidePropagation`：

1. 如果节点没有递归标记，重复传播通常会被跳过。
2. 如果节点正在 `RecursedCheck` 中，算法会用
   `isLinkInCurrentDeps` 判断当前 link 是否已经被本轮重新覆盖。
3. 只有满足条件时，才补上 `Recursed | Pending`，避免错误重入。

## 组合速查

| 组合 | 可以理解为 |
| --- | --- |
| `None` | 节点未激活或已停止 |
| `Mutable` | 值生产者已激活且当前干净 |
| `Mutable | Dirty` | 值生产者自己确定需要提交/重算 |
| `Mutable | Pending` | 值生产者的上游可能变化，等待 PULL 确认 |
| `Watching` | effect 正在监听依赖变化 |
| `Pending` + `isQueued` | effect 已入队，等待 scheduler 刷新 |
| `Watching | RecursedCheck` | effect 首次执行或重跑中，正在收集依赖 |
| `Mutable | RecursedCheck` | computed 正在执行 getter，正在收集依赖 |
| `HAS_CHILD_EFFECT` | 节点拥有子 effect/scope，cleanup 时要先释放子树 |

## 按代码入口阅读

| 想看哪种迁移 | 入口 |
| --- | --- |
| signal 写入变 Dirty | `primitives.signalOp` |
| signal Dirty 回到 Mutable | `engine.commitSignalValue` |
| computed 首次激活 | `engine.initComputed` |
| computed Pending 是否刷新 | `engine.computedNeedsRefresh` |
| Pending 递归确认 | `engine.checkDeps` |
| effect 入队去重 | `scheduler.enqueueEffect` |
| effect 重跑恢复 Watching | `engine.runQueuedEffect` |
| 递归传播判定 | `engine.lua` 中的 `decidePropagation` |
| 子 effect cleanup 标记 | `constants.HAS_CHILD_EFFECT` 和 `effect-cleanup.md` |

把这张表和 `graph.md` 的 Link 结构放在一起看，基本就能读懂整个实现：

- `subs` 链负责 PUSH，把 `Dirty/Pending` 往下游传播。
- `deps` 链负责 PULL，确认 `Pending` 是否真的需要变成重算。
- flags 记录每个节点当前处于哪一步。
