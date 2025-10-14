# alien-signals-in-lua 3.0.0 升级完成

## 版本信息
- **旧版本**: 2.0.7
- **新版本**: 3.0.0
- **升级日期**: 2025-10-14
- **兼容**: alien-signals v3.0.0

## 主要变更

### 1. API重命名和移除

#### 重命名的API
- `setCurrentSub` → `setActiveSub`
- `getCurrentSub` → `getActiveSub`

#### 移除的API
- `setCurrentScope` (已移除，不再需要)
- `getCurrentScope` (已移除，不再需要)
- `pauseTracking` (已废弃并移除)
- `resumeTracking` (已废弃并移除)

### 2. 新增功能

#### 类型检测函数
```lua
-- 检查值是否为特定类型的响应式原语
isSignal(fn)      -- 检查是否为signal
isComputed(fn)    -- 检查是否为computed
isEffect(fn)      -- 检查是否为effect
isEffectScope(fn) -- 检查是否为effectScope
```

#### 新的Getter函数
```lua
getActiveSub()   -- 获取当前活动订阅者
getBatchDepth()  -- 获取当前批量更新深度
```

### 3. 内部优化

#### 移除tracking函数
- 移除了 `startTracking` 和 `endTracking` 函数
- 将tracking逻辑内联到 `run` 和 `updateComputed` 函数中
- 添加了新的 `purgeDeps` 函数来处理依赖清理

#### Computed优化
- computed的初始flags从 `17` (Mutable | Dirty) 改为 `0` (None)
- 添加首次访问的快速路径优化
- 首次访问computed值时不再需要完整的dirty检查流程

#### Effect和EffectScope改进
- 简化了父子层级关系的建立
- 分离了 `effectOper` 和 `effectScopeOper` 函数
- 优化了cleanup逻辑

#### Link函数增强
- `reactive.link` 现在接受第三个参数 `version`
- 在effect和effectScope中传递版本号0以提高性能
- 改进了cycle变量的使用

#### Pending标志清除优化
- 在 `checkDirty` 和 `computedOper` 中内联Pending标志的清除操作
- 减少不必要的标志操作

#### unwatched函数改进
- 更准确地识别不同类型的节点(signal/computed/effect/effectScope)
- 对effect和effectScope使用不同的清理策略

### 4. 性能改进

- 避免不必要的activeSub访问
- 内联Pending标志unset操作
- computed首次访问的快速路径
- 优化依赖清理流程

## 测试验证

所有测试用例均已通过：

✅ test_effect.lua - 11个测试全部通过
✅ test_computed.lua - 4个测试全部通过  
✅ test_effectScope.lua - 2个测试全部通过
✅ test_topology.lua - 12个测试全部通过
✅ test_untrack.lua - 3个测试全部通过
✅ test_v3_features.lua - 5个新功能测试全部通过

## 迁移指南

### 如果你使用了已重命名的API

```lua
-- 旧代码 (v2.0.7)
local prevSub = reactive.setCurrentSub(nil)
-- ...
reactive.setCurrentSub(prevSub)

-- 新代码 (v3.0.0)
local prevSub = reactive.setActiveSub(nil)
-- ...
reactive.setActiveSub(prevSub)
```

### 如果你使用了已移除的API

```lua
-- 旧代码 (v2.0.7)
reactive.pauseTracking()
someSignal() -- 不会建立依赖
reactive.resumeTracking()

-- 新代码 (v3.0.0) - 使用setActiveSub
local prevSub = reactive.setActiveSub(nil)
someSignal() -- 不会建立依赖
reactive.setActiveSub(prevSub)
```

### 如果你使用了getCurrentScope/setCurrentScope

v3.0.0中effectScope的管理已简化，不再需要显式的scope管理。
effect和effectScope现在通过activeSub建立父子关系。

## 向后兼容性

- ⚠️ **破坏性变更**: 移除了 `pauseTracking` 和 `resumeTracking`
- ⚠️ **破坏性变更**: 移除了 `getCurrentScope` 和 `setCurrentScope`
- ⚠️ **破坏性变更**: `setCurrentSub` 重命名为 `setActiveSub`
- ⚠️ **破坏性变更**: `getCurrentSub` 重命名为 `getActiveSub`

## 新功能使用示例

```lua
local reactive = require("reactive")
local signal = reactive.signal
local isSignal = reactive.isSignal
local getBatchDepth = reactive.getBatchDepth

-- 类型检测
local count = signal(0)
if isSignal(count) then
    print("count是一个signal")
end

-- 批量深度检测
print("当前批量深度:", getBatchDepth())
reactive.startBatch()
print("批量更新中，深度:", getBatchDepth())
reactive.endBatch()
```

## 总结

alien-signals-in-lua 3.0.0是一个重要的版本升级，带来了：
- 更清晰的API命名
- 更好的性能优化
- 新的类型检测功能
- 简化的内部实现
- 完全兼容alien-signals v3.0.0的算法

升级后的代码更加简洁、高效，并与TypeScript版本保持同步。
