--[[
constants.lua

集中放置响应式系统的常量、类型标记和轻量工具函数。其它模块只依赖这里的
“稳定事实”：节点有哪些类型、状态有哪些位标记、如何读写这些标记。
]]

local bit = require("bit")

local constants = {}

constants.SIGNAL_MARKER = {}
constants.COMPUTED_MARKER = {}
constants.EFFECT_MARKER = {}
constants.EFFECT_SCOPE_MARKER = {}

constants.functionToNode = setmetatable({}, { __mode = "k" })

constants.ReactiveFlags = {
    None = 0,
    Mutable = 1,
    Watching = 2,
    RecursedCheck = 4,
    Recursed = 8,
    Dirty = 16,
    Pending = 32,
}

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

function constants.bind(operation, node)
    local callable = function(...)
        return operation(node, ...)
    end
    constants.functionToNode[callable] = node
    return callable
end

function constants.nodeForCallable(value)
    if type(value) ~= "function" then
        return nil
    end
    return constants.functionToNode[value]
end

function constants.hasFlagValue(flags, flag)
    return bit.band(flags or 0, flag) ~= 0
end

function constants.hasAllFlagValues(flags, flagSet)
    return bit.band(flags or 0, flagSet) == flagSet
end

function constants.hasAnyFlagValue(flags, flagSet)
    return bit.band(flags or 0, flagSet) ~= 0
end

function constants.hasFlag(node, flag)
    return constants.hasFlagValue(node.flags, flag)
end

function constants.setFlags(node, flags)
    node.flags = flags
end

function constants.addFlags(node, flags)
    node.flags = bit.bor(node.flags or ReactiveFlags.None, flags)
end

function constants.removeFlags(node, flags)
    node.flags = bit.band(node.flags or ReactiveFlags.None, bit.bnot(flags))
end

function constants.isMutableNode(node)
    return constants.hasFlag(node, ReactiveFlags.Mutable)
end

function constants.isWatchingEffect(node)
    return constants.hasFlag(node, ReactiveFlags.Watching)
end

function constants.isInactive(node)
    return (node.flags or ReactiveFlags.None) == ReactiveFlags.None
end

function constants.isMutableAndDirty(node)
    return constants.hasAllFlagValues(
        node.flags,
        bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty)
    )
end

function constants.isMutableAndPending(node)
    return constants.hasAllFlagValues(
        node.flags,
        bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Pending)
    )
end

return constants
