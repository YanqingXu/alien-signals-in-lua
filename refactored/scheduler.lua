--[[
scheduler.lua

模块概述：
批量更新与 effect 调度模块。它负责维护 batch 深度、排队等待执行的 effect 队列，
并在安全时机统一 flush 队列，而不是在每次写入时立即重跑副作用。

设计动机与职责：
响应式系统需要把“写入导致的失效传播”与“effect 真正执行”解耦，否则连续多次写入
会造成重复运行与顺序混乱。scheduler.lua 的职责是把 effect 的执行延迟到批处理边界，
维持嵌套 effect 的一致出队顺序，并在某个 effect 抛错时恢复剩余队列的 Watching 状态，
避免调度器留下半失效的节点。

协作关系：
它依赖 constants 提供 Watching 等标志位语义，依赖 tracer 输出调度事件；实际如何
重跑单个 effect 由 engine 通过 runEffectHandler 注入。上层的 primitives 与公开入口
通过 startBatch、endBatch、getBatchDepth 暴露调度控制能力。

核心概念：
本模块围绕 queuedEffects、queuedEffectCount、queueReadIndex、batchDepth 等队列状态运转，
并以 ReactiveFlags.Watching、Recursed 等标志作为入队去重和异常恢复的关键依据。
]]

local bit = require("bit")

local constants = require("refactored.constants")
local tracer = require("refactored.tracer")
local ReactiveFlags = constants.ReactiveFlags

local scheduler = {}

local queuedEffects = {}
local queuedEffectCount = 0
local queueReadIndex = 0
local batchDepth = 0
local runEffectHandler = function()
    error("scheduler.runEffectHandler has not been configured")
end

-- 注入真正执行 effect 的函数。
function scheduler.setRunEffectHandler(handler)
    runEffectHandler = handler
end

-- 暴露当前 batch 嵌套深度。
function scheduler.getBatchDepth()
    return batchDepth
end

--[[
把 effect 放入队列。

effect 创建 effect 时，父 effect 本身也可能成为子 effect 的 dependency。通知父 effect
时，需要沿 subs 链把内层 effect 一起收集，并反向入队。这样内层 effect 和普通
并列 effect 的执行顺序保持一致。
]]
function scheduler.enqueueEffect(effectNode)
    local collected = {}

    while effectNode and constants.isWatchingEffect(effectNode) do
        local flagsBefore = effectNode.flags
        collected[#collected + 1] = effectNode
        effectNode.isQueued = true
        constants.removeFlags(effectNode, ReactiveFlags.Watching)
        tracer.emit("effect:enqueue", effectNode, {
            flagsBefore = flagsBefore,
            flagsAfter = effectNode.flags,
        })

        local innerEffectLink = effectNode.subs
        effectNode = innerEffectLink and innerEffectLink.sub or nil
    end

    for index = #collected, 1, -1 do
        queuedEffectCount = queuedEffectCount + 1
        queuedEffects[queuedEffectCount] = collected[index]
    end
end

-- 消费队列，并在出错时恢复剩余 effect。
function scheduler.flush()
    tracer.enter("flush", nil, {
        queueSize = queuedEffectCount - queueReadIndex,
    })

    local ok, err = pcall(function()
        while queueReadIndex < queuedEffectCount do
            queueReadIndex = queueReadIndex + 1
            local effectNode = queuedEffects[queueReadIndex]
            queuedEffects[queueReadIndex] = nil

            if effectNode then
                tracer.emit("flush:run", effectNode, {
                    queueSize = queuedEffectCount - queueReadIndex,
                })
                runEffectHandler(effectNode)
            end
        end
    end)

    -- 如果某个 effect 抛错，队列里尚未执行的 effect 已经被移除了 Watching 标记。
    -- 这里恢复它们的可监听状态，避免下一次更新时队列处在半失效状态。
    while queueReadIndex < queuedEffectCount do
        queueReadIndex = queueReadIndex + 1
        local effectNode = queuedEffects[queueReadIndex]
        queuedEffects[queueReadIndex] = nil
        if effectNode then
            effectNode.isQueued = false
            constants.addFlags(effectNode, bit.bor(ReactiveFlags.Watching, ReactiveFlags.Recursed))
            tracer.emit("flush:restore", effectNode, {
                flagsAfter = effectNode.flags,
                reason = "error-recovery",
            })
        end
    end

    queueReadIndex = 0
    queuedEffectCount = 0

    tracer.leave("flush", nil, {
        result = ok and "ok" or "error",
    })

    if not ok then
        error(err)
    end
end

-- 进入一层 batch。
function scheduler.startBatch()
    batchDepth = batchDepth + 1
    tracer.emit("batch:start", nil, {
        batchDepth = batchDepth,
    })
end

-- 退出一层 batch，最外层结束时 flush。
function scheduler.endBatch()
    batchDepth = batchDepth - 1
    tracer.emit("batch:end", nil, {
        batchDepth = batchDepth,
    })
    if batchDepth == 0 then
        scheduler.flush()
    end
end

return scheduler
