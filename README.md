# Alien Signals - Lua响应式编程系统

**版本: 3.0.0** - 兼容 alien-signals v3.0.0

[English README](README.en.md)

## 项目简介

本项目移植自[stackblitz/alien-signals](https://github.com/stackblitz/alien-signals)，是原TypeScript版本响应式系统的Lua实现。

Alien Signals是一个高效的响应式编程系统，它通过简洁而强大的API，为应用提供自动依赖追踪和响应式数据流管理能力。

### 3.0.0 版本新特性 🎉

- **新增类型检测函数**: `isSignal`, `isComputed`, `isEffect`, `isEffectScope` - 运行时检测响应式原语类型
- **新增Getter函数**: `getActiveSub`, `getBatchDepth` - 查询当前响应式上下文状态
- **API重命名**: `setCurrentSub/getCurrentSub` → `setActiveSub/getActiveSub` (更清晰的命名)
- **移除废弃API**: `pauseTracking`, `resumeTracking`, `setCurrentScope`, `getCurrentScope`
- **性能优化**: 
  - Computed首次访问快速路径
  - 内联Pending标志清除操作
  - 避免不必要的activeSub访问
  - 优化依赖清理流程
- **内部改进**: 
  - 分离effectOper和effectScopeOper
  - 简化父子层级关系建立
  - 改进unwatched节点类型识别
- **完全兼容**: 与 alien-signals v3.0.0 完全同步

> 📖 详细的升级指南请参阅 [UPGRADE_TO_3.0.0.md](UPGRADE_TO_3.0.0.md)

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

##### HybridReactive - Vue.js风格的响应式API

除了底层的响应式系统，本项目还提供了一个类似Vue.js的高级响应式API - HybridReactive，它提供了更加友好和直观的接口。

#### HybridReactive - Vue.js风格API

**核心API：**
- `ref(value)` - 创建响应式引用
- `reactive(obj, shallow)` - 将对象转换为响应式对象（支持深层/浅层响应式）
- `computed(fn)` - 创建计算属性

**监听API：**
- `watch(callback)` - 监听响应式数据变化
- `watchRef(ref, callback)` - 监听ref对象变化
- `watchReactive(reactive, callback, shallow)` - 监听reactive对象属性变化

**工具函数：**
- `isRef(value)` - 检查是否为ref对象
- `isReactive(value)` - 检查是否为响应式对象

### 基本用法

```lua
local HybridReactive = require("HybridReactive")

-- 创建响应式引用
local count = HybridReactive.ref(0)
local name = HybridReactive.ref("Alice")

-- 访问和修改值
print(count.value)  -- 0
count.value = 10
print(count.value)  -- 10

-- 创建计算属性
local doubled = HybridReactive.computed(function()
    return count.value * 2
end)

print(doubled.value)  -- 20

-- 创建响应式对象
local state = HybridReactive.reactive({
    user = "Bob",
    age = 25
})

print(state.user)  -- Bob
state.age = 30
print(state.age)   -- 30

#### `reactive(obj, shallow)`

将普通对象转换为响应式对象。

**参数：**
- `obj`: 要转换的对象
- `shallow`: 可选，布尔值，默认为 `false`
  - `false`（默认）：深层响应式，嵌套对象也会被转换为响应式
  - `true`：浅层响应式，只有第一层属性是响应式的

**深层响应式（默认行为）：**
```lua
local obj = HybridReactive.reactive({
    user = {
        name = "Alice",
        profile = {
            age = 25,
            address = { city = "Beijing" }
        }
    }
})

-- 所有嵌套对象都是响应式的
print(HybridReactive.isReactive(obj.user))                    -- true
print(HybridReactive.isReactive(obj.user.profile))           -- true
print(HybridReactive.isReactive(obj.user.profile.address))   -- true

-- 可以监听任何层级的变化
obj.user.name = "Bob"                    -- 触发响应式更新
obj.user.profile.age = 30                -- 触发响应式更新
obj.user.profile.address.city = "Shanghai"  -- 触发响应式更新
```

**浅层响应式：**
```lua
local obj = HybridReactive.reactive({
    user = { name = "Alice", age = 25 },
    settings = { theme = "light" }
}, true)  -- shallow = true

-- 只有第一层是响应式的
print(HybridReactive.isReactive(obj.user))     -- false
print(HybridReactive.isReactive(obj.settings)) -- false

-- 只能监听第一层的变化
obj.user = { name = "Bob", age = 30 }      -- 触发响应式更新
obj.user.name = "Charlie"                  -- 不会触发响应式更新（user不是响应式的）
```

### watchRef - 专门监听ref对象的变化

`watchRef` 是一个专门用于监听 ref 对象变化的函数，它会在 ref 的值发生变化时调用回调函数，并提供新值和旧值作为参数。

#### 语法

```lua
local stopWatching = HybridReactive.watchRef(refObj, callback)
```

- `refObj`: 要监听的 ref 对象
- `callback`: 回调函数，接收 `(newValue, oldValue)` 两个参数
- 返回值: 停止监听的函数

#### 使用示例

```lua
local HybridReactive = require("HybridReactive")

-- 监听数字变化
local counter = HybridReactive.ref(0)

local stopWatching = HybridReactive.watchRef(counter, function(newValue, oldValue)
    print(string.format("计数器从 %d 变为 %d", oldValue, newValue))
end)

counter.value = 1  -- 输出: 计数器从 0 变为 1
counter.value = 5  -- 输出: 计数器从 1 变为 5
counter.value = 5  -- 不会触发回调（值未变化）

-- 停止监听
stopWatching()
counter.value = 10 -- 不会触发回调

-- 监听字符串变化
local username = HybridReactive.ref("guest")

HybridReactive.watchRef(username, function(newValue, oldValue)
    print(string.format("用户名从 '%s' 变为 '%s'", oldValue, newValue))
end)

username.value = "alice"  -- 输出: 用户名从 'guest' 变为 'alice'

-- 监听布尔值变化
local isLoggedIn = HybridReactive.ref(false)

HybridReactive.watchRef(isLoggedIn, function(newValue, oldValue)
    if newValue then
        print("用户已登录！")
    else
        print("用户已登出！")
    end
end)

isLoggedIn.value = true   -- 输出: 用户已登录！
isLoggedIn.value = false  -- 输出: 用户已登出！

-- 监听对象变化
local userProfile = HybridReactive.ref({
    name = "John",
    age = 25
})

HybridReactive.watchRef(userProfile, function(newValue, oldValue)
    print("用户资料已更新")
    print("旧资料:", oldValue.name, oldValue.age)
    print("新资料:", newValue.name, newValue.age)
end)

userProfile.value = { name = "Jane", age = 30 }
-- 输出:
-- 用户资料已更新
-- 旧资料: John 25
-- 新资料: Jane 30
```

#### watchRef 特性

1. **类型安全**: 只能监听 ref 对象，传入非 ref 对象会抛出错误
2. **值比较**: 只有在值真正发生变化时才会触发回调
3. **新旧值**: 回调函数同时接收新值和旧值，方便进行比较和处理
4. **清理功能**: 返回停止监听的函数，支持手动清理
5. **多监听器**: 同一个 ref 可以被多个 watchRef 监听

#### 错误处理

```lua
-- 错误：第一个参数必须是 ref 对象
local success, err = pcall(function()
    HybridReactive.watchRef({}, function() end)
end)
print(err)  -- "watchRef: first parameter must be a ref object"

-- 错误：第二个参数必须是函数
local success, err = pcall(function()
    HybridReactive.watchRef(HybridReactive.ref(1), "not a function")
end)
print(err)  -- "watchRef: second parameter must be a function"
```

### watchReactive - 监听响应式对象的变化

`watchReactive` 是一个专门用于监听 reactive 对象属性变化的函数，它会在 reactive 对象的任何属性发生变化时调用回调函数。

#### 语法

```lua
local stopWatching = HybridReactive.watchReactive(reactiveObj, callback, shallow)
```

- `reactiveObj`: 要监听的 reactive 对象
- `callback`: 回调函数，接收 `(key, newValue, oldValue, path)` 四个参数
- `shallow`: 可选，布尔值，默认为 `false`
  - `false`（默认）：深层监听，递归监听嵌套对象的变化
  - `true`：浅层监听，只监听第一层属性的变化
- 返回值: 停止监听的函数

#### 基础使用示例

```lua
local HybridReactive = require("HybridReactive")

-- 创建响应式对象
local user = HybridReactive.reactive({
    name = "Alice",
    age = 25,
    profile = {
        email = "alice@example.com",
        settings = {
            theme = "light"
        }
    }
})

-- 深层监听（默认）
local stopWatching = HybridReactive.watchReactive(user, function(key, newValue, oldValue, path)
    print(string.format("属性 '%s' 在路径 '%s' 从 '%s' 变为 '%s'",
          key, path or key, tostring(oldValue), tostring(newValue)))
end)

user.name = "Bob"                           -- 输出: 属性 'name' 在路径 'name' 从 'Alice' 变为 'Bob'
user.profile.email = "bob@example.com"      -- 输出: 属性 'email' 在路径 'profile.email' 从 'alice@example.com' 变为 'bob@example.com'
user.profile.settings.theme = "dark"       -- 输出: 属性 'theme' 在路径 'profile.settings.theme' 从 'light' 变为 'dark'

-- 停止监听
stopWatching()
user.name = "Charlie"  -- 不会触发回调
```

#### 浅层 vs 深层监听

```lua
local obj = HybridReactive.reactive({
    user = {
        name = "Alice",
        profile = { age = 25 }
    }
})

-- 浅层监听
local stopShallow = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print("浅层监听:", key, path)
end, true)  -- shallow = true

