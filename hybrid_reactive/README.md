# HybridReactive - Vue.js 风格的响应式系统

[English](#english) | [中文](#chinese)

---

<a name="chinese"></a>

## 📖 概述

`HybridReactive.lua` 是基于 [alien-signals](https://github.com/stackblitz/alien-signals) 响应式系统构建的高级响应式编程接口，提供类似 **Vue.js** 的 API 设计，让 Lua 开发者能够以更直观、更易用的方式使用响应式编程。

### 🎯 设计目标

- **Vue.js 风格 API**：为熟悉 Vue.js 的开发者提供一致的编程体验
- **深度响应式**：支持嵌套对象的自动响应式转换
- **灵活的监听**：提供多种监听方式（ref、reactive、通用 watch）
- **类型安全**：提供完整的类型检查和错误提示
- **性能优化**：基于 alien-signals 的高性能响应式内核

---

## 🚀 核心功能

### 1. `ref()` - 响应式引用

创建一个包装基本值的响应式引用对象。

```lua
local count = HybridReactive.ref(0)

-- 读取值
print(count.value)  -- 输出: 0

-- 设置值
count.value = 10
print(count.value)  -- 输出: 10
```

**特点：**
- ✅ 包装任何类型的值（数字、字符串、表等）
- ✅ 通过 `.value` 属性访问和修改
- ✅ 自动触发依赖更新
- ✅ 只能访问 `value` 属性，访问其他属性会报错

---

### 2. `computed()` - 计算值

创建一个根据依赖自动重新计算的只读值。

```lua
local firstName = HybridReactive.ref("John")
local lastName = HybridReactive.ref("Doe")

local fullName = HybridReactive.computed(function()
    return firstName.value .. " " .. lastName.value
end)

print(fullName.value)  -- 输出: "John Doe"

firstName.value = "Jane"
print(fullName.value)  -- 输出: "Jane Doe" (自动更新)
```

**特点：**
- ✅ 惰性求值（只在访问时计算）
- ✅ 自动依赖追踪
- ✅ 只读（无法修改 computed 的值）
- ✅ 值缓存（依赖不变时不重新计算）

---

### 3. `reactive()` - 响应式对象

将普通对象转换为响应式对象，支持深度和浅层两种模式。

```lua
local user = HybridReactive.reactive({
    name = "Alice",
    age = 25,
    profile = {
        email = "alice@example.com"
    }
})

-- 直接访问和修改属性
print(user.name)  -- 输出: "Alice"
user.age = 26     -- 自动触发更新

-- 深度响应式：嵌套对象也是响应式的
user.profile.email = "newemail@example.com"  -- 也会触发更新
```

**特点：**
- ✅ 自动转换对象所有属性为响应式
- ✅ 支持深度响应式（默认）
- ✅ 支持浅层响应式（`reactive(obj, true)`）
- ✅ 支持动态添加新属性
- ✅ 防止循环引用

---

### 4. `watch()` - 通用监听器

监听响应式数据的变化并执行回调函数。

```lua
local count = HybridReactive.ref(0)

-- 监听 ref
local stop = HybridReactive.watch(function()
    return count.value
end, function(newValue, oldValue)
    print("count changed from " .. oldValue .. " to " .. newValue)
end)

count.value = 5  -- 输出: "count changed from 0 to 5"

-- 停止监听
stop()
```

**特点：**
- ✅ 支持监听任意响应式表达式
- ✅ 回调接收新值和旧值
- ✅ 返回停止函数
- ✅ 自动依赖收集

---

### 5. `watchRef()` - 监听 ref 对象

专门用于监听 ref 对象值变化的便捷函数。

```lua
local count = HybridReactive.ref(0)

local stop = HybridReactive.watchRef(count, function(newValue, oldValue)
    print(string.format("值从 %d 变为 %d", oldValue, newValue))
end)

count.value = 10  -- 输出: "值从 0 变为 10"

stop()  -- 停止监听
```

**特点：**
- ✅ 专门优化的 ref 监听
- ✅ 简洁的 API
- ✅ 只在值真正改变时触发回调
- ✅ 类型检查（必须传入 ref 对象）

---

### 6. `watchReactive()` - 监听响应式对象

监听响应式对象的属性变化，支持深度和浅层监听。

```lua
local user = HybridReactive.reactive({
    name = "Alice",
    profile = {
        email = "alice@example.com"
    }
})

-- 深度监听（默认）
local stop = HybridReactive.watchReactive(user, function(key, newValue, oldValue, path)
    print(string.format("属性 %s 从 %s 变为 %s (路径: %s)", 
        key, tostring(oldValue), tostring(newValue), path))
end)

user.name = "Bob"  
-- 输出: "属性 name 从 Alice 变为 Bob (路径: name)"

user.profile.email = "bob@example.com"
-- 输出: "属性 email 从 alice@example.com 变为 bob@example.com (路径: profile.email)"

stop()  -- 停止监听
```

**特点：**
- ✅ 监听对象所有属性变化
- ✅ 支持深度监听（默认）和浅层监听
- ✅ 回调提供详细信息：key、新值、旧值、完整路径
- ✅ 防止循环引用
- ✅ 自动清理嵌套对象的监听器

---

## 🔍 工具函数

### `isRef()` - 检查是否为 ref

```lua
local count = HybridReactive.ref(0)
print(HybridReactive.isRef(count))  -- 输出: true
print(HybridReactive.isRef({}))     -- 输出: false
```

### `isReactive()` - 检查是否为响应式对象

```lua
local user = HybridReactive.reactive({ name = "Alice" })
print(HybridReactive.isReactive(user))  -- 输出: true
print(HybridReactive.isReactive({}))    -- 输出: false
```

### `toRaw()` - 获取原始对象

```lua
local user = HybridReactive.reactive({ name = "Alice" })
local raw = HybridReactive.toRaw(user)
-- raw 是普通对象，修改它不会触发响应式更新
```

---

## 📚 使用示例

### 示例 1：购物车系统

```lua
local HybridReactive = require("HybridReactive")

-- 创建购物车状态
local cart = HybridReactive.reactive({
    items = {},
    total = 0
})

-- 计算商品总数
local itemCount = HybridReactive.computed(function()
    local count = 0
    for _, item in ipairs(cart.items) do
        count = count + item.quantity
    end
    return count
end)

-- 监听购物车变化
HybridReactive.watchReactive(cart, function(key, newValue, oldValue, path)
    print(string.format("购物车更新: %s = %s", path, tostring(newValue)))
end)

-- 添加商品
table.insert(cart.items, { name = "Apple", quantity = 3, price = 1.5 })
cart.total = cart.total + 4.5

print("商品总数:", itemCount.value)  -- 输出: 商品总数: 3
```

### 示例 2：用户信息表单

```lua
local HybridReactive = require("HybridReactive")

-- 用户信息
local user = HybridReactive.reactive({
    firstName = "",
    lastName = "",
    email = ""
})

-- 计算全名
local fullName = HybridReactive.computed(function()
    if user.firstName == "" and user.lastName == "" then
        return "未设置"
    end
    return user.firstName .. " " .. user.lastName
end)

-- 监听邮箱变化
local stopEmailWatch = HybridReactive.watchReactive(user, function(key, newValue, oldValue, path)
    if key == "email" then
        print("邮箱已更新:", newValue)
        -- 这里可以触发邮箱验证逻辑
    end
end, true)  -- 浅层监听

-- 更新用户信息
user.firstName = "张"
user.lastName = "三"
user.email = "zhangsan@example.com"

print("全名:", fullName.value)  -- 输出: 全名: 张 三
```

### 示例 3：主题切换系统

```lua
local HybridReactive = require("HybridReactive")

-- 主题配置
local theme = HybridReactive.ref("light")

-- 监听主题变化
HybridReactive.watchRef(theme, function(newTheme, oldTheme)
    print(string.format("主题从 '%s' 切换到 '%s'", oldTheme, newTheme))
    -- 这里可以应用主题样式
    if newTheme == "dark" then
        print("应用暗色主题...")
    else
        print("应用亮色主题...")
    end
end)

-- 切换主题
theme.value = "dark"  
-- 输出: 
-- 主题从 'light' 切换到 'dark'
-- 应用暗色主题...
```

---

## 🎨 架构设计

```
HybridReactive.lua (高级 API 层)
       ↓
  基于以下封装
       ↓
reactive.lua (核心响应式系统)
       ↓
alien-signals 架构
```

### 层次说明：

1. **alien-signals 架构**：提供高性能的响应式内核
   - Signal（信号）
   - Computed（计算值）
   - Effect（副作用）
   - EffectScope（副作用作用域）

2. **reactive.lua**：Lua 实现的 alien-signals 核心系统
   - 依赖追踪
   - 批量更新
   - 拓扑排序优化

3. **HybridReactive.lua**：Vue.js 风格的高级 API
   - ref/reactive 语法糖
   - watch/watchRef/watchReactive 监听器
   - 深度响应式支持
   - 类型检查和错误处理

---

## ⚙️ 深度 vs 浅层响应式

### 深度响应式（默认）

```lua
local user = HybridReactive.reactive({
    profile = {
        settings = {
            theme = "light"
        }
    }
})

-- 深层嵌套的修改也会触发更新
user.profile.settings.theme = "dark"  -- ✅ 触发更新
```

### 浅层响应式

```lua
local user = HybridReactive.reactive({
    profile = {
        settings = {
            theme = "light"
        }
    }
}, true)  -- shallow = true

user.profile = { name = "New Profile" }  -- ✅ 触发更新
user.profile.settings.theme = "dark"     -- ❌ 不触发更新（不是响应式的）
```

---

## 🛡️ 错误处理

HybridReactive 提供完整的类型检查和错误提示：

```lua
-- ❌ 错误：computed 是只读的
local count = HybridReactive.computed(function() return 1 end)
count.value = 2  -- Error: Cannot set value on computed property

-- ❌ 错误：只能访问 .value 属性
local count = HybridReactive.ref(0)
print(count.other)  -- Error: Cannot access property on ref object: key=other

-- ❌ 错误：watchRef 必须传入 ref 对象
local obj = {}
HybridReactive.watchRef(obj, function() end)  
-- Error: watchRef: first parameter must be a ref object

-- ❌ 错误：reactive 只能用于对象
local num = HybridReactive.reactive(123)  
-- Error: reactive() can only be called on objects
```

---

## 🔬 测试文件

本目录包含完整的测试套件，验证所有功能：

- `test_hybrid_reactive.lua` - HybridReactive 基础功能测试
- `test_watch_with_reactive.lua` - watch 与 reactive 集成测试
- `test_shallow_reactive_deep_watch.lua` - 浅层响应式 + 深度监听测试
- `test_deep_reactive_shallow_watch.lua` - 深层响应式 + 浅层监听测试
- `example_shopping_cart.lua` - 购物车实际应用示例

运行测试：
```bash
lua test_hybrid_reactive.lua
```

---

## 📦 依赖

- **reactive.lua**：alien-signals 核心响应式系统
- **bit**：Lua 位运算库（通常内置于 LuaJIT）

---

## 🎯 适用场景

HybridReactive 适合以下场景：

✅ **游戏开发**：角色状态、UI 系统、配置管理  
✅ **Web 框架**：类似 Vue.js 的响应式数据绑定  
✅ **数据流管理**：复杂的状态管理和派生状态  
✅ **配置系统**：动态配置和热重载  
✅ **测试工具**：模拟响应式行为和数据变化  

---

## 📝 注意事项

1. **性能考虑**：深度响应式会递归转换所有嵌套对象，对于大型对象可能影响性能，可以使用浅层响应式优化

2. **循环引用**：HybridReactive 内置循环引用检测，但建议避免创建循环引用的对象结构

3. **内存管理**：记得调用 `stop()` 函数停止不再需要的监听器，避免内存泄漏

4. **类型限制**：reactive() 只能用于表（table）类型，基本类型请使用 ref()

---

## 🔗 相关资源

- [alien-signals GitHub](https://github.com/stackblitz/alien-signals)
- [Vue.js 响应式 API](https://vuejs.org/api/reactivity-core.html)
- [../reactive.lua](../reactive.lua) - 核心响应式系统
- [../README.md](../README.md) - 项目主文档

---

<a name="english"></a>

# HybridReactive - Vue.js-style Reactive System

## 📖 Overview

`HybridReactive.lua` is a high-level reactive programming interface built on top of the [alien-signals](https://github.com/stackblitz/alien-signals) reactive system, providing a **Vue.js-like** API design that allows Lua developers to use reactive programming in a more intuitive and user-friendly way.

### 🎯 Design Goals

- **Vue.js-style API**: Consistent programming experience for developers familiar with Vue.js
- **Deep Reactivity**: Automatic reactive transformation for nested objects
- **Flexible Watching**: Multiple watching methods (ref, reactive, generic watch)
- **Type Safety**: Complete type checking and error messages
- **Performance**: Built on high-performance alien-signals reactive core

---

## 🚀 Core Features

### 1. `ref()` - Reactive Reference

Creates a reactive reference that wraps a value.

```lua
local count = HybridReactive.ref(0)

-- Read value
print(count.value)  -- Output: 0

-- Set value
count.value = 10
print(count.value)  -- Output: 10
```

**Features:**
- ✅ Wraps any type of value (numbers, strings, tables, etc.)
- ✅ Access and modify via `.value` property
- ✅ Automatically triggers dependency updates
- ✅ Only `.value` property accessible, other properties throw errors

---

### 2. `computed()` - Computed Value

Creates a read-only value that automatically recomputes based on dependencies.

```lua
local firstName = HybridReactive.ref("John")
local lastName = HybridReactive.ref("Doe")

local fullName = HybridReactive.computed(function()
    return firstName.value .. " " .. lastName.value
end)

print(fullName.value)  -- Output: "John Doe"

firstName.value = "Jane"
print(fullName.value)  -- Output: "Jane Doe" (automatically updated)
```

**Features:**
- ✅ Lazy evaluation (computed only when accessed)
- ✅ Automatic dependency tracking
- ✅ Read-only (cannot modify computed values)
- ✅ Value caching (doesn't recompute when dependencies unchanged)

---

### 3. `reactive()` - Reactive Object

Converts a plain object to a reactive object, supporting both deep and shallow modes.

```lua
local user = HybridReactive.reactive({
    name = "Alice",
    age = 25,
    profile = {
        email = "alice@example.com"
    }
})

-- Direct property access and modification
print(user.name)  -- Output: "Alice"
user.age = 26     -- Automatically triggers update

-- Deep reactivity: nested objects are also reactive
user.profile.email = "newemail@example.com"  -- Also triggers update
```

**Features:**
- ✅ Automatically converts all object properties to reactive
- ✅ Supports deep reactivity (default)
- ✅ Supports shallow reactivity (`reactive(obj, true)`)
- ✅ Supports dynamically adding new properties
- ✅ Prevents circular references

---

### 4. `watch()` - Generic Watcher

Watches reactive data changes and executes callback functions.

```lua
local count = HybridReactive.ref(0)

-- Watch ref
local stop = HybridReactive.watch(function()
    return count.value
end, function(newValue, oldValue)
    print("count changed from " .. oldValue .. " to " .. newValue)
end)

count.value = 5  -- Output: "count changed from 0 to 5"

-- Stop watching
stop()
```

**Features:**
- ✅ Watches any reactive expression
- ✅ Callback receives new and old values
- ✅ Returns stop function
- ✅ Automatic dependency collection

---

### 5. `watchRef()` - Watch ref Object

Convenient function specifically for watching ref object value changes.

```lua
local count = HybridReactive.ref(0)

local stop = HybridReactive.watchRef(count, function(newValue, oldValue)
    print(string.format("Value changed from %d to %d", oldValue, newValue))
end)

count.value = 10  -- Output: "Value changed from 0 to 10"

stop()  -- Stop watching
```

**Features:**
- ✅ Optimized specifically for ref watching
- ✅ Concise API
- ✅ Triggers callback only when value actually changes
- ✅ Type checking (must pass ref object)

---

### 6. `watchReactive()` - Watch Reactive Object

Watches property changes in reactive objects, supporting deep and shallow watching.

```lua
local user = HybridReactive.reactive({
    name = "Alice",
    profile = {
        email = "alice@example.com"
    }
})

-- Deep watching (default)
local stop = HybridReactive.watchReactive(user, function(key, newValue, oldValue, path)
    print(string.format("Property %s changed from %s to %s (path: %s)", 
        key, tostring(oldValue), tostring(newValue), path))
end)

user.name = "Bob"  
-- Output: "Property name changed from Alice to Bob (path: name)"

user.profile.email = "bob@example.com"
-- Output: "Property email changed from alice@example.com to bob@example.com (path: profile.email)"

stop()  -- Stop watching
```

**Features:**
- ✅ Watches all property changes in object
- ✅ Supports deep watching (default) and shallow watching
- ✅ Callback provides detailed info: key, new value, old value, full path
- ✅ Prevents circular references
- ✅ Automatically cleans up nested object watchers

---

## 🔍 Utility Functions

### `isRef()` - Check if ref

```lua
local count = HybridReactive.ref(0)
print(HybridReactive.isRef(count))  -- Output: true
print(HybridReactive.isRef({}))     -- Output: false
```

### `isReactive()` - Check if reactive object

```lua
local user = HybridReactive.reactive({ name = "Alice" })
print(HybridReactive.isReactive(user))  -- Output: true
print(HybridReactive.isReactive({}))    -- Output: false
```

### `toRaw()` - Get raw object

```lua
local user = HybridReactive.reactive({ name = "Alice" })
local raw = HybridReactive.toRaw(user)
-- raw is a plain object, modifying it won't trigger reactive updates
```

---

## 📦 Dependencies

- **reactive.lua**: alien-signals core reactive system
- **bit**: Lua bitwise operation library (usually built into LuaJIT)

---

## 🎯 Use Cases

HybridReactive is suitable for:

✅ **Game Development**: Character states, UI systems, configuration management  
✅ **Web Frameworks**: Vue.js-like reactive data binding  
✅ **Data Flow Management**: Complex state management and derived state  
✅ **Configuration Systems**: Dynamic configuration and hot reload  
✅ **Testing Tools**: Simulate reactive behavior and data changes  

---

## 📝 Notes

1. **Performance**: Deep reactivity recursively converts all nested objects, which may impact performance for large objects. Use shallow reactivity for optimization.

2. **Circular References**: HybridReactive has built-in circular reference detection, but it's recommended to avoid creating circular reference object structures.

3. **Memory Management**: Remember to call the `stop()` function to stop watchers that are no longer needed to avoid memory leaks.

4. **Type Restrictions**: reactive() only works with table types. Use ref() for primitive types.

---

## 🔗 Related Resources

- [alien-signals GitHub](https://github.com/stackblitz/alien-signals)
- [Vue.js Reactivity API](https://vuejs.org/api/reactivity-core.html)
- [../reactive.lua](../reactive.lua) - Core reactive system
- [../README.md](../README.md) - Main project documentation

---

## 📄 License

Same as the parent project - MIT License

## 👥 Contributing

Contributions are welcome! Please refer to the main project's contribution guidelines.
