--- 
# Alien Signals · 模块化重构版

本目录是 `alien_signals.lua` 单文件实现的模块化重构版本。它把原本约一千行的实现
拆成六个互相协作的模块，原有公共 API 保持一致，并额外提供可选 tracing；
外部使用方只需要
`require("refactored")`，无需关心内部分层。

```
refactored/
├── init.lua        ── 统一入口；聚合并导出公共 API
├── constants.lua   ── 常量、类型标记 (Markers)、ReactiveFlags 位标志、标志位工具
├── graph.lua       ── 双向链表依赖图：Link 节点的创建、插入、解绑
├── scheduler.lua   ── 批量更新 (Batching) 与 effect 调度队列
├── engine.lua      ── 响应式核心：activeSub 追踪、传播、脏值检查
├── primitives.lua  ── 用户侧原语：signal / computed / effect / effectScope / trigger
└── tracer.lua      ── 默认关闭的结构化运行时追踪事件
```

## 模块职责

### `init.lua` — 统一入口

聚合层。按顺序加载 `constants → tracer → scheduler → engine → primitives`，
然后把面向用户的函数集中导出到同一张表里：

- 响应式原语：`signal` / `computed` / `effect` / `effectScope` / `trigger`
- 类型判断：`isSignal` / `isComputed` / `isEffect` / `isEffectScope`
- 批量调度：`startBatch` / `endBatch` / `getBatchDepth`
- 活动订阅者控制：`getActiveSub` / `setActiveSub`
- 标志常量：`ReactiveFlags`
- 运行时追踪：`tracer` / `setTraceHandler` / `clearTraceHandler`

它本身不持有任何状态，只负责"打包发布"。

### `constants.lua` — 常量与标志位工具

集中放置整个系统的"稳定事实"，让其他模块只依赖少量、明确的常量与小工具：

- **类型标记 (Markers)**：`SIGNAL_MARKER` / `COMPUTED_MARKER` / `EFFECT_MARKER` /
  `EFFECT_SCOPE_MARKER`，作为节点身份的唯一引用。
- **ReactiveFlags 位标志**：`None`/`Mutable`/`Watching`/`RecursedCheck`/`Recursed`
  /`Dirty`/`Pending`，以及若干位组合常量（`TRACKABLE_FLAGS`、`RECURSION_FLAGS`、
  `DIRTY_OR_PENDING_FLAGS`、`PROPAGATION_GUARD_FLAGS`）。
- **位运算工具**：`hasFlag` / `addFlags` / `removeFlags` / `setFlags` 等，
  以及若干语义化的判定函数 (`isSignalNode`、`isMutableNode`、`isInactive`、
  `isDirtyValue` …)。
- **callable ↔ node 映射**：通过弱键表 `functionToNode` 将面向用户的闭包
  绑定回它所代表的节点，用于 `isSignal` 等判断。

### `graph.lua` — 双向链表依赖图

只关注"如何连接"，不掺杂任何业务语义。每个 `Link` 同时挂在两条链上：

- `dependency.subs / subsTail` —— 从依赖源出发，可遍历所有订阅者。
- `subscriber.deps / depsTail` —— 从订阅者出发，可遍历它读取过的所有依赖源。

对外暴露：
- `createLink` —— 创建 Link 节点结构体。
- `connect` —— 建立依赖关系，并尽量复用上一轮的旧 Link。
- `unlink` —— 同步从两条链上摘除一个 Link，并在依赖源失去所有
  订阅者时回调 `onDependencyBecameUnwatched`。
- `unlinkDepsReverse` —— 从 `depsTail` 反向摘除依赖，用于按 LIFO
  顺序清理嵌套 effect / scope。
- `unlinkStaleDeps` —— 跑完一次 effect/computed 后清理 `depsTail`
  之后残留的旧依赖。
- `validateDeps` / `validateSubs` —— 测试和调试
  时检查双链 Link 的不变量。
- `isLinkInCurrentDeps` —— 判断某个 Link 是否落在本轮已经
  重新追踪的前缀范围内（递归判定要用到）。

### `scheduler.lua` — 批量更新与 effect 调度

掌管 "什么时候运行 effect"，但不实际重跑 effect 本体（重跑动作由 `engine`
注入的 `runEffectHandler` 完成）：

- `startBatch` / `endBatch` / `getBatchDepth` —— 维护批量更新深度，深度归零时
  自动触发 `flush`。
- `enqueueEffect` —— 入队时会沿 `subs` 链向上收集嵌套父 effect，反向推入
  队列，保证内层与外层 effect 的执行顺序与平铺写法一致。
- `flush` —— 顺序消费队列，并通过 `pcall` 保证即便某个 effect 抛错，
  尚未执行的 effect 也会被恢复 `Watching` 标记，不至于让队列陷入半失效状态。

### `engine.lua` — 响应式核心算法

整套系统的"大脑"：负责依赖追踪、失效传播、脏值检查与 effect 重跑。它不创建
用户直接调用的函数，但提供给 `primitives` 几乎全部底层算子：