-- 深层监听
local stopDeep = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print("深层监听:", key, path)
end, false)  -- shallow = false

-- 替换整个 user 对象（两者都会触发）
obj.user = { name: "Bob", profile: { age: 30 } }
-- 输出:
-- 浅层监听: user user
-- 深层监听: user user

-- 修改嵌套属性（只有深层监听会触发）
obj.user.name = "Charlie"
-- 输出:
-- 深层监听: name user.name

obj.user.profile.age = 35
-- 输出:
-- 深层监听: age user.profile.age

stopShallow()
stopDeep()
```

#### 相同属性名在不同层级的处理

`watchReactive` 能够准确区分不同层级的相同属性名：

```lua
local obj = HybridReactive.reactive({
    name = "root-name",           -- 根级 name
    user = {
        name = "user-name",       -- 用户级 name
        profile = {
            name = "profile-name" -- 配置级 name
        }
    }
})

HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print(string.format("属性 '%s' 在路径 '%s' 发生变化", key, path))
end, false)

obj.name = "new-root-name"                    -- 输出: 属性 'name' 在路径 'name' 发生变化
obj.user.name = "new-user-name"              -- 输出: 属性 'name' 在路径 'user.name' 发生变化
obj.user.profile.name = "new-profile-name"   -- 输出: 属性 'name' 在路径 'user.profile.name' 发生变化
```

#### 对象替换与深层监听

当替换整个对象时，`watchReactive` 会自动为新对象设置深层监听：

```lua
local obj = HybridReactive.reactive({
    data = {
        value = 10,
        nested = { count: 5 }
    }
})

HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print("变化:", path, "->", newValue)
end, false)

-- 替换整个 data 对象
obj.data = { value: 20, nested: { count: 10 } }  -- 触发回调

-- 修改新对象的属性（仍然能被监听到）
obj.data.value = 30        -- 触发回调
obj.data.nested.count = 15 -- 触发回调
```

#### watchReactive 特性

1. **深层监听**: 默认递归监听所有嵌套对象的变化
2. **路径跟踪**: 提供完整的属性路径信息，准确定位变化位置
3. **相同Key区分**: 能够区分不同层级的相同属性名
4. **对象替换支持**: 对象替换后自动为新对象设置监听
5. **类型安全**: 只能监听 reactive 对象，传入非 reactive 对象会抛出错误
6. **值比较**: 只有在值真正发生变化时才会触发回调
7. **清理功能**: 返回停止监听的函数，支持手动清理
8. **多监听器**: 同一个 reactive 对象可以被多个 watchReactive 监听

#### 错误处理

```lua
-- 错误：第一个参数必须是 reactive 对象
local success, err = pcall(function()
    HybridReactive.watchReactive({}, function() end)
end)
print(err)  -- "watchReactive: first parameter must be a reactive object"

-- 错误：第二个参数必须是函数
local success, err = pcall(function()
    HybridReactive.watchReactive(HybridReactive.reactive({}), "not a function")
end)
print(err)  -- "watchReactive: second parameter must be a function"
```

### 工具函数

```lua
-- 检查是否为 ref 对象
local isRefObj = HybridReactive.isRef(count)     -- true
local isRefObj = HybridReactive.isRef(state)     -- false

