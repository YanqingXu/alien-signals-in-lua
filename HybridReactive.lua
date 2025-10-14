--[[
 * HybridReactive - A comprehensive reactive system for Lua
 * HybridReactive - Lua 的综合响应式系统
 *
 * This module provides a Vue.js-like reactive programming interface built on top of
 * the alien-signals reactive system. It offers:
 * - ref() for reactive references
 * - computed() for computed values
 * - watch() for watching reactive changes
 * - reactive() for reactive objects
 *
 * 该模块基于 alien-signals 响应式系统提供类似 Vue.js 的响应式编程接口。它提供：
 * - ref() 用于响应式引用
 * - computed() 用于计算值
 * - watch() 用于监听响应式变化
 * - reactive() 用于响应式对象
 * - watchRef() 用于监听 ref 对象
 * - watchReactive() 用于监听响应式对象
 *
 * Based on the alien-signals reactive system architecture
 * 基于 alien-signals 响应式系统架构
]]

-- Import the core reactive system
-- 导入核心响应式系统
local reactive = require("reactive")
local HybridReactive = {}


--[[
 * ================== ref Implementation ==================
 * ================== ref 实现 ==================
]]

--[[
 * Creates a reactive reference that wraps a value
 * 创建包装值的响应式引用
 *
 * @param initialValue: The initial value / 初始值
 * @return: A ref object with .value property / 具有 .value 属性的 ref 对象
]]
function HybridReactive.ref(initialValue)
    local signal = reactive.signal(initialValue)

    local refObj = {
        __signal = signal  -- Keep reference to the underlying signal
    }

    -- Create metatable for getter/setter behavior
    local mt = {
        __index = function(t, key)
            if key ~= "value" then
                error("Cannot access property on ref object: key=".. key)
            end

            -- Get operation: call signal()
            return signal()
        end,

        __newindex = function(t, key, newValue)
            if key ~= "value" then
                error("Cannot set value on ref object: key=".. key .. ", value=".. newValue)
            end

            -- Set operation: call signal(newValue)
            signal(newValue)
        end
    }

    setmetatable(refObj, mt)
    return refObj
end


--[[
 * ================== computed Implementation ==================
 * ================== computed 实现 ==================
]]

--[[
 * Creates a computed value that automatically updates when its dependencies change
 * 创建在依赖变化时自动更新的计算值
 *
 * @param getter: Function that computes the value / 计算值的函数
 * @return: A computed ref object / 计算值 ref 对象
]]
function HybridReactive.computed(getter)
    local computedSignal = reactive.computed(getter)

    local computedObj = {
        __signal = computedSignal  -- Keep reference to the underlying computed
    }

    -- Create metatable for getter behavior (computed is read-only)
    local mt = {
        __index = function(t, key)
            if key ~= "value" then
                error("Cannot access property on computed object: key=".. key)
            end

            -- Get operation: call computedSignal()
            return computedSignal()
        end,

        -- computed obj is readonly
        __newindex = function(t, key, newValue)
            error("Cannot set value on computed property: key=".. key .. ", value=".. newValue)
        end
    }

    setmetatable(computedObj, mt)
    return computedObj
end


--[[
 * ================== reactive Implementation ==================
 * ================== reactive 实现 ==================
]]

