# `constants.lua` — 常量、类型标记与位标志

## 设计动机

整个响应式系统里有大量"稳定不变的事实"：一共有几种节点、节点的状态用哪几个比特
表示、怎样测试/设置这些比特。如果把它们散落到 `graph`、`engine`、`primitives`
任何一处，都会带来两个问题：

1. **循环依赖**：`graph` 需要识别"节点处于 RecursedCheck"，而 `engine` 又需要
   `graph` 提供的判断；如果定义放在 `engine`，`graph` 反过来就要 require
   `engine`，立刻闭环。
2. **概念漂移**：同一组比特在不同文件里被反复 `bit.bor` 出新的常量，时间一长
   就会出现"含义相近但取值不同"的副本。

`constants.lua` 是一个**叶子模块**：它不依赖任何业务模块，只暴露常量与极薄的
位运算工具。其他模块都从这里取唯一权威的定义。

## 内部逻辑

### 类型标记 (Markers)

```lua
constants.SIGNAL_MARKER       = {}
constants.COMPUTED_MARKER     = {}
constants.EFFECT_MARKER       = {}
constants.EFFECT_SCOPE_MARKER = {}
```

每个 marker 都是一张空表。Lua 中空表的相等性是基于引用的，因此它们天生具备
"全局唯一身份"，且不会被任何字符串/数字意外撞上。节点用 `__type = SIGNAL_MARKER`
之类的字段记录自己是哪种节点。

### `functionToNode` 弱键表

```lua
constants.functionToNode = setmetatable({}, { __mode = "k" })
```

`signal()` / `computed()` / `effect()` 返回给用户的都是闭包，而真正承载状态的
是闭包内部捕获的 node。通过 `bind(operation, node)` 把闭包反向登记到这张表，
之后 `isSignal(value)` 等判断就可以由闭包反查 node。`__mode = "k"` 让用户丢弃
callable 之后，对应条目可以被 GC 回收。

### ReactiveFlags 位标志

| 标志           | 值  | 含义                                            |
|----------------|-----|-------------------------------------------------|
| `None`         | 0   | 默认状态 / 节点已停                              |
| `Mutable`      | 1   | 节点可被作为依赖追踪（signal / 已激活的 computed） |
| `Watching`     | 2   | 节点是"活的 effect"，值变化时需要重跑             |
| `RecursedCheck`| 4   | 节点正在重跑的过程里（防止自递归追踪）             |
| `Recursed`     | 8   | 在递归路径中已经被重新触达                        |
| `Dirty`        | 16  | 值确定变了（signal 已写、computed 需重算）        |
| `Pending`      | 32  | 上游有变化，"可能脏" —— 等脏值检查最终裁决         |

把状态压缩进单个整数，让"节点处于哪些组合状态"成为一次 `bit.band`/`bit.bor`，
是该响应式实现性能优势的根源之一。

### 子 effect 标记：`HAS_CHILD_EFFECT`

`HAS_CHILD_EFFECT = 64` 不属于 `ReactiveFlags` 状态机。它只记录一个节点是否
在自己的执行过程中创建过子 effect / scope。

这个标记用于 cleanup 顺序：父 effect 重跑或停止前，要先从 `depsTail` 反向释放
子 effect / scope，再执行父 effect 自己的 cleanup。这样嵌套 effect 的清理顺序
保持为“最内层先、后创建的 sibling 先”。

### 阅读词汇表：把 flags 翻译成问题

读 `engine.lua` 时，不要先把 flags 当成二进制位看；可以先把它们翻译成
算法正在回答的问题：

| 标志 | 可以翻译成的问题 | 常见出现位置 |
| --- | --- | --- |
| `Mutable` | 这个节点会产出值吗？它能继续向下游传播吗？ | signal、已激活 computed、scope |
| `Watching` | 这个 effect 还活着吗？失效时要不要入队？ | effect 节点、scheduler 入队去重 |
| `RecursedCheck` | 这个节点正在重建依赖链吗？ | effect/computed 执行 getter 或 fn 时 |
| `Recursed` | 传播是否在递归路径里又碰到它？ | 写入发生在响应式运行内部时 |
| `Dirty` | 它自己的值是否已经确定需要提交或重算？ | signal 写入、computed 需要重算 |
| `Pending` | 它的上游可能变了，但还没确认吗？ | PUSH 阶段传播、PULL 阶段确认 |

两组对照最重要：

| 对照 | 教学理解 |
| --- | --- |
| `Dirty` vs `Pending` | `Dirty` 是“我自己要检查”，`Pending` 是“我得先问上游有没有真的变” |
| `Mutable` vs `Watching` | `Mutable` 节点负责产出值并继续传播，`Watching` 节点负责被调度重跑 |

按节点类型理解 flags 如何迁移，见 [`state-machine.md`](state-machine.md)。

### 预组合常量

```lua
TRACKABLE_FLAGS         = Mutable | Watching
RECURSION_FLAGS         = RecursedCheck | Recursed
DIRTY_OR_PENDING_FLAGS  = Dirty | Pending
PROPAGATION_GUARD_FLAGS = RecursedCheck | Recursed | Dirty | Pending
```

