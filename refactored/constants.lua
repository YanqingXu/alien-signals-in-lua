--[[
constants.lua

模块概述：
常量与轻量工具模块。它集中定义响应式系统中的稳定事实，包括节点类型标记、位标志、
标志位操作函数，以及 callable 与节点之间的反向映射。

设计动机与职责：
响应式运行时中的 Marker、ReactiveFlags 和状态判定如果分散在 graph、engine、
primitives 等模块中，会很快引入循环依赖和语义漂移。constants.lua 作为叶子模块，
负责提供唯一权威定义，让其他模块都建立在同一套节点类型与状态机词汇之上。

协作关系：
它只依赖 bit 库，不依赖任何业务模块；graph、scheduler、engine、primitives、tracer
以及 init 都从这里读取类型标记、位掩码和辅助判定，因此它是整套模块化分层的公共基座。

核心概念：
本模块处理的关键数据包括 SIGNAL_MARKER / COMPUTED_MARKER / EFFECT_MARKER /
EFFECT_SCOPE_MARKER，ReactiveFlags 与 HAS_CHILD_EFFECT，弱键表 functionToNode，
以及 addFlags、removeFlags、hasFlag 一类围绕位运算展开的状态工具。
]]

local bit = require("bit")

local constants = {}

constants.SIGNAL_MARKER = {}
constants.COMPUTED_MARKER = {}
constants.EFFECT_MARKER = {}
constants.EFFECT_SCOPE_MARKER = {}

constants.functionToNode = setmetatable({}, { __mode = "k" })

--[[
ReactiveFlags 词汇表

这些名字尽量贴近原实现，但阅读时可以把它们理解成下面的问题：

- None          节点已经停止，或尚未进入响应式图。
- Mutable       这个节点可作为依赖源被下游订阅，并参与传播。
- Watching      这个节点是活跃 effect，失效传播时需要被调度。
- RecursedCheck 节点正在重建自己的依赖链，传播时要处理自递归场景。
- Recursed      失效传播已经在递归路径中再次触达过这个节点。
- Dirty         值已经确定需要提交或重算。
- Pending       上游可能变了，等下一次读取/刷新时再确认。

一句话区分 Dirty 与 Pending：
Dirty 是“必须检查自己”，Pending 是“先去问上游到底有没有真的变”。
]]
constants.ReactiveFlags = {
    None = 0,
    Mutable = 1,
    Watching = 2,
    RecursedCheck = 4,
    Recursed = 8,
    Dirty = 16,
    Pending = 32,
}

-- 这个位不属于 ReactiveFlags 状态机，只标记节点拥有子 effect/scope。
-- 重跑或停止父节点时，依靠它先释放子节点，再执行父节点自己的 cleanup。
constants.HAS_CHILD_EFFECT = 64

local ReactiveFlags = constants.ReactiveFlags

constants.TRACKABLE_FLAGS = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Watching)
constants.RECURSION_FLAGS = bit.bor(ReactiveFlags.RecursedCheck, ReactiveFlags.Recursed)
constants.DIRTY_OR_PENDING_FLAGS = bit.bor(ReactiveFlags.Dirty, ReactiveFlags.Pending)
constants.PROPAGATION_GUARD_FLAGS = bit.bor(
    ReactiveFlags.RecursedCheck,
    ReactiveFlags.Recursed,
    ReactiveFlags.Dirty,
    ReactiveFlags.Pending
)

-- 把内部 node 绑定成用户可调用的闭包。
function constants.bind(operation, node)
    local callable = function(...)
        return operation(node, ...)
    end
    constants.functionToNode[callable] = node
    return callable
end

-- 从用户闭包反查它代表的内部 node。
function constants.nodeForCallable(value)
    if type(value) ~= "function" then
        return nil
    end
    return constants.functionToNode[value]
end

-- 判断 node 是否是 signal。
function constants.isSignalNode(node)
    return type(node) == "table" and node.__type == constants.SIGNAL_MARKER
end

-- 判断 node 是否是 computed。
function constants.isComputedNode(node)
    return type(node) == "table" and node.__type == constants.COMPUTED_MARKER
end

-- 判断 node 是否是 effect。
function constants.isEffectNode(node)
    return type(node) == "table" and node.__type == constants.EFFECT_MARKER
end

-- 判断 node 是否是 effect scope。
function constants.isEffectScopeNode(node)
    return type(node) == "table" and node.__type == constants.EFFECT_SCOPE_MARKER
end

-- 判断 node 是否会产出可被订阅的值。
function constants.isValueProducerNode(node)
    return constants.isSignalNode(node) or constants.isComputedNode(node)
end

-- 判断 flags 整数是否包含某一位。
function constants.hasBit(flags, flag)
    return bit.band(flags or 0, flag) ~= 0
end

-- 判断 flags 整数是否包含一组位。
function constants.hasAllBits(flags, flagSet)
    return bit.band(flags or 0, flagSet) == flagSet
end

-- 判断 flags 整数是否包含任意一位。
function constants.hasAnyBits(flags, flagSet)
    return bit.band(flags or 0, flagSet) ~= 0
end

-- 判断 node.flags 是否包含某一位。
function constants.hasFlag(node, flag)
    return constants.hasBit(node.flags, flag)
end

-- 直接覆盖 node.flags。
function constants.setFlags(node, flags)
    node.flags = flags
end

-- 给 node.flags 增加一组位。
function constants.addFlags(node, flags)
    node.flags = bit.bor(node.flags or ReactiveFlags.None, flags)
end

-- 从 node.flags 移除一组位。
function constants.removeFlags(node, flags)
    node.flags = bit.band(node.flags or ReactiveFlags.None, bit.bnot(flags))
end

-- 判断节点是否会参与下游传播。
function constants.isMutableNode(node)
    return constants.hasFlag(node, ReactiveFlags.Mutable)
end

-- 判断 effect 是否仍处于监听态。
function constants.isWatchingEffect(node)
    return constants.hasFlag(node, ReactiveFlags.Watching)
end

-- 判断节点是否已经停用或尚未激活。
function constants.isInactive(node)
    return (node.flags or ReactiveFlags.None) == ReactiveFlags.None
end

-- 判断值节点是否已确定变脏。
function constants.isDirtyValue(node)
    return constants.hasAllBits(
        node.flags,
        bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty)
    )
end

-- 判断值节点是否等待上游确认。
function constants.isPendingValue(node)
    return constants.hasAllBits(
        node.flags,
        bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Pending)
    )
end

return constants
