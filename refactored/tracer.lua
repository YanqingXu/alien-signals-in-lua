--[[
tracer.lua

模块概述：
结构化运行时追踪模块。它为响应式系统提供默认关闭的观测层，把 signal、graph、
scheduler、engine 与 primitives 发出的事件整理为稳定的调试标签、flags 文本和日志行。

设计动机与职责：
教学和排障需要看到运行时链路，但核心算法不能直接耦合到 print 或特定展示格式。
tracer.lua 通过 handler 注入把“事件采集”与“事件呈现”解耦，负责维护事件序号、缩进层级、
节点与 Link 的稳定标识、格式化输出，以及 handler 抛错时的隔离与记录，从而让追踪能力
既足够详细，又不会干扰正常运行路径。

协作关系：
它依赖 constants 提供节点类型与 flags 语义，并被 graph、scheduler、engine、primitives
在关键路径中调用 emit/enter/leave 发出结构化事件；init.lua 再把 tracer 和 trace handler
控制函数统一暴露给外部示例、调试脚本与测试使用。

核心概念：
本模块处理的关键概念包括 handler、sequence、depth、lastError，弱键表 nodeIds/linkIds，
nodeLabel 与 linkLabel 的稳定命名，flagsText 的位标志可视化，以及包含 nodeType、
nodeLabel、flagsText 和 data 的事件对象。
]]

local bit = require("bit")

local constants = require("refactored.constants")

local ReactiveFlags = constants.ReactiveFlags

local tracer = {}

local handler = nil
local sequence = 0
local depth = 0
local lastError = nil

local nodeIds = setmetatable({}, { __mode = "k" })
local linkIds = setmetatable({}, { __mode = "k" })
local nextNodeId = 0
local nextLinkId = 0

local FLAG_ORDER = {
    { "Mutable", ReactiveFlags.Mutable },
    { "Watching", ReactiveFlags.Watching },
    { "RecursedCheck", ReactiveFlags.RecursedCheck },
    { "Recursed", ReactiveFlags.Recursed },
    { "Dirty", ReactiveFlags.Dirty },
    { "Pending", ReactiveFlags.Pending },
    { "HasChildEffect", constants.HAS_CHILD_EFFECT },
}

local DATA_ORDER = {
    "link",
    "dep",
    "sub",
    "from",
    "to",
    "value",
    "changed",
    "action",
    "reason",
    "result",
    "flagsBefore",
    "flagsAfter",
    "batchDepth",
    "queueSize",
    "note",
}

local DATA_LABELS = {
    dep = "dep",
    sub = "sub",
    from = "from",
    to = "to",
    value = "value",
    changed = "changed",
    action = "action",
    reason = "reason",
    result = "result",
    batchDepth = "batch",
    queueSize = "queue",
    note = "note",
}

local function hasKey(tableValue, key)
    return tableValue ~= nil and rawget(tableValue, key) ~= nil
end

local function nodeKind(node)
    if type(node) ~= "table" then
        return type(node)
    end

    if constants.isSignalNode(node) then
        return "signal"
    end

    if constants.isComputedNode(node) then
        return "computed"
    end

    if constants.isEffectNode(node) then
        return "effect"
    end

    if constants.isEffectScopeNode(node) then
        return "scope"
    end

    return "node"
end

local function ensureNodeId(node)
    if type(node) ~= "table" then
        return nil
    end

    local id = nodeIds[node]
    if not id then
        nextNodeId = nextNodeId + 1
        id = nextNodeId
        nodeIds[node] = id
    end

    return id
end

local function ensureLinkId(link)
    if type(link) ~= "table" then
        return nil
    end

    local id = linkIds[link]
    if not id then
        nextLinkId = nextLinkId + 1
        id = nextLinkId
        linkIds[link] = id
    end

    return id
end

-- 判断当前是否启用了追踪输出。
function tracer.isEnabled()
    return handler ~= nil
end

-- 注入事件处理器；传 nil 可关闭追踪。
function tracer.setHandler(nextHandler)
    handler = nextHandler
    lastError = nil
end

-- 关闭追踪输出。
function tracer.clearHandler()
    handler = nil
end

-- 重置事件序号、缩进层级和调试 ID。
function tracer.reset()
    sequence = 0
    depth = 0
    lastError = nil
    nodeIds = setmetatable({}, { __mode = "k" })
    linkIds = setmetatable({}, { __mode = "k" })
    nextNodeId = 0
    nextLinkId = 0
end

-- 返回最近一次 handler 抛出的错误。
function tracer.getLastError()
    return lastError
end

-- 把普通值格式化成适合日志阅读的短文本。
function tracer.valueText(value)
    local valueType = type(value)

    if value == nil then
        return "nil"
    end

    if valueType == "string" then
        return string.format("%q", value)
    end

    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end

    return valueType .. ":" .. tostring(value)
end

-- 包装一个可为 nil 的值，供 data formatter 原样展示。
function tracer.value(value)
    return {
        __traceKind = "value",
        text = tracer.valueText(value),
    }