-- 检查是否为响应式对象
local isReactiveObj = HybridReactive.isReactive(state)  -- true
local isReactiveObj = HybridReactive.isReactive(count)  -- false
```

## HybridReactive 测试套件

为了确保 HybridReactive 功能的稳定性和正确性，项目提供了全面的测试套件。

### 测试文件

- **`test_hybrid_reactive.lua`** - 综合测试套件，包含所有 HybridReactive 功能的测试
- **`run_hybrid_reactive_tests.lua`** - 专用测试运行器

### 运行测试

```bash
# 运行完整的 HybridReactive 测试套件
lua run_hybrid_reactive_tests.lua

# 或直接运行测试文件
lua test_hybrid_reactive.lua
```

### 测试覆盖范围

测试套件分为 **6 个主要部分**，共 **17 个综合测试用例**：

#### 1. 基础功能测试
- 基础回调功能验证
- 浅层 vs 深层监听测试
- 多个监听器协同工作
- 监听器生命周期管理

#### 2. 路径跟踪和相同Key测试
- 不同层级相同属性名的区分（`obj.name` vs `obj.user.name`）
- 深层嵌套路径的准确性验证

#### 3. 高级功能测试
- 对象替换后的深层监听
- 混合数据类型处理
- 批量操作支持

#### 4. 错误处理和边缘情况
- 无效参数的错误处理
- 循环引用场景的稳定性

#### 5. 性能测试
- 大对象性能（500+ 属性）
- 深层嵌套性能（20+ 层）
- 多监听器性能（50+ 监听器）

#### 6. 集成测试
- 与 `ref` 对象的集成
- 快速连续修改的压力测试

### 性能基准

在标准测试环境下的性能表现：
- **500属性对象设置**: ~2ms
- **50个监听器设置**: ~1ms
- **100次快速修改**: ~2ms
- **20层深度嵌套**: ~1ms

### 测试结果示例

```
========== Comprehensive HybridReactive.watchReactive Test Suite ==========

SECTION 1: Basic Functionality Tests
=====================================
[OK] Basic callback functionality
[OK] Shallow vs deep monitoring
[OK] Multiple watchers on same object
[OK] Watcher lifecycle and cleanup

SECTION 2: Path Tracking and Same Key Tests
============================================
[OK] Same key at different levels
[OK] Path tracking accuracy

... (其他部分)

[OK] ALL WATCHREACTIVE TESTS COMPLETED SUCCESSFULLY! [OK]
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

### v3.0.0 新功能

#### 类型检测函数

v3.0.0 新增了运行时类型检测函数，用于判断值是否为特定的响应式原语：

```lua
local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local effectScope = reactive.effectScope

-- 创建响应式原语
local count = signal(0)
local doubled = computed(function() return count() * 2 end)
local stopEffect = effect(function() print(count()) end)
local stopScope = effectScope(function() end)

-- 类型检测
print(reactive.isSignal(count))        -- true
print(reactive.isSignal(doubled))      -- false

print(reactive.isComputed(doubled))    -- true
print(reactive.isComputed(count))      -- false

print(reactive.isEffect(stopEffect))   -- true
print(reactive.isEffectScope(stopScope)) -- true
```