- **活动订阅者管理**：`setActiveSub` / `getActiveSub` / `callWithSub`，
  维护读取上下文与 `runDepth`，让 `trackRead` 知道该把依赖连到谁。
- **追踪生命周期**：`beginTrack` / `finishTrack` 推进
  `trackingVersion`、清空 `depsTail`、扫除旧依赖。
- **失效传播**：`propagate` 以显式栈代替递归遍历下游图，
  只做"标记+入队"，不立即重算。
- **脏值检查**：`checkDeps` / `computedNeedsRefresh` /
  `shouldRunEffect` 按需把 `Pending` 还原为 `Dirty` 或撤销，避免无意义重算。
- **节点重算**：`commitSignalValue` / `updateComputed` /
  `initComputed` / `runEffectBody` / `runCleanup` /
  `runQueuedEffect`。
- **资源回收**：`handleUnwatched` 在 `graph` 检测到依赖源无人订阅
  时被回调，安排无观察者的 computed 进入"懒态"，effect 进入停止流程。

启动末尾还把自身回调注入 `scheduler` 与 `graph`，闭合模块协作环。

### `tracer.lua` — 运行时追踪

默认关闭的教学/调试辅助模块。核心模块在关键路径上发出结构化事件，例如
`signal:set`、`propagate:visit`、`check:dep`、`effect:run:start`；是否输出、
输出到哪里、如何格式化，全部由外部 handler 决定。

它提供：

- `setHandler` / `clearHandler` —— 开关追踪。
- `consoleHandler` / `formatEvent` —— 把事件格式化为缩进文本日志。
- `nodeLabel` / `linkLabel` / `flagsText` —— 用稳定短标签解释节点、Link 和 flags。

普通运行不启用 handler 时不会打印任何内容。

### `primitives.lua` — 用户侧 API

把 `engine`、`graph`、`scheduler` 提供的算子组装成最终的响应式原语：

- `signal(initialValue)` —— 创建 `SIGNAL_MARKER` 节点；返回的 callable
  无参数即"读"，传入新值即"写"，写入时调用 `engine.propagate`
  传播失效。
- `computed(getter)` —— 创建 `COMPUTED_MARKER` 节点；读取时按需调用
  `computedNeedsRefresh` + `updateComputed`，惰性求值。
- `effect(fn)` —— 立即跑一次并注册依赖，返回 `stop` callable。支持
  通过 `fn` 返回 cleanup 函数，在重跑或停止前调用。
- `effectScope(fn)` —— 创建一个可批量回收子 effect 的作用域节点。
- `trigger(fn)` —— 临时 subscriber 收集 `fn` 中读到的依赖源，再对它们手动
  发起传播，用于"原地修改 signal 内部 table"这种 setter 无法感知的场景。
- `isSignal` / `isComputed` / `isEffect` / `isEffectScope` —— 通过
  `constants.functionToNode` 反查 callable 背后的节点类型。

启动末尾注册 `stopNode` 为 `engine.setStopHandler`，
让 `engine` 在节点失去全部订阅者时能够安全停止用户作用域。

## 模块依赖关系

```
init.lua
  └─ primitives.lua
        ├─ engine.lua
        │     ├─ graph.lua ──── constants.lua + tracer.lua
        │     ├─ scheduler.lua ─ constants.lua + tracer.lua
        │     ├─ tracer.lua ─── constants.lua
        │     └─ constants.lua
        ├─ graph.lua
        ├─ scheduler.lua
        ├─ tracer.lua
        └─ constants.lua
```

整体严格分层 + 少量"回调注入"反向连接：

- `constants` 是叶子模块，被所有人依赖，不依赖任何业务模块。
- `graph` / `scheduler` 依赖 `constants`，并向 `tracer` 发出可选事件。
- `tracer` 只依赖 `constants`，默认关闭；其它模块只向它发事件。
- `engine` 依赖 `constants` / `graph` / `scheduler` / `tracer`，并向后两者注入回调
  (`runEffectHandler`、`unwatched handler`) 形成协作环。
- `primitives` 依赖前面五者，并向 `engine` 注入 `stopNode`。
- `init` 只依赖 `primitives`、`scheduler`、`engine`、`constants`、`tracer`，
  仅做 API 聚合。

## 进一步阅读

每个核心模块都有独立的技术文档，深入描述设计动机、内部数据结构与关键算法：

- [`docs/constants.md`](docs/constants.md)
- [`docs/graph.md`](docs/graph.md)
- [`docs/scheduler.md`](docs/scheduler.md)
- [`docs/engine.md`](docs/engine.md)
- [`docs/state-machine.md`](docs/state-machine.md)
- [`docs/primitives.md`](docs/primitives.md)
- [`docs/effect-cleanup.md`](docs/effect-cleanup.md)
- [`docs/from-naive-map-to-link.md`](docs/from-naive-map-to-link.md)
- [`docs/runtime-tracing.md`](docs/runtime-tracing.md)