--[[
 * Creates a reactive proxy for an object
 * 为对象创建响应式代理
 *
 * @param obj: Object to make reactive / 要变为响应式的对象
 * @return: Reactive proxy object / 响应式代理对象
]]
function HybridReactive.reactive(obj, shallow)
    if type(obj) ~= "table" then
        error("reactive() can only be called on objects")
    end

    -- Default to deep reactive (shallow = false)
    -- 默认为深层响应式 (shallow = false)
    if shallow == nil then
        shallow = false
    end

    local signals = {}
    local proxy = {
        __signals = signals  -- Store reference to signals for watchReactive
    }

    -- Helper function to process value based on shallow flag
    -- 根据 shallow 标志处理值的辅助函数
    local function processValue(value)
        -- Shallow reactive or non-table: keep original value
        -- 浅层响应式或非表类型：保持原始值
        if shallow or type(value) ~= "table" then
            return value
        end

        -- Check if it's already a reactive or ref object
        -- 检查是否已经是响应式或ref对象
        local isAlreadyReactive = false
        local isAlreadyRef = false

        -- Safe check for reactive object
        -- 安全检查响应式对象
        local success1, result1 = pcall(function()
            return HybridReactive.isReactive(value)
        end)
        if success1 then
            isAlreadyReactive = result1
        end

        -- Safe check for ref object
        -- 安全检查ref对象
        local success2, result2 = pcall(function()
            return HybridReactive.isRef(value)
        end)
        if success2 then
            isAlreadyRef = result2
        end

        -- Already reactive or ref: keep original value
        -- 已经是响应式或ref：保持原始值
        if isAlreadyReactive or isAlreadyRef then
            return value
        end

        -- Deep reactive: recursively make nested objects reactive
        -- 深层响应式：递归地使嵌套对象变为响应式
        return HybridReactive.reactive(value, false)
    end

    -- Create signals for each property
    -- 为每个属性创建信号
    for key, value in pairs(obj) do
        local processedValue = processValue(value)
        signals[key] = reactive.signal(processedValue)
    end

    -- Create proxy with getter/setter
    -- 创建带有 getter/setter 的代理
    local mt = {
        __index = function(t, key)
            if key == "__signals" then
                return signals
            end
            if signals[key] then
                return signals[key]()
            end
            return nil
        end,

        __newindex = function(t, key, value)
            if key == "__signals" then
                error("Cannot modify __signals property")
            end

            local processedValue = processValue(value)

            if not signals[key] then
                signals[key] = reactive.signal(processedValue)
            else
                signals[key](processedValue)
            end
        end,
    }

    setmetatable(proxy, mt)
    return proxy
end


--[[
 * Watches a ref object and calls a callback when its value changes
 * 监听 ref 对象并在其值变化时调用回调
 *
 * @param refObj: The ref object to watch / 要监听的 ref 对象
 * @param callback: Function to call when ref value changes, receives (newValue, oldValue) / 当 ref 值变化时调用的函数，接收 (新值, 旧值)
 * @return: Stop function to stop watching / 停止监听的函数
]]
function HybridReactive.watchRef(refObj, callback)
    -- Validate that the first parameter is a ref object
    -- 验证第一个参数是 ref 对象
    if not HybridReactive.isRef(refObj) then
        error("watchRef: first parameter must be a ref object")
    end

    if type(callback) ~= "function" then
        error("watchRef: second parameter must be a function")
    end

    -- Store the previous value
    -- 存储之前的值
    local oldValue = refObj.value

    -- Create an effect that watches the ref
    -- 创建监听 ref 的副作用
    return reactive.effect(function()
        local newValue = refObj.value  -- This will trigger dependency tracking

        -- Only call callback if value actually changed
        -- 只有在值真正改变时才调用回调
        if newValue ~= oldValue then
            callback(newValue, oldValue)
            oldValue = newValue  -- Update old value for next comparison
        end
    end)
end