#### 获取响应式上下文状态

v3.0.0 新增了查询当前响应式上下文的函数：

```lua
local reactive = require("reactive")
local signal = reactive.signal
local effect = reactive.effect

-- 获取批量更新深度
print(reactive.getBatchDepth())  -- 0

reactive.startBatch()
print(reactive.getBatchDepth())  -- 1

reactive.startBatch()
print(reactive.getBatchDepth())  -- 2

reactive.endBatch()
print(reactive.getBatchDepth())  -- 1

reactive.endBatch()
print(reactive.getBatchDepth())  -- 0

-- 获取当前活动订阅者
local count = signal(0)
print(reactive.getActiveSub() == nil)  -- true

effect(function()
    count()
    -- 在effect内部，getActiveSub会返回当前effect
    local sub = reactive.getActiveSub()
    print(sub ~= nil)  -- true
end)

-- effect外部
print(reactive.getActiveSub() == nil)  -- true
```

#### API更名说明

为了更清晰的语义，v3.0.0对部分API进行了重命名：

```lua
-- v2.0.7 (旧API)
local prevSub = reactive.setCurrentSub(nil)
reactive.setCurrentSub(prevSub)

-- v3.0.0 (新API)
local prevSub = reactive.setActiveSub(nil)
reactive.setActiveSub(prevSub)
```

> ⚠️ **重要**: `pauseTracking`/`resumeTracking` 和 `setCurrentScope`/`getCurrentScope` 已在v3.0.0中移除。
> 如需暂停追踪，请使用 `setActiveSub(nil)` 代替。



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

## 链表结构详解

Alien Signals 的核心是通过双向链表（doubly-linked list）结构实现的依赖追踪系统。每个链接节点同时存在于两个不同的链表中，实现了高效的依赖收集和通知传播。

### 链表节点结构

每个链接节点包含以下字段：

```lua
{
    dep = dep,        -- 依赖对象（Signal或Computed）
    sub = sub,        -- 订阅者对象（Effect或Computed）
    prevSub = prevSub, -- 订阅者链表中的前一个节点
    nextSub = nextSub, -- 订阅者链表中的下一个节点
    prevDep = prevDep, -- 依赖链表中的前一个节点
    nextDep = nextDep  -- 依赖链表中的下一个节点
}
```

### 双向链表示意图

系统中的链表结构可以表示为如下形式：

```
依赖关系图结构：

+-------------+          +--------------+          +--------------+
|    Signal   |          |   Computed   |          |    Effect    |
|  (数据源)    |          | (计算属性)    |          |  (副作用)     |
+-------------+          +--------------+          +--------------+
       ^                        ^                         ^
       |                        |                         |
       |                        |                         |
       v                        v                         v
+-----------------+    +-----------------+    +-----------------+
| 订阅者链表 (垂直) |    | 订阅者链表 (垂直) |    | 订阅者链表 (垂直) |
+-----------------+    +-----------------+    +-----------------+
       ^                        ^                         ^
       |                        |                         |
       |                        |                         |
+======================================================================================================================+
|                                            链接节点(Link)                                                           |
+======================================================================================================================+
       |                        |                         |
       |                        |                         |
       v                        v                         v
+-----------------+    +-----------------+    +-----------------+
|  依赖链表 (水平)  |    |  依赖链表 (水平)  |    |  依赖链表 (水平)  |
+-----------------+    +-----------------+    +-----------------+
```

### 链接(link)过程

当一个响应式对象（如Signal或Computed）被访问时，系统会建立它与当前活跃副作用（Effect）之间的依赖关系：

1. 检查重复依赖，避免同一依赖被多次添加
2. 处理循环依赖情况，防止无限递归
3. 创建新的链接节点，同时插入两个链表
4. 更新双向链表的前后指针，确保完整的链表结构