这些组合在传播算法（`engine.lua` 的 `decidePropagation`）和脏值检查里
被高频使用，预先合好可省去每次重新 `bit.bor`。

#### 位图速查（bit5..bit0）

每个组合常量对应的二进制位图如下（` ■ ` 表示该位为 1，` · ` 表示为 0）：

| 常量 / 标志             | 数值 | Pend (32) | Dirty (16) | Recur (8) | Check (4) | Watch (2) | Muta (1) |
|-------------------------|------|:---------:|:----------:|:---------:|:---------:|:---------:|:--------:|
| `Mutable`               |   1  |    ·      |     ·      |    ·      |    ·      |    ·      |    ■     |
| `Watching`              |   2  |    ·      |     ·      |    ·      |    ·      |    ■      |    ·     |
| `RecursedCheck`         |   4  |    ·      |     ·      |    ·      |    ■      |    ·      |    ·     |
| `Recursed`              |   8  |    ·      |     ·      |    ■      |    ·      |    ·      |    ·     |
| `Dirty`                 |  16  |    ·      |     ■      |    ·      |    ·      |    ·      |    ·     |
| `Pending`               |  32  |    ■      |     ·      |    ·      |    ·      |    ·      |    ·     |
| `TRACKABLE_FLAGS`       |   3  |    ·      |     ·      |    ·      |    ·      |    ■      |    ■     |
| `RECURSION_FLAGS`       |  12  |    ·      |     ·      |    ■      |    ■      |    ·      |    ·     |
| `DIRTY_OR_PENDING_FLAGS`|  48  |    ■      |     ■      |    ·      |    ·      |    ·      |    ·     |
| `PROPAGATION_GUARD_FLAGS`|  60 |    ■      |     ■      |    ■      |    ■      |    ·      |    ·     |

判定函数与组合常量的对应关系：

| 判定 | 等价表达 | 用途 |
| --- | --- | --- |
| `hasAnyBits(flags, TRACKABLE_FLAGS)` | flags & 3 ≠ 0 | 节点是否值得参与传播 |
| `hasAnyBits(flags, RECURSION_FLAGS)` | flags & 12 ≠ 0 | 节点是否处于追踪/已触达递归路径 |
| `hasAnyBits(flags, DIRTY_OR_PENDING_FLAGS)` | flags & 48 ≠ 0 | 节点是否已被打上某种"脏"标记 |
| `hasAnyBits(flags, PROPAGATION_GUARD_FLAGS)` | flags & 60 ≠ 0 | 传播时是否需要走"已触达"分支 |
| `isDirtyValue(node)` | flags & 17 == 17 | signal 写入后等待 commit 的状态 |
| `isPendingValue(node)` | flags & 33 == 33 | computed 上游被打 Pending 的状态 |

> 这些"按位组合 + 整数比较"是该实现性能的核心。`decidePropagation`
> 在最坏路径下也只做 4~5 次 `bit.band`，没有任何分配。

### 位运算工具

- `hasFlag(node, flag)` —— 判断单个标志。
- `hasAnyBits` / `hasAllBits` —— 判断一组标志是"有任意一个"还是
  "全部都有"。
- `isSignalNode` / `isComputedNode` / `isEffectNode` / `isEffectScopeNode` ——
  基于 marker 判断内部节点类型，避免在算法层散落 `node.__type == ...`。
- `isValueProducerNode` —— 判断节点是否是 signal/computed，用于 cleanup 时
  区分普通值依赖和子 effect/scope。
- `addFlags` / `removeFlags` / `setFlags` —— 写入侧的便捷封装；做了
  `node.flags or None` 的兜底，使刚创建尚未设置 `flags` 的节点也安全可用。
- `isMutableNode` / `isWatchingEffect` / `isInactive` /
  `isDirtyValue` / `isPendingValue` —— 语义化判定，
  让调用方读起来更接近自然语言。

## 模块间依赖关系

- **依赖**：仅依赖 `bit`（来自 `bit.lua`，本仓库提供）。
- **被依赖**：`graph` / `scheduler` / `engine` / `primitives` 全部依赖它，
  通常是直接 `require` 并按需保留 `ReactiveFlags` 本地引用以减少表查找。

## 关键实现细节

### 为什么 `setFlags` 不是 `node.flags = flags`？

实际上 `setFlags` 确实就是 `node.flags = flags`；它存在的价值是给外部一个
**单一入口**：未来如果要加日志、监听、或迁移到不同存储 (例如 metatable
属性)，只需要改这一个函数。`addFlags` / `removeFlags` 同理。

### 为什么 `functionToNode` 用弱键？

`functionToNode[callable] = node` 是从用户可见的 callable 指向内部 node 的弱
映射。如果用户不再持有 callable，对应的 effect / signal 也应当能被 GC。强引用
会让 callable 永远活在表里，造成内存泄漏。

### 为什么 marker 是空表而不是字符串？

字符串常量在 Lua 中是全局唯一的，但容易和用户数据撞名（比如用户把
`"signal"` 写入某个字段）。空表的引用唯一性更强，也方便日后挂载额外元数据
（例如 `SIGNAL_MARKER.__name = "Signal"` 用于调试）。
