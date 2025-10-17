# HybridReactive Watch 系统完整指南

## 📚 目录

- [概述](#概述)
- [核心概念](#核心概念)
- [详细使用指南](#详细使用指南)
  - [watch() + reactive() 组合](#1-watch--reactive-组合)
  - [watchReactive() + reactive() 组合](#2-watchreactive--reactive-组合)
- [响应式深度的影响](#响应式深度的影响)
- [性能对比和优化](#性能对比和优化)
- [实际应用场景](#实际应用场景)
  - [数据计算和派生状态](#1-数据计算和派生状态-推荐-watch)
  - [数据同步和持久化](#2-数据同步和持久化-推荐-watchreactive)
  - [表单验证和实时反馈](#3-表单验证和实时反馈-组合使用)
  - [游戏状态管理](#4-游戏状态管理-组合使用)
- [最佳实践指南](#最佳实践指南)
- [总结](#总结)

## 概述

HybridReactive 提供了两种主要的监听机制来处理响应式对象的变化：
- **`watch()`** - 通用副作用函数，基于依赖追踪
- **`watchReactive()`** - 专用响应式对象监听器，基于属性变化

本文档详细说明这两种监听方式与 `reactive()` 对象的配合使用。

## 核心概念

### 1. 函数本质

```lua
-- watch() 是 reactive.effect() 的别名
HybridReactive.watch = reactive.effect

-- watchReactive() 是专门的响应式对象监听器
HybridReactive.watchReactive = function(reactiveObj, callback, shallow)
```

### 2. 工作原理对比

| 特性 | `watch()` | `watchReactive()` |
|------|-----------|-------------------|
| **监听方式** | 依赖追踪 | 属性变化监听 |
| **触发条件** | 访问的属性变化时 | 对象属性变化时 |
| **回调参数** | 无参数 | `(key, newValue, oldValue, path)` |
| **数据获取** | 主动访问 | 被动接收 |
| **性能特点** | 选择性监听 | 全面监听 |

## 详细使用指南

### 1. watch() + reactive() 组合

#### 基础用法
```lua
local HybridReactive = require("HybridReactive")

-- 创建响应式对象
local user = HybridReactive.reactive({
    name = "Alice",
    age = 25,
    profile = {
        email = "alice@example.com",
        settings = {
            theme = "dark"
        }
    }
})

-- 使用 watch() 监听
local stopWatch = HybridReactive.watch(function()
    -- 只有被访问的属性才会被追踪
    local name = user.name
    local email = user.profile.email
    
    -- 执行副作用
    print(string.format("User: %s (%s)", name, email))
end)

-- 触发变化
user.name = "Bob"           -- ✅ 触发 watch（name 被访问了）
user.age = 30               -- ❌ 不触发 watch（age 没有被访问）
user.profile.email = "bob@example.com"  -- ✅ 触发 watch（email 被访问了）
```

#### 选择性依赖追踪
```lua
local data = HybridReactive.reactive({
    input1 = 10,
    input2 = 20,
    config = { enabled = true },
    cache = { result = 0 }
})

HybridReactive.watch(function()
    if data.config.enabled then
        -- 只有在启用时才追踪 input1 和 input2
        local result = data.input1 + data.input2
        data.cache.result = result
        print("计算结果:", result)
    else
        print("计算已禁用")
    end
end)

-- 测试
data.input1 = 15            -- ✅ 触发（当 enabled = true 时）
data.config.enabled = false -- ✅ 触发（改变计算逻辑）
data.input2 = 25            -- ❌ 不触发（当 enabled = false 时）
```

#### 跨对象依赖
```lua
local userObj = HybridReactive.reactive({ name: "Alice", status: "online" })
local settingsObj = HybridReactive.reactive({ theme: "dark", language: "en" })
local statusObj = HybridReactive.reactive({ lastSeen: Date.now() })

HybridReactive.watch(function()
    -- 可以同时监听多个响应式对象
    local userInfo = userObj.name + " (" + userObj.status + ")"
    local theme = settingsObj.theme
    local lastSeen = statusObj.lastSeen
    
    updateUI(userInfo, theme, lastSeen)
end)
```

### 2. watchReactive() + reactive() 组合

#### 基础用法
```lua
local user = HybridReactive.reactive({
    name = "Alice",
    age = 25,
    profile = {
        email = "alice@example.com",
        settings = {
            theme = "dark"
        }
    }
})

-- 使用 watchReactive() 监听所有属性变化
local stopWatcher = HybridReactive.watchReactive(user, function(key, newValue, oldValue, path)
    print(string.format("属性变化: %s 在路径 %s 从 %s 变为 %s", 
          key, path, tostring(oldValue), tostring(newValue)))
end, false)  -- deep = false (深层监听)

-- 触发变化
user.name = "Bob"                    -- ✅ 触发: name 在路径 name 从 Alice 变为 Bob
user.age = 30                        -- ✅ 触发: age 在路径 age 从 25 变为 30
user.profile.email = "bob@example.com"  -- ✅ 触发: email 在路径 profile.email 从 alice@example.com 变为 bob@example.com
user.profile.settings.theme = "light"   -- ✅ 触发: theme 在路径 profile.settings.theme 从 dark 变为 light
```

#### 浅层 vs 深层监听
```lua
local obj = HybridReactive.reactive({
    user = {
        name = "Alice",
        profile = { age = 25 }
    },
    config = { theme = "dark" }
}, false)  -- 深层响应式

-- 浅层监听
local stopShallow = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print("浅层监听:", key, "at", path)
end, true)  -- shallow = true

-- 深层监听
local stopDeep = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print("深层监听:", key, "at", path)
end, false)  -- shallow = false

-- 测试变化
obj.user = { name: "Bob", profile: { age: 30 } }  -- 两者都触发
obj.user.name = "Charlie"                         -- 只有深层监听触发
obj.user.profile.age = 35                         -- 只有深层监听触发
```

#### 属性变化监控
```lua
local data = HybridReactive.reactive({
    users = {},
    settings = { version: "1.0" },
    cache = { lastUpdate: null }
})

HybridReactive.watchReactive(data, function(key, newValue, oldValue, path)
    -- 数据验证
    if key === "version" and !isValidVersion(newValue) then
        print("警告: 无效的版本号", newValue)
        data.settings.version = oldValue  -- 回滚
        return
    end
    
    -- 数据同步
    syncToServer(path, newValue)
    
    -- 缓存更新
    data.cache.lastUpdate = os.time()
    
    -- 日志记录
    logChange(path, oldValue, newValue)
end, false)
```

## 响应式深度的影响

### 1. 深层响应式 + 不同监听方式

```lua
-- 深层响应式对象
local deepObj = HybridReactive.reactive({
    level1 = {
        level2 = {
            level3 = { value = "deep" }
        }
    }
}, false)  -- shallow = false

-- watch() 可以访问任何层级
HybridReactive.watch(function()
    local value = deepObj.level1.level2.level3.value
    print("Deep value:", value)
end)

-- watchReactive() 可以监听任何层级变化
HybridReactive.watchReactive(deepObj, function(key, newValue, oldValue, path)
    print("Change at:", path)
end, false)

-- 修改深层属性
deepObj.level1.level2.level3.value = "modified"  -- 两者都会触发
```

### 2. 浅层响应式 + 不同监听方式

```lua
-- 浅层响应式对象
local shallowObj = HybridReactive.reactive({
    data = { nested = { value = "shallow" } }
}, true)  -- shallow = true

print("data is reactive:", HybridReactive.isReactive(shallowObj.data))  -- false

-- watch() 受限于响应式结构
HybridReactive.watch(function()
    local value = shallowObj.data.nested.value  -- ❌ data 不是响应式的
    print("Value:", value)
end)

-- watchReactive() 也受限于响应式结构
HybridReactive.watchReactive(shallowObj, function(key, newValue, oldValue, path)
    print("Change:", path)
end, false)

-- 测试变化
shallowObj.data = { nested: { value: "new" } }    -- ✅ 两者都触发（顶层变化）
shallowObj.data.nested.value = "modified"         -- ❌ 两者都不触发（data 不是响应式）
```

## 性能对比和优化

### 1. 性能测试示例

```lua
local obj = HybridReactive.reactive({
    a = 1, b = 2, c = 3, d = 4, e = 5,
    nested = { x = 10, y = 20, z = 30 }
}, false)

local watchCount = 0
local watchReactiveCount = 0

-- watch() - 选择性监听
local stopWatch = HybridReactive.watch(function()
    -- 只访问部分属性
    local sum = obj.a + obj.nested.x
    watchCount = watchCount + 1
end)

-- watchReactive() - 全面监听
local stopWatchReactive = HybridReactive.watchReactive(obj, function()
    watchReactiveCount = watchReactiveCount + 1
end, false)

-- 修改不同属性
obj.a = 10          -- 两者都触发
obj.nested.x = 100  -- 两者都触发
obj.b = 20          -- 只有 watchReactive 触发
obj.c = 30          -- 只有 watchReactive 触发

print("watch() triggers:", watchCount)           -- 3
print("watchReactive() triggers:", watchReactiveCount)  -- 6
```

### 2. 性能优化策略

#### 使用 watch() 优化
```lua
-- ✅ 好的做法：只访问需要的属性
HybridReactive.watch(function()
    if obj.config.enabled then
        processData(obj.data.value)  -- 条件性访问
    end
end)

-- ❌ 避免：访问不必要的属性
HybridReactive.watch(function()
    local allData = {
        value = obj.data.value,
        unused1 = obj.data.unused1,  -- 创建不必要的依赖
        unused2 = obj.data.unused2
    }
    processData(allData.value)
end)
```

#### 使用 watchReactive() 优化
```lua
-- ✅ 使用浅层监听减少触发
HybridReactive.watchReactive(obj, callback, true)  -- shallow = true

-- ✅ 分别监听不同部分
HybridReactive.watchReactive(obj.user, userCallback, false)
HybridReactive.watchReactive(obj.settings, settingsCallback, true)
```

## 实际应用场景

### 1. 数据计算和派生状态 (推荐 watch)

```lua
local store = HybridReactive.reactive({
    cart = {
        items = {
            { id = 1, price = 10, quantity = 2 },
            { id = 2, price = 15, quantity = 1 }
        },
        discount = 0.1,
        taxRate = 0.08
    },
    user = {
        membership = "premium"
    }
})

-- 使用 watch() 进行复杂计算
HybridReactive.watch(function()
    local items = store.cart.items
    local discount = store.cart.discount
    local taxRate = store.cart.taxRate
    local membership = store.user.membership

    -- 计算小计
    local subtotal = 0
    for _, item in ipairs(items) do
        subtotal = subtotal + (item.price * item.quantity)
    end

    -- 应用折扣
    local discountAmount = subtotal * discount
    if membership == "premium" then
        discountAmount = discountAmount * 1.5  -- 额外折扣
    end

    -- 计算税费
    local afterDiscount = subtotal - discountAmount
    local tax = afterDiscount * taxRate
    local total = afterDiscount + tax

    -- 更新UI
    updateCartDisplay({
        subtotal = subtotal,
        discount = discountAmount,
        tax = tax,
        total = total
    })
end)
```

### 2. 数据同步和持久化 (推荐 watchReactive)

```lua
local appState = HybridReactive.reactive({
    user = {
        preferences = {
            theme = "dark",
            language = "en",
            notifications = true
        },
        profile = {
            name = "Alice",
            email = "alice@example.com"
        }
    },
    settings = {
        version = "1.0",
        features = {
            beta = false,
            analytics = true
        }
    }
})

-- 使用 watchReactive() 进行数据同步
HybridReactive.watchReactive(appState, function(key, newValue, oldValue, path)
    -- 数据验证
    if !validateChange(path, newValue) then
        print("数据验证失败:", path, newValue)
        return
    end

    -- 本地存储
    localStorage.setItem(path, JSON.stringify(newValue))

    -- 远程同步
    if shouldSyncToServer(path) then
        syncToServer({
            path: path,
            value: newValue,
            timestamp: Date.now()
        })
    end

    -- 审计日志
    auditLog.record({
        action: "data_change",
        path: path,
        oldValue: oldValue,
        newValue: newValue,
        user: getCurrentUser().id
    })

    -- 通知其他组件
    eventBus.emit("data_changed", { path, newValue, oldValue })
end, false)
```

### 3. 表单验证和实时反馈 (组合使用)

```lua
local formData = HybridReactive.reactive({
    user = {
        username = "",
        email = "",
        password = "",
        confirmPassword = ""
    },
    validation = {
        errors = {},
        isValid = false
    }
})

-- 使用 watch() 进行实时验证
HybridReactive.watch(function()
    local user = formData.user
    local errors = {}

    -- 用户名验证
    if user.username.length < 3 then
        errors.username = "用户名至少3个字符"
    end

    -- 邮箱验证
    if !isValidEmail(user.email) then
        errors.email = "请输入有效的邮箱地址"
    end

    -- 密码验证
    if user.password.length < 8 then
        errors.password = "密码至少8个字符"
    end

    -- 确认密码验证
    if user.password ~= user.confirmPassword then
        errors.confirmPassword = "密码不匹配"
    end

    -- 更新验证状态
    formData.validation.errors = errors
    formData.validation.isValid = Object.keys(errors).length === 0
end)

-- 使用 watchReactive() 监听字段变化
HybridReactive.watchReactive(formData.user, function(key, newValue, oldValue, path)
    -- 清除该字段的错误状态
    if formData.validation.errors[key] then
        delete formData.validation.errors[key]
    end

    -- 实时保存草稿
    saveDraft(path, newValue)

    -- 字段级别的特殊处理
    if key === "email" then
        checkEmailAvailability(newValue)
    end
end, true)  -- 浅层监听，只关心直接字段变化
```

### 4. 游戏状态管理 (组合使用)

```lua
local gameState = HybridReactive.reactive({
    player = {
        position = { x = 0, y = 0 },
        health = 100,
        inventory = {
            items = {},
            gold = 0
        }
    },
    world = {
        level = 1,
        enemies = {},
        items = {}
    },
    ui = {
        showInventory = false,
        selectedItem = null
    }
})

-- 使用 watch() 处理游戏逻辑
HybridReactive.watch(function()
    local player = gameState.player
    local world = gameState.world

    -- 检查玩家与敌人的碰撞
    for _, enemy in ipairs(world.enemies) do
        if checkCollision(player.position, enemy.position) then
            handleCombat(player, enemy)
        end
    end

    -- 检查玩家与物品的碰撞
    for i, item in ipairs(world.items) do
        if checkCollision(player.position, item.position) then
            collectItem(player, item)
            table.remove(world.items, i)
        end
    end

    -- 更新游戏渲染
    renderGame(gameState)
end)

-- 使用 watchReactive() 处理状态变化
HybridReactive.watchReactive(gameState, function(key, newValue, oldValue, path)
    -- 成就系统
    if path === "player.health" and newValue <= 0 then
        triggerGameOver()
    end

    if path === "player.inventory.gold" and newValue >= 1000 then
        unlockAchievement("rich_player")
    end

    -- 音效系统
    if path.startsWith("player.inventory.items") then
        playSound("item_collected")
    end

    -- 保存游戏状态
    if shouldSaveGame(path) then
        saveGameState(gameState)
    end

    -- 网络同步（多人游戏）
    if isMultiplayer() and shouldSync(path) then
        syncToServer(path, newValue)
    end
end, false)
```

## 最佳实践指南

### 1. 选择决策树

```
需要监听响应式对象变化？
├─ 是 → 需要复杂计算或条件逻辑？
│   ├─ 是 → 使用 watch()
│   │   ├─ 跨对象依赖 → watch()
│   │   ├─ 条件性监听 → watch()
│   │   └─ 复杂派生状态 → watch()
│   └─ 否 → 需要详细的变化信息？
│       ├─ 是 → 使用 watchReactive()
│       │   ├─ 数据同步 → watchReactive()
│       │   ├─ 审计日志 → watchReactive()
│       │   └─ 调试监控 → watchReactive()
│       └─ 否 → 根据性能需求选择
└─ 否 → 考虑使用 watchRef() 或其他方案
```

### 2. 性能优化原则

#### watch() 优化
```lua
-- ✅ 条件性访问
HybridReactive.watch(function()
    if condition then
        useProperty(obj.expensiveProperty)
    end
end)

-- ✅ 缓存计算结果
local cachedResult = null
HybridReactive.watch(function()
    if needsRecalculation() then
        cachedResult = expensiveCalculation(obj.data)
    end
    useResult(cachedResult)
end)
```

#### watchReactive() 优化
```lua
-- ✅ 使用浅层监听
HybridReactive.watchReactive(obj, callback, true)

-- ✅ 分层监听
HybridReactive.watchReactive(obj.criticalData, criticalCallback, false)
HybridReactive.watchReactive(obj.uiState, uiCallback, true)
```

### 3. 错误处理和调试

```lua
-- 错误处理包装
function safeWatch(fn, errorHandler) {
    return HybridReactive.watch(function()
        local success, result = pcall(fn)
        if not success then
            if errorHandler then
                errorHandler(result)
            else
                print("Watch error:", result)
            end
        end
    end)
}

-- 调试监听器
function debugWatchReactive(obj, name) {
    return HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
        print(string.format("[DEBUG %s] %s: %s → %s",
              name, path, tostring(oldValue), tostring(newValue)))
    end, false)
}
```

### 4. 内存管理

```lua
-- 组件生命周期管理
local Component = {}

function Component:new()
    local instance = {
        watchers = {}
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function Component:addWatch(fn)
    local stop = HybridReactive.watch(fn)
    table.insert(self.watchers, stop)
    return stop
end

function Component:addWatchReactive(obj, callback, shallow)
    local stop = HybridReactive.watchReactive(obj, callback, shallow)
    table.insert(self.watchers, stop)
    return stop
end

function Component:destroy()
    for _, stop in ipairs(self.watchers) do
        stop()
    end
    self.watchers = {}
end
```

## 总结

### 核心原则

1. **watch() 适合计算型场景**：复杂逻辑、派生状态、条件监听
2. **watchReactive() 适合监控型场景**：数据同步、变化追踪、调试监控
3. **性能优先**：根据实际需求选择合适的监听深度
4. **组合使用**：在复杂应用中两者往往互补使用
5. **生命周期管理**：及时清理监听器避免内存泄漏

### 快速参考

| 场景 | 推荐方案 | 原因 |
|------|----------|------|
| 计算总价 | `watch()` | 需要访问多个属性进行计算 |
| 数据同步 | `watchReactive()` | 需要监听所有属性变化 |
| 条件渲染 | `watch()` | 可以条件性地建立依赖 |
| 表单验证 | `watch()` | 需要综合多个字段进行验证 |
| 审计日志 | `watchReactive()` | 需要记录每个属性的变化 |
| 缓存失效 | `watch()` | 可以精确控制何时失效缓存 |
| 调试监控 | `watchReactive()` | 需要完整的变化信息 |

通过合理选择和组合使用这两种监听方式，可以构建高效、可维护的响应式应用程序。

## 常见问题解答 (FAQ)

### Q1: 什么时候使用 watch()，什么时候使用 watchReactive()？

**A1:**
- **使用 `watch()`** 当你需要：
  - 基于多个属性进行复杂计算
  - 条件性地监听某些属性
  - 跨多个响应式对象建立依赖
  - 实现类似 computed 的派生状态

- **使用 `watchReactive()`** 当你需要：
  - 监听对象的所有属性变化
  - 获取详细的变化信息（key, newValue, oldValue, path）
  - 实现数据同步、日志记录、调试监控
  - 对每个属性变化进行特定处理

### Q2: 为什么我的 watch() 没有触发？

**A2:** 常见原因：
```lua
-- ❌ 问题：属性没有在 watch 函数中被访问
local obj = HybridReactive.reactive({ name: "Alice", age: 25 })
HybridReactive.watch(function()
    print("Something changed")  -- 没有访问任何属性
end)
obj.name = "Bob"  -- 不会触发

-- ✅ 解决：在函数中访问需要监听的属性
HybridReactive.watch(function()
    local name = obj.name  -- 访问属性建立依赖
    print("Name is:", name)
end)
obj.name = "Bob"  -- 会触发
```

### Q3: 为什么我的 watchReactive() 监听不到嵌套对象的变化？

**A3:** 检查响应式对象的深度：
```lua
-- ❌ 问题：浅层响应式 + 深层监听
local obj = HybridReactive.reactive({ user: { name: "Alice" } }, true)  -- shallow = true
HybridReactive.watchReactive(obj, callback, false)  -- deep watch
obj.user.name = "Bob"  -- 不会触发，因为 user 不是响应式的

-- ✅ 解决：使用深层响应式
local obj = HybridReactive.reactive({ user: { name: "Alice" } }, false)  -- deep reactive
HybridReactive.watchReactive(obj, callback, false)
obj.user.name = "Bob"  -- 会触发
```

### Q4: 如何避免无限循环？

**A4:** 避免在监听器中修改被监听的属性：
```lua
-- ❌ 危险：可能导致无限循环
local obj = HybridReactive.reactive({ count: 0 })
HybridReactive.watch(function()
    local count = obj.count
    obj.count = count + 1  -- 修改被监听的属性
end)

-- ✅ 安全：使用不同的属性或添加条件
local obj = HybridReactive.reactive({ input: 0, output: 0 })
HybridReactive.watch(function()
    local input = obj.input
    obj.output = input * 2  -- 修改不同的属性
end)
```

### Q5: 如何优化性能？

**A5:** 性能优化策略：
```lua
-- 1. 使用浅层监听减少触发
HybridReactive.watchReactive(obj, callback, true)  -- shallow = true

-- 2. 条件性访问属性
HybridReactive.watch(function()
    if obj.config.enabled then
        processData(obj.data.value)  -- 只在需要时访问
    end
end)

-- 3. 分层监听
HybridReactive.watchReactive(obj.criticalData, criticalCallback, false)
HybridReactive.watchReactive(obj.uiState, uiCallback, true)

-- 4. 使用防抖
local debounce = require("debounce")
HybridReactive.watchReactive(obj, debounce(callback, 100), false)
```

### Q6: 如何调试监听器？

**A6:** 调试技巧：
```lua
-- 1. 添加调试信息
HybridReactive.watch(function()
    print("[DEBUG] Watch triggered")
    local value = obj.data
    print("[DEBUG] Current value:", value)
end)

-- 2. 使用调试包装器
function debugWatch(name, fn)
    return HybridReactive.watch(function()
        print("[WATCH " .. name .. "] Starting")
        fn()
        print("[WATCH " .. name .. "] Finished")
    end)
end

-- 3. 监听所有变化
HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print(string.format("[DEBUG] %s: %s → %s", path, tostring(oldValue), tostring(newValue)))
end, false)
```

## 代码模板

### 1. 基础监听模板

```lua
-- watch() 模板
local stopWatch = HybridReactive.watch(function()
    -- 访问需要监听的属性
    local prop1 = obj.prop1
    local prop2 = obj.nested.prop2

    -- 执行副作用
    doSomething(prop1, prop2)
end)

-- watchReactive() 模板
local stopWatchReactive = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    -- 处理属性变化
    handleChange(key, newValue, oldValue, path)
end, false)  -- shallow = false for deep watching
```

### 2. 组件生命周期模板

```lua
local Component = {}

function Component:new(data)
    local instance = {
        data = HybridReactive.reactive(data),
        watchers = {}
    }
    setmetatable(instance, self)
    self.__index = self

    instance:setupWatchers()
    return instance
end

function Component:setupWatchers()
    -- 计算型监听
    local computeWatcher = HybridReactive.watch(function()
        self:updateComputedProperties()
    end)
    table.insert(self.watchers, computeWatcher)

    -- 变化监听
    local changeWatcher = HybridReactive.watchReactive(self.data, function(key, newValue, oldValue, path)
        self:handleDataChange(key, newValue, oldValue, path)
    end, false)
    table.insert(self.watchers, changeWatcher)
end

function Component:updateComputedProperties()
    -- 实现计算逻辑
end

function Component:handleDataChange(key, newValue, oldValue, path)
    -- 实现变化处理逻辑
end

function Component:destroy()
    for _, stop in ipairs(self.watchers) do
        stop()
    end
    self.watchers = {}
end
```

### 3. 状态管理模板

```lua
local Store = {}

function Store:new(initialState)
    local instance = {
        state = HybridReactive.reactive(initialState),
        mutations = {},
        actions = {},
        watchers = {}
    }
    setmetatable(instance, self)
    self.__index = self

    instance:setupMiddleware()
    return instance
end

function Store:setupMiddleware()
    -- 状态变化日志
    local logWatcher = HybridReactive.watchReactive(self.state, function(key, newValue, oldValue, path)
        print(string.format("[STORE] %s: %s → %s", path, tostring(oldValue), tostring(newValue)))
    end, false)
    table.insert(self.watchers, logWatcher)

    -- 持久化
    local persistWatcher = HybridReactive.watchReactive(self.state, function(key, newValue, oldValue, path)
        if self:shouldPersist(path) then
            self:saveToStorage(path, newValue)
        end
    end, false)
    table.insert(self.watchers, persistWatcher)
end

function Store:commit(mutation, payload)
    if self.mutations[mutation] then
        self.mutations[mutation](self.state, payload)
    end
end

function Store:dispatch(action, payload)
    if self.actions[action] then
        self.actions[action](self, payload)
    end
end

function Store:shouldPersist(path)
    -- 实现持久化逻辑
    return true
end

function Store:saveToStorage(path, value)
    -- 实现存储逻辑
end
```

## 参考资源

- [HybridReactive API 文档](README.md)
- [性能优化指南](REACTIVE_WATCH_COMBINATIONS_ANALYSIS.md)
- [测试用例](test_hybrid_reactive.lua)
- [Vue.js 响应式原理](https://vuejs.org/guide/extras/reactivity-in-depth.html)

---

**最后更新**: 2024年
**版本**: 1.0
**作者**: HybridReactive 开发团队
```