```
初始状态:
Signal A     Effect 1
 subs=nil     deps=nil
 
执行 reactive.link(Signal A, Effect 1):

创建新链接节点：
+-------------------+
| Link {            |
|   dep = Signal A  |
|   sub = Effect 1  |
|   prevSub = nil   |
|   nextSub = nil   |
|   prevDep = nil   |
|   nextDep = nil   |
| }                 |
+-------------------+

更新Signal A和Effect 1:
Signal A            Effect 1
 subs=Link           deps=Link
 subsTail=Link       depsTail=Link
```

### 解除链接(unlink)过程

当依赖关系不再需要时（例如，副作用被清理或重新执行不再需要特定依赖），系统会移除这些依赖关系：

1. 从依赖链表中移除链接节点（水平方向）
2. 从订阅者链表中移除链接节点（垂直方向）
3. 处理特殊情况，如最后一个订阅者被移除时的清理

```
初始状态:
Signal A                 Effect 1
 subs=Link                deps=Link
 subsTail=Link            depsTail=Link
 
   +-------------------+
   | Link {            |
   |   dep = Signal A  |
   |   sub = Effect 1  |
   |   prevSub = nil   |
   |   nextSub = nil   |
   |   prevDep = nil   |
   |   nextDep = nil   |
   | }                 |
   +-------------------+

执行 reactive.unlink(Link, Effect 1):

移除链接:
Signal A           Effect 1
 subs=nil           deps=nil
 subsTail=nil       depsTail=nil
```

### 复杂场景示例

在实际应用中，依赖关系网络可能非常复杂：

```
Signal A ---> Effect 1 ---> Signal B ---> Effect 2
    |                           |
    |                           v
    +----------------------> Computed C ---> Effect 3
                               |
                               v
                            Signal D
```

这种复杂的依赖关系通过双向链表结构高效管理，实现了O(1)时间复杂度的依赖操作。

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

4. Lua 5.1 兼容性
   - 支持Lua 5.1
   - 所有示例和测试都兼容Lua 5.1和更新版本

## 完整API参考

### 底层响应式系统 (reactive.lua) - v3.0.0

```lua
local reactive = require("reactive")

-- 核心响应式原语
local signal = reactive.signal           -- 创建响应式信号
local computed = reactive.computed       -- 创建计算值
local effect = reactive.effect           -- 创建响应式副作用
local effectScope = reactive.effectScope -- 创建副作用作用域

-- 批量操作工具
local startBatch = reactive.startBatch   -- 开始批量更新
local endBatch = reactive.endBatch       -- 结束批量更新并刷新

-- 高级控制 API (v3.0.0)
local setActiveSub = reactive.setActiveSub       -- 设置当前活动订阅者 (v3.0.0重命名)
local getActiveSub = reactive.getActiveSub       -- 获取当前活动订阅者 (v3.0.0重命名)
local getBatchDepth = reactive.getBatchDepth     -- 获取批量更新深度 (v3.0.0新增)

-- 类型检测 API (v3.0.0新增)
local isSignal = reactive.isSignal               -- 检测是否为Signal
local isComputed = reactive.isComputed           -- 检测是否为Computed
local isEffect = reactive.isEffect               -- 检测是否为Effect
local isEffectScope = reactive.isEffectScope     -- 检测是否为EffectScope

-- 已移除的API (v3.0.0)
-- ❌ pauseTracking - 使用 setActiveSub(nil) 代替
-- ❌ resumeTracking - 使用 setActiveSub(prevSub) 代替
-- ❌ setCurrentScope - 已移除
-- ❌ getCurrentScope - 已移除
```

### HybridReactive - Vue.js风格API (v3.0.0)