end

-- 把 flags 整数格式化为标志名列表。
function tracer.flagsText(flags)
    if flags == nil then
        return "nil"
    end

    if flags == ReactiveFlags.None then
        return "None"
    end

    local names = {}
    local knownMask = ReactiveFlags.None

    for _, entry in ipairs(FLAG_ORDER) do
        local name = entry[1]
        local flag = entry[2]
        knownMask = bit.bor(knownMask, flag)

        if bit.band(flags, flag) ~= 0 then
            names[#names + 1] = name
        end
    end

    local unknownMask = bit.band(flags, bit.bnot(knownMask))
    if unknownMask ~= 0 then
        names[#names + 1] = "Unknown(" .. tostring(unknownMask) .. ")"
    end

    return table.concat(names, "|")
end

-- 返回节点的稳定调试标签。如果节点有 customLabel，优先使用它。
function tracer.nodeLabel(node)
    local id = ensureNodeId(node)
    if not id then
        return "nil"
    end

    if type(node.customLabel) == "string" and node.customLabel ~= "" then
        return nodeKind(node) .. "#" .. node.customLabel
    end

    return nodeKind(node) .. "#" .. tostring(id)
end

-- 返回 Link 的稳定调试标签。
function tracer.linkLabel(link)
    local id = ensureLinkId(link)
    if not id then
        return "nil"
    end

    return "link#" .. tostring(id)
end

local function dataValueText(key, value)
    if type(value) == "table" and value.__traceKind == "value" then
        return value.text
    end

    if key == "link" then
        return tracer.linkLabel(value)
    end

    if key == "dep" or key == "sub" then
        return tracer.nodeLabel(value)
    end

    if key == "flagsBefore" or key == "flagsAfter" then
        return tracer.flagsText(value)
    end

    if key == "action" or key == "reason" or key == "result" or key == "note" then
        return tostring(value)
    end

    return tracer.valueText(value)
end

local function appendDataPart(parts, key, value)
    local label = DATA_LABELS[key] or key
    parts[#parts + 1] = label .. "=" .. dataValueText(key, value)
end

local function formatData(data)
    if not data then
        return ""
    end

    local parts = {}
    local seen = {}

    if hasKey(data, "flagsBefore") and hasKey(data, "flagsAfter") then
        parts[#parts + 1] = "flags="
            .. tracer.flagsText(data.flagsBefore)
            .. "->"
            .. tracer.flagsText(data.flagsAfter)
        seen.flagsBefore = true
        seen.flagsAfter = true
    elseif hasKey(data, "flagsBefore") then
        parts[#parts + 1] = "flags=" .. tracer.flagsText(data.flagsBefore)
        seen.flagsBefore = true
    elseif hasKey(data, "flagsAfter") then
        parts[#parts + 1] = "flags=" .. tracer.flagsText(data.flagsAfter)
        seen.flagsAfter = true
    end

    for _, key in ipairs(DATA_ORDER) do
        if not seen[key] and hasKey(data, key) then
            appendDataPart(parts, key, data[key])
            seen[key] = true
        end
    end

    for key, value in pairs(data) do
        if not seen[key] then
            appendDataPart(parts, key, value)
        end
    end

    return table.concat(parts, " ")
end

-- 把结构化事件格式化成一行教学日志。
function tracer.formatEvent(event)
    local indent = string.rep("  ", event.depth or 0)
    local line = string.format(
        "%03d %-24s",
        event.seq,
        indent .. event.name
    )

    if event.nodeLabel then
        line = line .. " " .. event.nodeLabel
    end

    local detail = formatData(event.data)
    if detail ~= "" then
        line = line .. "  " .. detail
    end

    return line
end

-- 创建一个把事件格式化后输出的 handler。
function tracer.consoleHandler(writeLine)
    local writer = writeLine or print

    return function(event)
        writer(tracer.formatEvent(event))
    end
end

-- 发出一条结构化追踪事件。
function tracer.emit(name, node, data)
    if not handler then
        return nil
    end

    sequence = sequence + 1

    local event = {
        seq = sequence,
        name = name,
        node = node,
        nodeId = ensureNodeId(node),
        nodeType = nodeKind(node),
        nodeLabel = node and tracer.nodeLabel(node) or nil,
        flags = node and node.flags or nil,
        flagsText = node and tracer.flagsText(node.flags) or nil,
        depth = depth,
        data = data or {},
    }

    local ok, err = pcall(handler, event)
    if not ok then
        lastError = err
        handler = nil
    end

    return event
end

-- 进入一个可缩进展示的执行阶段。
function tracer.enter(name, node, data)
    if not handler then
        return
    end

    tracer.emit(name .. ":start", node, data)
    if handler then
        depth = depth + 1
    end
end

-- 离开一个可缩进展示的执行阶段。
function tracer.leave(name, node, data)
    if not handler then
        return
    end

    if depth > 0 then
        depth = depth - 1
    end

    tracer.emit(name .. ":end", node, data)
end

return tracer
