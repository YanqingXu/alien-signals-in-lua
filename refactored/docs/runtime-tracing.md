# Runtime Tracing — 从执行日志理解响应式链路

`tracer.lua` 提供一个默认关闭的运行时追踪层。核心模块只发出结构化事件，
不直接 `print`，因此普通运行和测试不会产生额外输出；教学或调试时再注入
handler 即可。

## 快速使用

```lua
local reactive = require("refactored")
local tracer = require("refactored.tracer")

tracer.reset()
tracer.setHandler(tracer.consoleHandler())

local count = reactive.signal(0)
local stop = reactive.effect(function()
    count()
end)

count(1)
stop()

tracer.clearHandler()
```

也可以通过统一入口设置：

```lua
local reactive = require("refactored")

reactive.setTraceHandler(reactive.tracer.consoleHandler())
```

## 一条事件包含什么

每次 `tracer.emit(name, node, data)` 会生成一个事件表：

| 字段 | 含义 |
| --- | --- |
| `seq` | 全局递增序号，方便还原真实执行顺序 |
| `name` | 事件名，例如 `signal:set`、`propagate:visit` |
| `nodeType` | `signal` / `computed` / `effect` / `scope` |
| `nodeLabel` | 稳定的教学标签，例如 `signal#1` |
| `flagsText` | 当前节点 flags 的可读文本 |
| `depth` | 缩进层级，用来展示嵌套执行阶段 |
| `data` | 事件携带的结构化上下文，例如 `dep`、`sub`、`link`、`changed` |

节点和 Link 的编号只在追踪器里维护，使用弱键表保存，不会参与响应式算法。

## 关键事件路线

一次 `signal` 更新触发 `effect` 的典型路线如下：

```text
signal:set
propagate:start
  propagate:visit
  effect:enqueue
propagate:end
flush:start
  flush:run
  effect:dequeue
  check:start
    check:dep
    check:dirty
    signal:commit
    check:changed
  check:end
  effect:should-run
  effect:run:start
    track:begin
    signal:read
    track:read
    graph:reuse
    track:end
  effect:run:end
flush:end
```

这条日志对应两个阶段：

- **PUSH**：`signal:set` 后进入 `propagate`，只打 `Pending/Dirty` 标记并把
  effect 入队。
- **PULL**：`flush` 时进入 `check`，确认依赖是否真的变化，然后才重跑 effect。

## 事件命名约定

| 前缀 | 关注点 |
| --- | --- |
| `node:*` | 节点创建、无人订阅等生命周期 |
| `signal:*` | signal 写入、读取、提交 pending 值 |
| `computed:*` | computed 首次激活、按需重算、是否需要刷新 |
| `track:*` | active subscriber 追踪与依赖读取 |
| `graph:*` | Link 创建、复用、解绑和依赖源无人订阅 |
| `propagate:*` | PUSH 阶段的失效传播 |
| `check:*` | PULL 阶段的脏值确认 |
| `effect:*` | effect 入队、出队、运行、跳过和 cleanup |
| `flush:*` | 调度队列消费与错误恢复 |
| `batch:*` | batch 嵌套深度变化 |

## 自定义输出

`consoleHandler()` 只是默认文本格式。你可以收集结构化事件后做任意展示：

```lua
local events = {}

tracer.setHandler(function(event)
    events[#events + 1] = event
end)
```

例如：

- 生成一段 Markdown 教学日志。
- 把 `graph:connect` / `graph:unlink` 转成 Mermaid 图。
- 只过滤 `check:*` 事件来观察脏值检查。
- 按 `nodeLabel` 聚合，查看某个 computed 的完整生命周期。

## 非侵入性边界

- 默认 handler 为 `nil`，未启用时不会打印任何内容。
- 如果 handler 自己抛错，tracer 会记录 `getLastError()` 并自动关闭追踪，
  避免日志系统破坏响应式运行。
- `tracer.reset()` 只重置追踪序号、缩进层级和调试 ID，不会修改任何响应式节点。

可以直接运行示例：

```bash
lua refactored/examples/trace_signal_to_effect.lua
```
