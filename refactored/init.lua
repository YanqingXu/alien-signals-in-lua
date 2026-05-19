--[[
init.lua

模块化重构版的统一入口。外部用户只需要 require("refactored")，不需要知道内部被拆成
constants、graph、scheduler、engine、primitives 五个职责模块。
]]

local constants = require("refactored.constants")
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
}