```lua
local HybridReactive = require("HybridReactive")

-- 响应式数据创建
local ref = HybridReactive.ref           -- 创建响应式引用
local reactive = HybridReactive.reactive -- 创建响应式对象
local computed = HybridReactive.computed -- 创建计算属性

-- 监听 API
local watch = HybridReactive.watch             -- 通用监听函数（effect 的别名）
local watchRef = HybridReactive.watchRef       -- 专门监听 ref 对象
local watchReactive = HybridReactive.watchReactive -- 专门监听响应式对象

-- 工具函数
local isRef = HybridReactive.isRef           -- 检查是否为 ref 对象
local isReactive = HybridReactive.isReactive -- 检查是否为响应式对象

-- 批量操作（从 reactive 模块暴露）
local startBatch = HybridReactive.startBatch -- 开始批量更新
local endBatch = HybridReactive.endBatch     -- 结束批量更新
```

### v3.0.0 版本技术特性

#### 类型标记系统
```lua
-- 唯一类型标记
local SIGNAL_MARKER = {}
local COMPUTED_MARKER = {}
local EFFECT_MARKER = {}
local EFFECTSCOPE_MARKER = {}

-- 类型检测实现
function reactive.isSignal(obj)
    if type(obj) ~= "function" then return false end
    
    -- 通过debug库检查upvalue中的标记
    local i = 1
    while true do
        local name, value = debug.getupvalue(obj, i)
        if not name then break end
        if name == "obj" then
            return value._marker == SIGNAL_MARKER
        end
        i = i + 1
    end
    return false
end
```

#### 优化的计算属性初始化
```lua
-- v3.0.0: 移除了Dirty标志位，优化首次计算路径
function reactive.computed(getter)
    local obj = {
        _getter = getter,
        _value = nil,
        _flags = 0,  -- v3.0.0: 初始为0，不再包含Dirty标志
        _marker = COMPUTED_MARKER
    }
    
    -- 首次访问直接计算
    return function()
        if obj._flags == 0 then
            -- 快速路径：首次计算
            local success, result = pcall(updateComputed, obj)
            if success then
                return result
            end
        end
        -- ...
    end
end
```

#### 内联追踪优化
```lua
-- v3.0.0: 移除了startTracking/endTracking，直接内联追踪逻辑
function run(obj)
    -- 直接内联检查和设置
    local shouldCleanup = obj._flags & RunningFlags ~= 0
    if shouldCleanup then
        obj._flags = obj._flags | NotifiedFlag
    end
    
    if shouldCleanup then
        purgeDeps(obj)
    end
    
    -- 设置活动订阅者
    local prevSub = g_activeSub
    g_activeSub = obj
    
    -- 执行副作用
    local status, err = pcall(obj._fn)
    
    -- 恢复前一个订阅者
    g_activeSub = prevSub
    
    -- 清除标志
    obj._flags = obj._flags & bit.bnot(RunningFlags | NotifiedFlag)
end
```

## HybridReactive 特性总结

### 核心优势

1. **Vue.js 风格API**: 提供熟悉的 `ref`、`reactive`、`computed` 等API
2. **深层响应式**: 默认支持深层嵌套对象的响应式转换
3. **精确监听**: `watchReactive` 提供精确的属性变化监听和路径跟踪
4. **高性能**: 基于高效的双向链表依赖管理系统
5. **类型安全**: 严格的类型检查和错误处理
6. **内存安全**: 自动清理不再使用的依赖关系

### 适用场景

- **状态管理**: 复杂应用的状态管理和数据流控制
- **数据绑定**: 实现数据与视图的双向绑定
- **响应式计算**: 基于数据变化的自动计算和更新
- **事件系统**: 构建基于数据变化的事件驱动系统
- **缓存系统**: 实现智能缓存和依赖失效机制

### 最佳实践

1. **合理使用深层/浅层响应式**: 根据需求选择合适的响应式深度
2. **利用路径信息**: 使用 `watchReactive` 的路径参数进行精确的变化处理
3. **及时清理监听器**: 使用返回的停止函数清理不再需要的监听器
4. **批量更新优化**: 在大量更新时使用 `startBatch`/`endBatch` 提高性能
5. **避免循环依赖**: 设计合理的数据结构避免复杂的循环依赖

## 许可证

本项目使用[LICENSE](LICENSE)许可证。
