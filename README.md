# Alien Signals - Lua Version

[EN README](README.en.md)

这是一个用 Lua 实现的响应式系统，它提供了类似于现代前端框架中的响应式编程能力。通过简洁的 API，它支持响应式数据流管理和自动依赖追踪。

## 核心概念

1. Signal（信号）
   - 用于存储和追踪响应式值
   - 当值发生变化时，会自动通知依赖它的计算属性和副作用
   - 通过函数调用方式直接读取和修改值

2. Computed（计算属性）
   - 基于其他响应式值的派生值
   - 只有在依赖的值发生变化时才会重新计算
   - 自动缓存结果，避免重复计算

3. Effect（副作用）
   - 响应式值变化时自动执行的函数
   - 用于处理副作用，如更新 UI、发送网络请求等
   - 支持清理和取消订阅

4. EffectScope（副作用作用域）
   - 用于批量管理和清理多个响应式副作用函数
   - 简化复杂系统中的内存管理

## 使用示例

```lua
local signal = require 'signal'
local computed = require 'computed'
local effect = require 'effect'

-- 创建响应式值
local count = signal.signal(0)
local doubled = computed.computed(function()
    return count() * 2
end)

-- 创建副作用
local stopEffect = effect.effect(function()
    print("Count:", count())
    print("Doubled:", doubled())
end)

-- 修改值，会自动触发相关的计算和副作用
count(1)  -- 输出: Count: 1, Doubled: 2
count(2)  -- 输出: Count: 2, Doubled: 4

-- 停止副作用监听
stopEffect()
count(3)  -- 不会触发任何输出

-- 使用副作用作用域
local cleanup = effect.effectScope(function()
    -- 在作用域内创建的所有副作用函数
    effect.effect(function()
        print("Scoped effect:", count())
    end)
    
    effect.effect(function()
        print("Another effect:", doubled())
    end)
end)

count(4)  -- 触发作用域内的所有副作用函数
cleanup()  -- 清理作用域内的所有副作用函数
count(5)  -- 不会触发任何输出
```

## 实现细节

系统使用了以下技术来实现响应式：

1. 依赖追踪
   - 使用函数闭包和绑定机制实现对象系统
   - 通过全局状态追踪当前正在执行的计算或副作用
   - 自动收集和管理依赖关系，构建响应式数据依赖图

2. 双向链表依赖管理
   - 使用高效的双向链表结构管理依赖关系
   - O(1)时间复杂度的依赖添加和删除操作
   - 自动清理不再需要的依赖，避免内存泄漏

3. 批量更新
   - 支持批量更新以提高性能
   - 使用队列管理待执行的副作用函数
   - 智能合并多次更新，减少不必要的计算

4. 脏值检查
   - 采用位运算的高效脏值检查机制
   - 只在必要时重新计算派生值
   - 精确的依赖图遍历算法

## 高级功能

1. 批处理操作
   ```lua
   global.startBatch()
   -- 多次修改信号值，不会立即触发副作用函数
   count(10)
   count(20)
   count(30)
   global.endBatch() -- 在这里统一触发一次副作用函数
   ```

2. 处理循环依赖
   - 系统能够智能处理响应式值之间的循环依赖
   - 使用标记位避免无限递归和栈溢出

## 注意事项

1. 性能考虑
   - 尽量避免在一个计算属性中访问太多的响应式值
   - 合理使用批量更新来提高性能
   - 不要在计算属性内部修改其他响应式值

2. 内存管理
   - 系统会自动管理依赖关系
   - 不再使用的响应式值会被自动清理
   - 使用 effectScope 管理复杂组件的副作用函数

## 许可证

MIT License
