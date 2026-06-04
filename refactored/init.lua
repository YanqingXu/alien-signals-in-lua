--[[
init.lua

模块概述：
统一入口模块。它把 refactored 目录下拆分后的核心能力重新聚合为一个稳定的公开 API，
让外部调用方继续通过 require("refactored") 使用 signal、computed、effect 等原语。

设计动机与职责：
模块化重构将单文件实现拆成常量层、图结构层、调度层、算法层、原语层与追踪层；
init.lua 的职责是屏蔽这种内部拆分，维持与原始入口一致的使用方式，并确保模块按
constants -> tracer -> scheduler -> engine -> primitives 的依赖顺序完成装配。

协作关系：
它直接依赖 constants、tracer、scheduler、engine 与 primitives，自身不持有运行时状态，
只负责把这些底层模块暴露成用户脚本、示例和测试可消费的统一门面。

核心概念：
本模块关注的是 API 聚合边界，而不是响应式算法本身。关键概念包括公开导出表、
稳定加载顺序，以及面向外部的原语、类型判断、批处理控制与 tracing 控制入口。
]]

local constants = require("refactored.constants")
local tracer = require("refactored.tracer")
local scheduler = require("refactored.scheduler")
local engine = require("refactored.engine")
local primitives = require("refactored.primitives")

return {
    signal = primitives.signal,
    computed = primitives.computed,
    effect = primitives.effect,
    effectScope = primitives.effectScope,
    trigger = primitives.trigger,

    isSignal = primitives.isSignal,
    isComputed = primitives.isComputed,
    isEffect = primitives.isEffect,
    isEffectScope = primitives.isEffectScope,

    startBatch = scheduler.startBatch,
    endBatch = scheduler.endBatch,

    getActiveSub = engine.getActiveSub,
    getBatchDepth = scheduler.getBatchDepth,
    setActiveSub = engine.setActiveSub,

    ReactiveFlags = constants.ReactiveFlags,

    tracer = tracer,
    setTraceHandler = tracer.setHandler,
    clearTraceHandler = tracer.clearHandler,
    formatTraceEvent = tracer.formatEvent,
}
