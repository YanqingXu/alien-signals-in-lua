# Alien Signals - Lua响应式编程系统

[English README](README.en.md)

## 项目简介

Alien Signals是一个用Lua语言实现的高效响应式编程系统，受到现代前端框架（如Vue、React）响应式系统的启发。它通过简洁而强大的API，为Lua应用提供自动依赖追踪和响应式数据流管理能力。

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
   - 用于处理副作用，如更新UI、发送网络请求等
   - 支持清理和取消订阅

4. EffectScope（副作用作用域）
   - 用于批量管理和清理多个响应式副作用函数
   - 简化复杂系统中的内存管理
   - 支持嵌套作用域结构

## 使用示例

```lua
local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local effectScope = reactive.effectScope

-- 创建响应式值
local count = signal(0)
local doubled = computed(function()
    return count() * 2
end)

-- 创建副作用
local stopEffect = effect(function()
    print("计数:", count())
    print("双倍:", doubled())
end)
-- 输出: 计数: 0, 双倍: 0

-- 修改值，会自动触发相关的计算和副作用
count(1)  -- 输出: 计数: 1, 双倍: 2
count(2)  -- 输出: 计数: 2, 双倍: 4

-- 停止副作用监听
stopEffect()
count(3)  -- 不会触发任何输出

-- 使用副作用作用域
local cleanup = effectScope(function()
    -- 在作用域内创建的所有副作用函数
    effect(function()
        print("作用域内副作用:", count())
    end)
    
    effect(function()
        print("另一个副作用:", doubled())
    end)
end)

count(4)  -- 触发作用域内的所有副作用函数
cleanup()  -- 清理作用域内的所有副作用函数
count(5)  -- 不会触发任何输出
```

## 高级功能

### 批量更新

在进行多个状态更新时，可以使用批量更新模式避免多次触发副作用，提高性能。

```lua
local reactive = require("reactive")
local signal = reactive.signal
local effect = reactive.effect
local startBatch = reactive.startBatch
local endBatch = reactive.endBatch

local count = signal(0)
local multiplier = signal(1)

effect(function()
    print("结果:", count() * multiplier())
end)
-- 输出：结果: 0

-- 不使用批量更新：副作用会执行两次
count(5) -- 输出：结果: 5
multiplier(2) -- 输出：结果: 10

-- 使用批量更新：副作用只执行一次
startBatch()
count(10)
multiplier(3)
endBatch() -- 输出：结果: 30
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

3. 脏值检查与优化
   - 采用位运算的高效脏值检查机制
   - 智能判断何时需要重新计算派生值
   - 精确的依赖图遍历算法

4. 更新调度系统
   - 使用队列管理待执行的副作用函数
   - 智能合并多次更新，减少不必要的计算
   - 支持批量更新以提高性能

## 注意事项

1. 性能优化
   - 尽量避免在一个计算属性中访问太多的响应式值
   - 合理使用批量更新来提高性能
   - 不要在计算属性内部修改其他响应式值

2. 循环依赖
   - 虽然系统能够智能处理一定程度的循环依赖
   - 但仍建议避免复杂的循环依赖关系
   - 使用位运算标记位避免无限递归和栈溢出

3. 内存管理
   - 系统会自动管理依赖关系
   - 不再使用的副作用会被自动清理
   - 使用 effectScope 管理复杂组件的多个副作用函数

## 完整API参考

```lua
local reactive = require("reactive")

-- 核心API
local signal = reactive.signal       -- 创建响应式信号
local computed = reactive.computed   -- 创建计算属性  
local effect = reactive.effect       -- 创建副作用
local effectScope = reactive.effectScope  -- 创建副作用作用域

-- 批量处理API
local startBatch = reactive.startBatch  -- 开始批量更新
local endBatch = reactive.endBatch      -- 结束批量更新并执行更新
```

## 许可证

本项目使用[LICENSE](LICENSE)许可证。
