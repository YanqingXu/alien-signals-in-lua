# Alien Signals - Lua Version

[EN README](README.en.md)

这是一个用 Lua 实现的响应式系统，它提供了类似于现代前端框架中的响应式编程能力。

## 核心概念

1. Signal（信号）
   - 用于存储和追踪响应式值
   - 当值发生变化时，会自动通知依赖它的计算属性和副作用

2. Computed（计算属性）
   - 基于其他响应式值的派生值
   - 只有在依赖的值发生变化时才会重新计算

3. Effect（副作用）
   - 响应式值变化时自动执行的函数
   - 用于处理副作用，如更新 UI、发送网络请求等

## 使用示例

```lua
local signal = require 'signal'
local computed = require 'computed'
local effect = require 'effect'

-- 创建响应式值
local count = signal.signal(0)
local doubled = computed.computed(function()
    return count:get() * 2
end)

-- 创建副作用
effect.effect(function()
    print("Count:", count:get())
    print("Doubled:", doubled:get())
end)

-- 修改值，会自动触发相关的计算和副作用
count:set(1)  -- 输出: Count: 1, Doubled: 2
count:set(2)  -- 输出: Count: 2, Doubled: 4
```

## 实现细节

系统使用了以下技术来实现响应式：

1. 依赖追踪
   - 使用 Lua 的元表（metatable）实现对象系统
   - 通过全局状态追踪当前正在执行的计算或副作用
   - 自动收集和管理依赖关系

2. 批量更新
   - 支持批量更新以提高性能
   - 使用队列管理待执行的副作用

3. 脏值检查
   - 智能的脏值检查机制
   - 只在必要时重新计算派生值

## 注意事项

1. 性能考虑
   - 尽量避免在一个计算属性中访问太多的响应式值
   - 合理使用批量更新来提高性能

2. 内存管理
   - 系统会自动管理依赖关系
   - 不再使用的响应式值会被自动清理

## 许可证

MIT License
