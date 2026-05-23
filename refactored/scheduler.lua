--[[
scheduler.lua

负责“什么时候运行 effect”。它只管理批量更新深度、effect 队列，以及错误时
队列状态如何恢复；真正的 effect 执行由 engine 注入进来的 runEffectHandler 完成。
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
