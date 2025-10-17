# alien-signals-in-lua v3.0.1 更新日志

## 版本信息
- 原版本: 3.0.0
- 新版本: 3.0.1
- 对应 TypeScript 版本: alien-signals v3.0.1 (commit 4983199)

## 主要变更

### 1. Signal 属性重命名
**原因**: 更清晰地区分待写入值和当前值

- `previousValue` → `currentValue` (已提交的当前值)
- `value` → `pendingValue` (待提交的新值)

**影响的函数**:
- `signal()` - 初始化时使用 `currentValue` 和 `pendingValue`
- `signalOper()` - 写入时更新 `pendingValue`，读取时返回 `currentValue`
- `updateSignal()` - 比较并提交 `pendingValue` 到 `currentValue`

### 2. updateSignal 签名更改
**变更**: 移除 `value` 参数

```lua
-- v3.0.0
function reactive.updateSignal(signal, value)
    signal.flags = ReactiveFlags.Mutable
    if signal.previousValue == value then
        return false
    end
    signal.previousValue = value
    return true
end

-- v3.0.1
function reactive.updateSignal(signal)
    signal.flags = ReactiveFlags.Mutable
    if signal.currentValue == signal.pendingValue then
        return false
    end
    signal.currentValue = signal.pendingValue
    return true
end
```

### 3. Computed 初始化标志更改
**变更**: Computed 创建时立即标记为 Dirty

```lua
-- v3.0.0
flags = ReactiveFlags.None  -- 0

-- v3.0.1
flags = 17  -- Mutable | Dirty
```

**原因**: 避免首次访问时的特殊路径处理，统一走 dirty 检查流程

### 4. 移除 Computed 首次访问快速路径
**变更**: 删除 `computedOper` 中的 `elseif flags == 0` 分支

```lua
-- v3.0.0 中存在的代码（已删除）:
elseif flags == 0 then
    -- Fast path for first time access
    this.flags = ReactiveFlags.Mutable
    local prevSub = reactive.setActiveSub(this)
    local result, value = pcall(this.getter)
    if result then
        this.value = value
    else
        print("Error in computed: " .. value)
    end
    g_activeSub = prevSub
end
```

**原因**: 与 flags=17 的初始化配合，首次访问也走正常的 dirty 更新流程

### 5. effectScopeOper 简化
**变更**: 使用 `purgeDeps()` 替代手动循环清理

```lua
-- v3.0.0
local dep = this.deps
while dep do
    dep = reactive.unlink(dep, this)
end

-- v3.0.1
this.depsTail = nil
this.flags = ReactiveFlags.None
reactive.purgeDeps(this)
```

**优势**: 代码更简洁，逻辑更清晰

### 6. unwatched 函数的判断逻辑更改
**变更**: EffectScope 的识别从属性检查改为 flags 检查

```lua
-- v3.0.0
elseif not node.previousValue then
    -- For effect scopes (no getter, no fn, no previousValue)

-- v3.0.1
elseif bit.band(node.flags, ReactiveFlags.Mutable) == 0 then
    -- For effect scopes (flag check: not Mutable)
```

**原因**: 更准确的类型判断，不依赖特定属性的存在性

### 7. signalOper 的依赖注册逻辑优化
**变更**: 在读取操作中使用 while 循环检查 subscriber 的 flags

```lua
-- v3.0.1
local sub = g_activeSub
while sub do
    if bit.band(sub.flags, 3) > 0 then  -- Mutable | Watching
        reactive.link(this, sub, g_currentVersion)
        break
    end
    sub = sub.subs and sub.subs.sub or nil
end
```

**原因**: 更精确的依赖关系建立，避免链接不活跃的订阅者

## 测试验证
所有测试均通过：
- ✅ test_effect.lua (11 tests)
- ✅ test_computed.lua (4 tests)
- ✅ test_effectScope.lua (2 tests)
- ✅ test_topology.lua (12 tests)
- ✅ test_untrack.lua (3 tests)

## 兼容性说明
v3.0.1 与 v3.0.0 在 API 层面完全兼容，所有公共接口保持不变。内部实现的优化对用户代码透明。

## 性能影响
- **Computed**: 首次访问统一走 dirty 检查，代码路径更一致，但理论上略微增加首次调用开销（可忽略）
- **Effect Cleanup**: 使用 `purgeDeps` 简化逻辑，清理效率可能略有提升
- **Signal**: 属性重命名本身无性能影响，但语义更清晰有助于代码优化

## 升级建议
从 v3.0.0 升级到 v3.0.1 无需修改任何用户代码，建议所有用户升级以获得更好的代码质量和潜在的性能改进。