--[[
 * Watch a reactive object for property changes
 * 监听响应式对象的属性变化
 *
 * @param reactiveObj: Reactive object to watch / 要监听的响应式对象
 * @param callback: Function called when any property changes / 属性变化时调用的函数
 *                 callback(key, newValue, oldValue, path)
 * @param shallow: If true, only watch first-level properties; if false,
 *                 watch nested objects recursively
 *                / 如果为true，只监听第一层属性；如果为false，递归监听嵌套对象
 * @return: Function to stop watching / 停止监听的函数
]]
function HybridReactive.watchReactive(reactiveObj, callback, shallow)
    -- Validate parameters
    -- 验证参数
    if not HybridReactive.isReactive(reactiveObj) then
        error("watchReactive: first parameter must be a reactive object")
    end

    if type(callback) ~= "function" then
        error("watchReactive: second parameter must be a function")
    end

    -- Default to deep watching (shallow = false)
    -- 默认为深层监听 (shallow = false)
    if shallow == nil then
        shallow = false
    end

    -- Store all stop functions and tracking state
    -- 存储所有停止函数和跟踪状态
    local allStopFunctions = {}
    local isActive = true
    local watchedObjects = {}  -- Prevent circular references / 防止循环引用

    -- Function to watch a single reactive object
    -- 监听单个响应式对象的函数
    local function watchSingleObject(obj, pathPrefix)
        -- Prevent circular references
        -- 防止循环引用
        if watchedObjects[obj] then
            return
        end
        watchedObjects[obj] = true

        -- Get the signals table from the reactive object
        -- 从响应式对象获取信号表
        local signals = obj.__signals
        if not signals then
            return
        end

        -- Store old values for comparison
        -- 存储旧值用于比较
        local oldValues = {}
        local watchedKeys = {}

        -- Function to create watcher for a specific key
        -- 为特定键创建监听器的函数
        local function createWatcher(key, signal)
            if watchedKeys[key] or not isActive then
                return
            end

            watchedKeys[key] = true
            oldValues[key] = signal()

            local stopEffect = reactive.effect(function()
                if not isActive then return end

                local newValue = signal()  -- This establishes dependency tracking
                local oldValue = oldValues[key]

                -- Only call callback if value actually changed
                -- 只有在值真正改变时才调用回调
                if newValue ~= oldValue then
                    local fullPath = pathPrefix and (pathPrefix .. "." .. key) or key
                    callback(key, newValue, oldValue, fullPath)
                    oldValues[key] = newValue  -- Update old value for next comparison

                    -- If not shallow and new value is reactive, watch it recursively
                    -- 如果不是浅层监听且新值是响应式的，递归监听它
                    if not shallow and HybridReactive.isReactive(newValue) and not watchedObjects[newValue] then
                        -- Pause tracking to avoid dependency issues when creating nested watchers
                        -- 暂停跟踪以避免创建嵌套监听器时的依赖问题
                        -- v3.0.0: Use setActiveSub instead of pauseTracking/resumeTracking
                        local prevSub = reactive.setActiveSub(nil)
                        watchSingleObject(newValue, fullPath)
                        reactive.setActiveSub(prevSub)
                    end
                end
            end)

            table.insert(allStopFunctions, stopEffect)
        end

        -- Create watchers for existing properties
        -- 为现有属性创建监听器
        for key, signal in pairs(signals) do
            createWatcher(key, signal)

            -- If not shallow, recursively watch nested reactive objects
            -- 如果不是浅层监听，递归监听嵌套的响应式对象
            if not shallow then
                local currentValue = signal()
                if HybridReactive.isReactive(currentValue) and not watchedObjects[currentValue] then
                    local nestedPath = pathPrefix and (pathPrefix .. "." .. key) or key
                    watchSingleObject(currentValue, nestedPath)
                end
            end
        end
    end

    -- Start watching from the root object
    -- 从根对象开始监听
    watchSingleObject(reactiveObj, nil)

    -- Note: Dynamic property addition is limited by current reactive design
    -- The reactive object doesn't automatically notify when new properties are added
    -- 注意：动态属性添加受当前响应式设计限制
    -- 响应式对象在添加新属性时不会自动通知

    -- Return a function that stops all watchers
    -- 返回停止所有监听器的函数
    return function()
        isActive = false
        for _, stopFn in ipairs(allStopFunctions) do
            stopFn()
        end
    end
end

--[[
 * ================== Utility Functions ==================
 * ================== 工具函数 ==================
]]

-- Check if a value is a ref
-- 检查值是否为 ref
function HybridReactive.isRef(value)
    return type(value) == "table" and value.__signal ~= nil
end

-- Check if a value is reactive
-- 检查值是否为响应式
function HybridReactive.isReactive(value)
    if type(value) ~= "table" then
        return false
    end

    -- First check if it's a ref object (refs are not reactive objects)
    -- 首先检查是否为ref对象（ref不是响应式对象）
    if HybridReactive.isRef(value) then
        return false
    end

    local mt = getmetatable(value)
    if not mt then
        return false
    end

    -- Check if it's a reactive object (has __index and __newindex for reactive behavior)
    -- and has __signals property
    return mt.__index ~= nil and mt.__newindex ~= nil and value.__signals ~= nil
end

--[[
 * ================== Module Export ==================
 * ================== 模块导出 ==================
]]

return {
    ref = HybridReactive.ref,
    reactive = HybridReactive.reactive,
    computed = HybridReactive.computed,

    watch = reactive.effect,
    watchRef = HybridReactive.watchRef,
    watchReactive = HybridReactive.watchReactive,

    isReactive = HybridReactive.isReactive,
    isRef = HybridReactive.isRef,

    startBatch = reactive.startBatch,
    endBatch = reactive.endBatch,
}