--[[
 * Alien Signals - A reactive programming system for Lua
 * Alien Signals - Lua 响应式编程系统
 *
 * Version: 2.0.7 (compatible with alien-signals v2.0.7)
 * 版本: 2.0.7 (兼容 alien-signals v2.0.7)
 *
 * Derived from https://github.com/stackblitz/alien-signals
 * 源自 https://github.com/stackblitz/alien-signals
 *
 * This module implements a full-featured reactivity system with automatic
 * dependency tracking and efficient updates propagation. It provides:
 * - Reactive signals (mutable reactive values)
 * - Computed values (derived reactive values)
 * - Effects (side effects that run when dependencies change)
 * - Effect scopes (grouping and cleanup of multiple effects)
 * - Batch updates (efficient bulk state changes)
 *
 * 该模块实现了一个功能完整的响应式系统，具有自动依赖跟踪和高效的更新传播。它提供：
 * - 响应式信号（可变的响应式值）
 * - 计算值（派生的响应式值）
 * - 副作用（当依赖变化时运行的副作用）
 * - 副作用作用域（多个副作用的分组和清理）
 * - 批量更新（高效的批量状态变更）
]]

local bit = require("bit")

local reactive = {}

--[[
 * Simple function binding utility
 * 简单的函数绑定工具
 *
 * This creates a closure that binds the first argument to a function,
 * enabling object-oriented-like behavior for reactive primitives.
 * 这创建一个闭包，将第一个参数绑定到函数，
 * 为响应式原语启用类似面向对象的行为。
]]
local function bind(func, obj)
    return function(...)
        return func(obj, ...)
    end
end

--[[
 * Bit flags used to track the state of reactive objects
 * 用于跟踪响应式对象状态的位标志
 *
 * These flags use bitwise operations for efficient state management.
 * Multiple flags can be combined using bitwise OR operations.
 * 这些标志使用位运算进行高效的状态管理。
 * 多个标志可以使用位或运算组合。
]]
local ReactiveFlags = {
    None = 0,          -- 0000000: Default state / 默认状态
    Mutable = 1,       -- 0000001: Can be changed (signals and computed values) / 可变的（信号和计算值）
    Watching = 2,      -- 0000010: Actively watching for changes (effects) / 主动监听变化（副作用）
    RecursedCheck = 4, -- 0000100: Being checked for circular dependencies / 正在检查循环依赖
    Recursed = 8,      -- 0001000: Has been visited during recursion check / 在递归检查中已被访问
    Dirty = 16,        -- 0010000: Value has changed and needs update / 值已改变需要更新
    Pending = 32,      -- 0100000: Might be dirty, needs checking / 可能是脏的，需要检查
}

--[[
 * Additional flags specific to effects
 * 副作用特有的额外标志
]]
local EffectFlags = {
    Queued = 64,       -- 1000000: Effect is queued for execution (1 << 6) / 副作用已排队等待执行
}

--[[
 * Global state for tracking current active subscriber and scope
 * 用于跟踪当前活动订阅者和作用域的全局状态
 *
 * These variables maintain the execution context during reactive operations.
 * They enable automatic dependency collection when signals are accessed.
 * 这些变量在响应式操作期间维护执行上下文。
 * 它们在访问信号时启用自动依赖收集。
]]
local g_activeSub = nil    -- Current active effect or computed value / 当前活动的副作用或计算值
local g_activeScope = nil  -- Current active effect scope / 当前活动的副作用作用域

--[[
 * Stack for pausing and resuming tracking
 * 用于暂停和恢复跟踪的栈
 *
 * This allows temporary suspension of dependency tracking,
 * useful for operations that shouldn't create dependencies.
 * 这允许临时暂停依赖跟踪，
 * 对于不应该创建依赖的操作很有用。
]]
local g_pauseStack = {}

--[[
 * Queue for batched effect execution
 * 批量副作用执行的队列
 *
 * Effects are queued and executed together for better performance.
 * This prevents redundant executions when multiple dependencies change.
 * 副作用被排队并一起执行以获得更好的性能。
 * 这防止了当多个依赖变化时的冗余执行。
]]
local g_queuedEffects = {}       -- Effects waiting to be executed / 等待执行的副作用
local g_queuedEffectsLength = 0  -- Length of the queue / 队列长度

--[[
 * Batch update state
 * 批量更新状态
 *
 * Batch operations allow multiple state changes to be grouped together,
 * with effects only running once at the end of the batch.
 * 批量操作允许将多个状态变更分组在一起，
 * 副作用只在批量结束时运行一次。
]]
local g_batchDepth = 0    -- Depth of nested batch operations / 嵌套批量操作的深度
local g_notifyIndex = 0   -- Current position in the effects queue / 副作用队列中的当前位置

--[[
 * Global version counter for dependency link deduplication
 * 用于依赖链接去重的全局版本计数器
 *
 * This counter is incremented at the start of each tracking cycle to ensure
 * that dependency links created in the same cycle can be properly deduplicated.
 * 该计数器在每个跟踪周期开始时递增，以确保在同一周期内创建的依赖链接可以正确去重。
]]
local g_currentVersion = 0       -- Global current version counter for link deduplication / 用于链接去重的全局当前版本计数器

--[[
 * Sets the current subscriber (effect or computed) and returns the previous one
 * 设置当前订阅者（副作用或计算值）并返回之前的订阅者
 *
 * @param sub: New subscriber to set as active / 要设置为活动的新订阅者
 * @return: Previous active subscriber / 之前的活动订阅者
 *
 * This function manages the execution context stack. When a reactive function
 * (effect or computed) runs, it becomes the active subscriber, allowing any
 * signals accessed during its execution to automatically register as dependencies.
 *
 * 该函数管理执行上下文栈。当响应式函数（副作用或计算值）运行时，
 * 它成为活动订阅者，允许在其执行期间访问的任何信号自动注册为依赖。
]]
function reactive.setCurrentSub(sub)
    local prevSub = g_activeSub
    g_activeSub = sub
    return prevSub
end

--[[
 * Sets the current effect scope and returns the previous one
 * 设置当前副作用作用域并返回之前的作用域
 *
 * @param scope: New scope to set as active / 要设置为活动的新作用域
 * @return: Previous active scope / 之前的活动作用域
 *
 * Effect scopes provide a way to group multiple effects together for
 * collective cleanup. When effects are created within a scope, they
 * automatically become children of that scope.
 *
 * 副作用作用域提供了将多个副作用分组在一起进行集体清理的方法。
 * 当在作用域内创建副作用时，它们自动成为该作用域的子级。
]]
function reactive.setCurrentScope(scope)
    local prevScope = g_activeScope
    g_activeScope = scope
    return prevScope
end

--[[
 * Starts a batch update - effects won't be executed until endBatch is called
 * 开始批量更新 - 副作用不会执行直到调用 endBatch
 *
 * This is useful for multiple updates that should be treated as one atomic operation.
 * Batching prevents intermediate effect executions and improves performance.
 * Batch operations can be nested - effects only run when the outermost batch ends.
 *
 * 这对于应该被视为一个原子操作的多个更新很有用。
 * 批处理防止中间副作用执行并提高性能。
 * 批量操作可以嵌套 - 副作用只在最外层批量结束时运行。
]]
function reactive.startBatch()
    g_batchDepth = g_batchDepth + 1
end

--[[
 * Ends a batch update and flushes pending effects if this is the outermost batch
 * 结束批量更新，如果这是最外层批量则刷新待处理的副作用
 *
 * When the batch depth reaches zero, all queued effects are executed.
 * This ensures that effects only run once per batch, even if multiple
 * dependencies changed during the batch.
 *
 * 当批量深度达到零时，所有排队的副作用都会被执行。
 * 这确保副作用每批只运行一次，即使在批量期间多个依赖发生了变化。
]]
function reactive.endBatch()
    g_batchDepth = g_batchDepth - 1
    if 0 == g_batchDepth then
        reactive.flush()
    end
end

--[[
 * Temporarily pauses dependency tracking
 * 临时暂停依赖跟踪
 *
 * This pushes the current subscriber onto a stack and clears the active subscriber.
 * Useful when you need to access reactive values without creating dependencies.
 * Must be paired with resumeTracking() to restore the previous state.
 *
 * 这将当前订阅者推入栈并清除活动订阅者。
 * 当您需要访问响应式值而不创建依赖时很有用。
 * 必须与 resumeTracking() 配对以恢复之前的状态。
]]
function reactive.pauseTracking()
    g_pauseStack[#g_pauseStack + 1] = reactive.setCurrentSub()
end

--[[
 * Resumes dependency tracking after a pause
 * 暂停后恢复依赖跟踪
 *
 * This pops the previous subscriber from the stack and restores it as active.
 * Must be called after pauseTracking() to maintain proper tracking state.
 *
 * 这从栈中弹出之前的订阅者并将其恢复为活动状态。
 * 必须在 pauseTracking() 之后调用以维护正确的跟踪状态。
]]
function reactive.resumeTracking()
    local top = table.remove(g_pauseStack, #g_pauseStack)
    reactive.setCurrentSub(top)
end

--[[
 * Executes all queued effects
 * 执行所有排队的副作用
 *
 * This is called automatically when a batch update ends or when a signal
 * changes outside of a batch. It processes the effect queue in order,
 * clearing the queued flag and running each effect.
 *
 * 这在批量更新结束时或信号在批量外部变化时自动调用。
 * 它按顺序处理副作用队列，清除排队标志并运行每个副作用。
]]
function reactive.flush()
    while g_notifyIndex < g_queuedEffectsLength do
        local effect = g_queuedEffects[g_notifyIndex+1]
        g_queuedEffects[g_notifyIndex+1] = nil
        g_notifyIndex = g_notifyIndex + 1

        if effect then
            -- Clear the queued flag and run the effect
            -- 清除排队标志并运行副作用
            effect.flags = bit.band(effect.flags, bit.bnot(EffectFlags.Queued))
            reactive.run(effect, effect.flags)
        end
    end

    -- Reset queue state after processing all effects
    -- 处理完所有副作用后重置队列状态
    g_notifyIndex = 0
    g_queuedEffectsLength = 0
end

--[[
 * Runs an effect based on its current state
 * 根据当前状态运行副作用
 *
 * @param e: The effect to run / 要运行的副作用
 * @param flags: Current state flags of the effect / 副作用的当前状态标志
 *
 * This function determines whether an effect needs to run based on its flags.
 * Effects run when they are dirty (definitely need update) or pending (might need update).
 * During execution, the effect becomes the active subscriber to collect new dependencies.
 *
 * 该函数根据标志确定副作用是否需要运行。
 * 副作用在脏（确实需要更新）或待定（可能需要更新）时运行。
 * 在执行期间，副作用成为活动订阅者以收集新的依赖。
]]
function reactive.run(e, flags)
    local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
    local isPending = bit.band(flags, ReactiveFlags.Pending) > 0

    -- If the effect is dirty or it's pending and has dirty dependencies
    -- 如果副作用是脏的，或者它是待定的且有脏依赖
    if isDirty or (isPending and reactive.checkDirty(e.deps, e)) then
        -- Track effect execution to collect dependencies
        -- 跟踪副作用执行以收集依赖
        local prev = reactive.setCurrentSub(e)
        reactive.startTracking(e)

        -- Execute the effect function safely
        -- 安全地执行副作用函数
        local result, err = pcall(e.fn)
        if not result then
            print("Error in effect: " .. err)
        end

        -- Restore previous state and finish tracking
        -- 恢复之前的状态并完成跟踪
        reactive.setCurrentSub(prev)
        reactive.endTracking(e)

        return
    end

    -- Clear pending flag if needed
    -- 如果需要，清除待定标志
    if isPending then
        e.flags = bit.band(flags, bit.bnot(ReactiveFlags.Pending))
    end

    -- Process queued dependent effects
    -- 处理排队的依赖副作用
    local link = e.deps
    while link do
        local dep = link.dep
        local depFlags = dep.flags

        -- If dependent effect is queued, run it
        -- 如果依赖副作用已排队，运行它
        if bit.band(depFlags, EffectFlags.Queued) > 0 then
            dep.flags = bit.band(depFlags, bit.bnot(EffectFlags.Queued))
            reactive.run(dep, dep.flags)
        end

        link = link.nextDep
    end
end

--[[
 * Creates a dependency link node in the doubly-linked list
 * 在双向链表中创建依赖链接节点
 *
 * @param dep: Dependency (signal or computed) / 依赖（信号或计算值）
 * @param sub: Subscriber (effect or computed) / 订阅者（副作用或计算值）
 * @param prevSub, nextSub: Previous and next links in the subscriber chain / 订阅者链中的前一个和下一个链接
 * @param prevDep, nextDep: Previous and next links in the dependency chain / 依赖链中的前一个和下一个链接
 * @return: New link object / 新的链接对象
 *
 * Each link exists in two doubly-linked lists simultaneously:
 * 1. The dependency's subscriber list (vertical, linking all subscribers of a dependency)
 * 2. The subscriber's dependency list (horizontal, linking all dependencies of a subscriber)
 *
 * This dual-list structure enables efficient traversal and cleanup operations.
 *
 * 每个链接同时存在于两个双向链表中：
 * 1. 依赖的订阅者列表（垂直，链接依赖的所有订阅者）
 * 2. 订阅者的依赖列表（水平，链接订阅者的所有依赖）
 *
 * 这种双列表结构使得遍历和清理操作更加高效。
]]
function reactive.createLink(dep, sub, prevSub, nextSub, prevDep, nextDep)
    return {
        version = 0,      -- Version number for deduplication / 用于去重的版本号
        dep = dep,        -- The dependency object / 依赖对象
        sub = sub,        -- The subscriber object / 订阅者对象
        prevSub = prevSub, -- Previous link in the subscriber's chain / 订阅者链中的前一个链接
        nextSub = nextSub, -- Next link in the subscriber's chain / 订阅者链中的下一个链接
        prevDep = prevDep, -- Previous link in the dependency's chain / 依赖链中的前一个链接
        nextDep = nextDep  -- Next link in the dependency's chain / 依赖链中的下一个链接
    }
end

--[[
 * Establishes a dependency relationship between a dependency (dep) and a subscriber (sub)
 * 在依赖（dep）和订阅者（sub）之间建立依赖关系
 *
 * This is the core of the dependency tracking system. It creates bidirectional
 * links in the reactive graph, allowing changes to propagate efficiently.
 *
 * @param dep: The reactive object being depended on (signal or computed) / 被依赖的响应式对象（信号或计算值）
 * @param sub: The reactive object depending on it (effect or computed) / 依赖它的响应式对象（副作用或计算值）
 *
 * The function handles several important cases:
 * 1. Avoiding duplicate links for the same dependency
 * 2. Managing circular dependency detection during recursion checks
 * 3. Maintaining proper doubly-linked list structure
 * 4. Optimizing for the common case where dependencies are added in order
 *
 * 该函数处理几个重要情况：
 * 1. 避免为同一依赖创建重复链接
 * 2. 在递归检查期间管理循环依赖检测
 * 3. 维护正确的双向链表结构
 * 4. 为按顺序添加依赖的常见情况进行优化
]]
function reactive.link(dep, sub)
    -- Check if this dependency is already the last one in the chain
    -- 检查这个依赖是否已经是链中的最后一个
    local prevDep = sub.depsTail
    if prevDep and prevDep.dep == dep then
        return
    end

    local nextDep = nil

    -- Handle circular dependency detection
    -- 处理循环依赖检测
    if bit.band(sub.flags, ReactiveFlags.RecursedCheck) > 0 then
        -- Correctly handle the case where prevDep.nextDep might be nil
        -- 正确处理prevDep.nextDep可能为nil的情况
        if prevDep then
            nextDep = prevDep.nextDep
        else
            nextDep = sub.deps
        end

        -- If we already have this dependency in the chain during recursion check
        -- 如果在递归检查期间链中已经有这个依赖
        if nextDep and nextDep.dep == dep then
            nextDep.version = g_currentVersion  -- Update version for current cycle / 为当前周期更新版本号
            sub.depsTail = nextDep
            return
        end
    end

    -- Check if the sub is already subscribed to this dependency using version-based deduplication
    -- 使用基于版本号的去重检查订阅者是否已经订阅了这个依赖
    local prevSub = dep.subsTail
    if prevSub and prevSub.version == g_currentVersion and prevSub.sub == sub then
        -- Only deduplicate if it's the same subscriber AND same tracking cycle (matching TypeScript logic)
        -- 只有在同一个订阅者且同一个跟踪周期时才去重（匹配TypeScript逻辑）
        return
    end

    -- Create a new link and insert it in both chains
    -- 创建新链接并将其插入到两个链中
    local newLink = reactive.createLink(dep, sub, prevDep, nextDep, prevSub)
    newLink.version = g_currentVersion  -- Set current version for deduplication / 设置当前版本号用于去重
    dep.subsTail = newLink  -- Add to dependency's subscribers chain / 添加到依赖的订阅者链
    sub.depsTail = newLink  -- Add to subscriber's dependencies chain / 添加到订阅者的依赖链

    -- Update next and previous pointers for proper doubly-linked list behavior
    -- 更新下一个和前一个指针以实现正确的双向链表行为
    if nextDep then
        nextDep.prevDep = newLink
    end

    if prevDep then
        prevDep.nextDep = newLink
    else
        sub.deps = newLink
    end

    if prevSub then
        prevSub.nextSub = newLink
    else
        dep.subs = newLink
    end
end

--[[
 * Removes a dependency link from both chains
 * 从两个链中移除依赖链接
 *
 * @param link: The link to remove / 要移除的链接
 * @param sub: The subscriber (can be provided explicitly or taken from link) / 订阅者（可以显式提供或从链接中获取）
 * @return: The next dependency link in the chain / 链中的下一个依赖链接
 *
 * This function carefully removes a link from both the dependency's subscriber list
 * and the subscriber's dependency list, maintaining the integrity of both doubly-linked lists.
 * When the last subscriber is removed from a dependency, it triggers cleanup.
 *
 * 该函数小心地从依赖的订阅者列表和订阅者的依赖列表中移除链接，
 * 保持两个双向链表的完整性。当从依赖中移除最后一个订阅者时，会触发清理。
]]
function reactive.unlink(link, sub)
    sub = sub or link.sub

    local dep = link.dep
    local prevDep = link.prevDep
    local nextDep = link.nextDep
    local nextSub = link.nextSub
    local prevSub = link.prevSub

    -- Remove from the dependency chain (horizontal)
    -- 从依赖链中移除（水平方向）
    if nextDep then
        nextDep.prevDep = prevSub
    else
        sub.depsTail = prevSub
    end

    if prevDep then
        prevDep.nextDep = nextDep
    else
        sub.deps = nextDep
    end

    -- Remove from the subscriber chain (vertical)
    -- 从订阅者链中移除（垂直方向）
    if nextSub then
        nextSub.prevSub = prevSub
    else
        dep.subsTail = prevSub
    end

    if prevSub then
        prevSub.nextSub = nextSub
    else
        dep.subs = nextSub

        -- If this was the last subscriber, notify the dependency it's no longer watched
        -- 如果这是最后一个订阅者，通知依赖它不再被监视
        if not nextSub then
            reactive.unwatched(dep)
        end
    end

    return nextDep
end

--[[
 * Processes subscriber flags and determines the appropriate action
 * 处理订阅者标志并确定适当的操作
 *
 * @param sub: The subscriber object / 订阅者对象
 * @param flags: Current flags of the subscriber / 订阅者的当前标志
 * @param link: The link connecting dependency and subscriber / 连接依赖和订阅者的链接
 * @return: Updated flags for further processing / 用于进一步处理的更新标志
 *
 * This function encapsulates the complex flag processing logic that determines
 * how a subscriber should respond to dependency changes. It handles various
 * states like recursion checking, dirty marking, and pending updates.
 *
 * 该函数封装了复杂的标志处理逻辑，确定订阅者应如何响应依赖变化。
 * 它处理各种状态，如递归检查、脏标记和待处理更新。
]]
local function processSubscriberFlags(sub, flags, link)
    -- Check if subscriber is mutable or watching (flags 1 | 2 = 3)
    -- 检查订阅者是否可变或正在监视（标志 1 | 2 = 3）
    if not bit.band(flags, 3) then
        return ReactiveFlags.None
    end

    -- Process different flag combinations
    -- 处理不同的标志组合

    -- Case 1: No recursion, dirty, or pending flags (60 = 4|8|16|32)
    -- 情况1：没有递归、脏或待处理标志
    if bit.band(flags, 60) == 0 then
        -- Set pending flag (32)
        -- 设置待处理标志
        sub.flags = bit.bor(flags, 32)
        return flags
    end

    -- Case 2: No recursion flags (12 = 4|8)
    -- 情况2：没有递归标志
    if bit.band(flags, 12) == 0 then
        return ReactiveFlags.None
    end

    -- Case 3: No RecursedCheck flag (4)
    -- 情况3：没有递归检查标志
    if bit.band(flags, 4) == 0 then
        -- Clear Recursed flag (8) and set Pending flag (32)
        -- 清除递归标志并设置待处理标志
        sub.flags = bit.bor(bit.band(flags, bit.bnot(8)), 32)
        return flags
    end

    -- Case 4: No Dirty or Pending flags (48 = 16|32) and valid link
    -- 情况4：没有脏或待处理标志且链接有效
    if bit.band(flags, 48) == 0 and reactive.isValidLink(link, sub) then
        -- Set Recursed and Pending flags (40 = 8|32)
        -- 设置递归和待处理标志
        sub.flags = bit.bor(flags, 40)
        return bit.band(flags, ReactiveFlags.Mutable)
    end

    -- Default case: clear all flags
    -- 默认情况：清除所有标志
    return ReactiveFlags.None
end

--[[
 * Handles the core propagation logic for a single subscriber
 * 处理单个订阅者的核心传播逻辑
 *
 * @param sub: Subscriber to process / 要处理的订阅者
 * @param flags: Subscriber's flags / 订阅者的标志
 * @param link: Link connecting dependency and subscriber / 连接依赖和订阅者的链接
 * @return: Subscriber's children (subs) if propagation should continue / 如果应该继续传播则返回订阅者的子级
]]
local function handleSubscriberPropagation(sub, flags, link)
    -- Process subscriber flags and get updated flags
    -- 处理订阅者标志并获取更新的标志
    local processedFlags = processSubscriberFlags(sub, flags, link)

    -- Notify if subscriber is watching
    -- 如果订阅者正在监视则通知
    if bit.band(processedFlags, ReactiveFlags.Watching) > 0 then
        reactive.notify(sub)
    end

    -- Continue propagation if subscriber is mutable
    -- 如果订阅者可变则继续传播
    if bit.band(processedFlags, ReactiveFlags.Mutable) > 0 then
        return sub.subs
    end

    return nil
end

--[[
 * Propagates changes through the dependency graph
 * 通过依赖图传播变化
 *
 * This function traverses the subscriber chain and notifies all affected subscribers
 * about dependency changes. It uses a simplified stack-based approach to handle
 * nested dependencies efficiently.
 *
 * 该函数遍历订阅者链并通知所有受影响的订阅者依赖变化。
 * 它使用简化的基于栈的方法来高效处理嵌套依赖。
]]
function reactive.propagate(link)
    local next = link.nextSub
    local stack = nil

    -- Use repeat...until true to simulate continue statements (classic Lua pattern)
    -- 使用repeat...until true模拟continue语句（经典Lua模式）
    repeat
        repeat
            local sub = link.sub
            local subSubs = handleSubscriberPropagation(sub, sub.flags, link)

            -- Handle mutable subscribers (exactly matching TypeScript logic)
            -- 处理可变订阅者（精确匹配TypeScript逻辑）
            if subSubs then
                -- const nextSub = (link = subSubs).nextSub;
                link = subSubs
                local nextSub = subSubs.nextSub
                if nextSub then
                    stack = {value = next, prev = stack}
                    next = nextSub
                end
                break  -- continue; (equivalent to TypeScript's continue)
            end

            -- if ((link = next!) !== undefined)
            link = next
            if link then
                next = link.nextSub
                break  -- continue; (equivalent to TypeScript's continue)
            end

            -- while (stack !== undefined)
            while stack do
                link = stack.value
                stack = stack.prev
                if link then
                    next = link.nextSub
                    break  -- continue top; (go to next iteration)
                end
            end

            if not link then
                return  -- break; (exit main loop)
            end
        until true
    until false
end

-- Begins dependency tracking for a subscriber
-- Called when an effect or computed value is about to execute its function
-- @param sub: The subscriber (effect or computed)
function reactive.startTracking(sub)
    -- Increment global version counter for this tracking cycle
    -- 为此跟踪周期递增全局版本计数器
    g_currentVersion = g_currentVersion + 1

    -- Reset dependency tail to collect dependencies from scratch
    sub.depsTail = nil

    -- Clear state flags and set RecursedCheck flag
    -- 56: Recursed | Dirty | Pending  4: RecursedCheck
    sub.flags = bit.bor(bit.band(sub.flags, bit.bnot(56)), 4)
end

-- Ends dependency tracking for a subscriber
-- Called after an effect or computed value has executed its function
-- Cleans up stale dependencies that were not accessed this time
-- @param sub: The subscriber (effect or computed)
function reactive.endTracking(sub)
    -- Find where to start removing dependencies
    local depsTail = sub.depsTail
    local toRemove = sub.deps
    if depsTail then
        toRemove = depsTail.nextDep
    end

    -- Remove all dependencies that were not accessed during this execution
    while toRemove do
        toRemove = reactive.unlink(toRemove, sub)
    end

    -- Clear the recursion check flag
    sub.flags = bit.band(sub.flags, bit.bnot(ReactiveFlags.RecursedCheck))
end

--[[
 * Processes the stack unwinding phase during dependency checking
 * 处理依赖检查期间的栈展开阶段
 *
 * @param checkDepth: Current check depth / 当前检查深度
 * @param sub: Current subscriber being processed / 当前正在处理的订阅者
 * @param stack: Stack for managing nested checks / 用于管理嵌套检查的栈
 * @param link: Current link being processed / 当前正在处理的链接
 * @param dirty: Whether dirty state was found / 是否发现脏状态
 * @return: Updated values {checkDepth, sub, stack, link, dirty, shouldGotoTop}
]]
local function processCheckStackUnwind(checkDepth, sub, stack, link, dirty)
    local gototop = false

    while checkDepth > 0 do
        local shouldExit = false

        checkDepth = checkDepth - 1
        local firstSub = sub.subs
        local hasMultipleSubs = firstSub.nextSub ~= nil

        if hasMultipleSubs then
            link = stack.value
            stack = stack.prev
        else
            link = firstSub
        end

        if dirty then
            if reactive.update(sub) then
                if hasMultipleSubs then
                    reactive.shallowPropagate(firstSub)
                end
                sub = link.sub
                shouldExit = true
            end
        else
            sub.flags = bit.band(sub.flags, bit.bnot(ReactiveFlags.Pending))
        end

        if not shouldExit then
            sub = link.sub
            if link.nextDep then
                link = link.nextDep
                gototop = true
                shouldExit = true
            else
                dirty = false
            end
        end

        if shouldExit then
            break
        end
    end

    return checkDepth, sub, stack, link, dirty, gototop
end

--[[
 * Processes a single step in the dirty checking phase
 * 处理脏值检查阶段的单个步骤
 *
 * @param link: Current link being processed / 当前正在处理的链接
 * @param sub: Current subscriber being processed / 当前正在处理的订阅者
 * @param stack: Stack for managing nested checks / 用于管理嵌套检查的栈
 * @param checkDepth: Current check depth / 当前检查深度
 * @return: Updated values {link, sub, stack, checkDepth, dirty, shouldReturn, shouldContinue}
]]
local function processDirtyCheckStep(link, sub, stack, checkDepth)
    local dep = link.dep
    local depFlags = dep.flags

    local dirty = false
    local isDirty = bit.band(sub.flags, ReactiveFlags.Dirty) > 0
    local bit_mut_or_dirty = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty)
    local bit_mut_or_pending = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Pending)
    local isMutOrDirty = bit.band(depFlags, bit_mut_or_dirty) == bit_mut_or_dirty
    local isMutOrPending = bit.band(depFlags, bit_mut_or_pending) == bit_mut_or_pending

    if isDirty then
        dirty = true
    elseif isMutOrDirty then
        if reactive.update(dep) then
            local subs = dep.subs
            if subs.nextSub then
                reactive.shallowPropagate(subs)
            end
            dirty = true
        end
    elseif isMutOrPending then
        if link.nextSub or link.prevSub then
            stack = { value = link, prev = stack }
        end

        link = dep.deps
        sub = dep
        checkDepth = checkDepth + 1
        return link, sub, stack, checkDepth, dirty, false, true
    end

    if not dirty and link.nextDep then
        link = link.nextDep
        return link, sub, stack, checkDepth, dirty, false, true
    end

    local gototop
    checkDepth, sub, stack, link, dirty, gototop = processCheckStackUnwind(checkDepth, sub, stack, link, dirty)

    if not gototop and checkDepth <= 0 then
        return link, sub, stack, checkDepth, dirty, true, false
    end

    return link, sub, stack, checkDepth, dirty, false, true
end

function reactive.checkDirty(link, sub)
    local stack = nil
    local checkDepth = 0

    while true do
        local dirty, shouldReturn, shouldContinue
        link, sub, stack, checkDepth, dirty, shouldReturn, shouldContinue =
            processDirtyCheckStep(link, sub, stack, checkDepth)

        if shouldReturn then
            return dirty
        end

        if not shouldContinue then
            break
        end
    end
end

function reactive.shallowPropagate(link)
    repeat
        local sub = link.sub
        local nextSub = link.nextSub
        local subFlags = sub.flags

        -- 48: Pending | Dirty,  32: Pending
        if bit.band(subFlags, 48) == 32 then
            sub.flags = bit.bor(subFlags, ReactiveFlags.Dirty)

            if bit.band(subFlags, ReactiveFlags.Watching) > 0 then
                reactive.notify(sub)
            end
        end

        link = nextSub
    until not link
end

function reactive.isValidLink(checkLink, sub)
    -- Simplified implementation: traverse backwards from depsTail (matching TypeScript v2.0.7)
    -- 简化实现：从depsTail向前遍历（匹配TypeScript v2.0.7）
    local link = sub.depsTail
    while link do
        if link == checkLink then
            return true
        end
        link = link.prevDep
    end
    return false
end

function reactive.updateSignal(signal, value)
    signal.flags = ReactiveFlags.Mutable
    if signal.previousValue == value then
        return false
    end

    signal.previousValue = value
    return true
end

function reactive.updateComputed(c)
    local prevSub = reactive.setCurrentSub(c)
    reactive.startTracking(c)

    local oldValue = c.value
    local newValue = oldValue

    local result, err = pcall(function()
        newValue = c.getter(oldValue)
        c.value = newValue
    end)

    if not result then
        print("Error in computed: " .. err)
    end

    reactive.setCurrentSub(prevSub)
    reactive.endTracking(c)

    return newValue ~= oldValue
end

-- Updates a signal or computed value and returns whether the value changed
-- @param signal: Signal or Computed object
-- @return: Boolean indicating whether the value changed
function reactive.update(signal)
    if signal.getter then
        -- For computed values, use the specialized update function
        return reactive.updateComputed(signal)
    end

    -- For signals, update directly
    return reactive.updateSignal(signal, signal.value)
end

--[[
 * Called when a node is no longer being watched by any subscribers
 * 当节点不再被任何订阅者监视时调用
 *
 * Cleans up the node's dependencies and performs necessary cleanup operations.
 * 清理节点的依赖并执行必要的清理操作。
 *
 * @param node: Signal, Computed, Effect, or EffectScope object / 信号、计算值、副作用或副作用作用域对象
 *
 * Different node types require different cleanup strategies:
 * - Computed values: Remove all dependencies and mark as dirty for potential recomputation
 * - Effects/Scopes: Perform complete cleanup to prevent memory leaks
 *
 * 不同的节点类型需要不同的清理策略：
 * - 计算值：移除所有依赖并标记为脏以便潜在的重新计算
 * - 副作用/作用域：执行完整清理以防止内存泄漏
]]
function reactive.unwatched(node)
    if node.getter then
        -- For computed values, clean up dependencies and mark as dirty
        -- 对于计算值，清理依赖并标记为脏
        local toRemove = node.deps
        if toRemove then
            -- 17: Mutable | Dirty
            node.flags = 17
        end

        -- Unlink all dependencies
        -- 取消所有依赖的链接
        repeat
            toRemove = reactive.unlink(toRemove, node)
        until not toRemove
    elseif not node.previousValue then
        -- For effects and effect scopes, clean up
        -- 对于副作用和副作用作用域，进行清理
        reactive.effectOper(node)
    end
end

--[[
 * Queues an effect for execution or propagates notification to parent effects
 * 将副作用排队执行或将通知传播到父副作用
 *
 * @param e: Effect or EffectScope object to notify / 要通知的副作用或副作用作用域对象
 *
 * This function implements a hierarchical notification system where child effects
 * can notify parent effects instead of being queued directly. This enables
 * effect scopes and nested effects to work correctly.
 *
 * 该函数实现了分层通知系统，其中子副作用可以通知父副作用而不是直接排队。
 * 这使得副作用作用域和嵌套副作用能够正确工作。
]]
function reactive.notify(e)
    local flags = e.flags
    if bit.band(flags, EffectFlags.Queued) == 0 then
        -- Mark as queued to prevent duplicate notifications
        -- 标记为已排队以防止重复通知
        e.flags = bit.bor(flags, EffectFlags.Queued)

        local subs = e.subs
        if subs then
            -- If this effect has parent effects, notify the parent instead
            -- 如果此副作用有父副作用，则通知父副作用
            reactive.notify(subs.sub)
        else
            -- Otherwise, add to the queue for execution
            -- 否则，添加到队列中执行
            g_queuedEffectsLength = g_queuedEffectsLength + 1
            g_queuedEffects[g_queuedEffectsLength] = e
        end
    end
end

--[[
 * ================== Signal Implementation ==================
 * ================== 信号实现 ==================
]]

--[[
 * Signal operator function - handles both get and set operations
 * 信号操作函数 - 处理获取和设置操作
 *
 * @param this: Signal object / 信号对象
 * @param newValue: New value (for set operation) or nil (for get operation) / 新值（用于设置操作）或 nil（用于获取操作）
 * @return: Current value (for get operation) or nil (for set operation) / 当前值（用于获取操作）或 nil（用于设置操作）
 *
 * This function implements the dual behavior of signals:
 * - When called with a value: acts as a setter, updates the signal and notifies subscribers
 * - When called without arguments: acts as a getter, returns current value and registers dependency
 *
 * 该函数实现了信号的双重行为：
 * - 当使用值调用时：作为设置器，更新信号并通知订阅者
 * - 当不带参数调用时：作为获取器，返回当前值并注册依赖
]]
local function signalOper(this, newValue)
    if newValue ~= nil then
        -- Set operation (when called with a value)
        -- 设置操作（当使用值调用时）
        if newValue ~= this.value then
            this.value = newValue
            this.flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty)

            -- Notify subscribers if any
            -- 如果有订阅者则通知它们
            local subs = this.subs
            if subs then
                reactive.propagate(subs)
                -- If not in batch mode, execute effects immediately
                -- 如果不在批量模式下，立即执行副作用
                if g_batchDepth == 0 then
                    reactive.flush()
                end
            end
        end
    else
        -- Get operation (when called without arguments)
        -- 获取操作（当不带参数调用时）
        local value = this.value
        -- Check if the signal needs to be updated (for signals within effects)
        -- 检查信号是否需要更新（对于副作用中的信号）
        if bit.band(this.flags, ReactiveFlags.Dirty) > 0 then
            if reactive.updateSignal(this, value) then
                local subs = this.subs
                if subs then
                    reactive.shallowPropagate(subs)
                end
            end
        end

        -- Register this signal as a dependency of the current subscriber, if any
        -- 如果有当前订阅者，将此信号注册为其依赖
        if g_activeSub then
            reactive.link(this, g_activeSub)
        end

        return value
    end
end

--[[
 * Creates a new reactive signal
 * 创建新的响应式信号
 *
 * @param initialValue: Initial value for the signal / 信号的初始值
 * @return: A function that can be called to get or set the signal's value / 可以调用以获取或设置信号值的函数
 *
 * Signals are the fundamental building blocks of the reactive system. They store
 * mutable values and automatically notify subscribers when changed. The returned
 * function can be used in two ways:
 * - signal() - returns the current value and registers as dependency
 * - signal(newValue) - sets a new value and triggers updates
 *
 * 信号是响应式系统的基本构建块。它们存储可变值并在更改时自动通知订阅者。
 * 返回的函数可以通过两种方式使用：
 * - signal() - 返回当前值并注册为依赖
 * - signal(newValue) - 设置新值并触发更新
]]
local function signal(initialValue)
    local s = {
        previousValue = initialValue, -- For change detection / 用于变更检测
        value = initialValue,         -- Current value / 当前值
        subs = nil,                   -- Linked list of subscribers (head) / 订阅者链表（头部）
        subsTail = nil,               -- Linked list of subscribers (tail) / 订阅者链表（尾部）
        flags = ReactiveFlags.Mutable, -- State flags / 状态标志
    }

    -- Return a bound function that can be called as signal() or signal(newValue)
    -- 返回一个绑定函数，可以作为 signal() 或 signal(newValue) 调用
    return bind(signalOper, s)
end

--[[
 * ================== Computed Implementation ==================
 * ================== 计算值实现 ==================
]]

--[[
 * Computed operator function - evaluates the computed value when accessed
 * 计算值操作函数 - 在访问时评估计算值
 *
 * @param this: Computed object / 计算值对象
 * @return: Current computed value / 当前计算值
 *
 * Computed values are lazy - they only recalculate when accessed and when their
 * dependencies have changed. This function implements the caching and dependency
 * checking logic that makes computed values efficient.
 *
 * 计算值是惰性的 - 它们只在被访问且依赖发生变化时重新计算。
 * 该函数实现了使计算值高效的缓存和依赖检查逻辑。
]]
local function computedOper(this)
    local flags = this.flags
    local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
    local maybeDirty = bit.band(flags, ReactiveFlags.Pending) > 0

    -- Recalculate value if it's dirty or possibly dirty (needs checking)
    -- 如果是脏的或可能是脏的（需要检查），则重新计算值
    if isDirty or (maybeDirty and reactive.checkDirty(this.deps, this)) then
        if reactive.updateComputed(this) then
            -- Notify subscribers if value changed
            -- 如果值发生变化，通知订阅者
            local subs = this.subs
            if subs then
                reactive.shallowPropagate(subs)
            end
        end
    elseif bit.band(flags, ReactiveFlags.Pending) > 0 then
        -- Clear pending flag if we determined it's not dirty
        -- 如果我们确定它不是脏的，清除待定标志
        this.flags = bit.band(flags, bit.bnot(ReactiveFlags.Pending))
    end

    -- Register this computed as a dependency of the current subscriber or scope
    -- 将此计算值注册为当前订阅者或作用域的依赖
    if g_activeSub then
        reactive.link(this, g_activeSub)
    elseif g_activeScope then
        reactive.link(this, g_activeScope)
    end

    return this.value
end

--[[
 * Creates a new computed value
 * 创建新的计算值
 *
 * @param getter: Function that calculates the computed value / 计算计算值的函数
 * @return: A function that returns the computed value when called / 调用时返回计算值的函数
 *
 * Computed values derive their value from other reactive sources (signals or other
 * computed values). They automatically track their dependencies and only recalculate
 * when those dependencies change. This provides efficient derived state management.
 *
 * 计算值从其他响应式源（信号或其他计算值）派生其值。它们自动跟踪其依赖
 * 并仅在这些依赖发生变化时重新计算。这提供了高效的派生状态管理。
]]
local function computed(getter)
    local c = {
        value = nil,               -- Cached value / 缓存值
        subs = nil,                -- Linked list of subscribers (head) / 订阅者链表（头部）
        subsTail = nil,            -- Linked list of subscribers (tail) / 订阅者链表（尾部）
        deps = nil,                -- Dependencies linked list (head) / 依赖链表（头部）
        depsTail = nil,            -- Dependencies linked list (tail) / 依赖链表（尾部）
        flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty), -- Initially dirty / 初始为脏
        getter = getter,           -- Function to compute the value / 计算值的函数
    }

    -- Return a bound function that can be called to get the computed value
    -- 返回一个绑定函数，可以调用以获取计算值
    return bind(computedOper, c)
end


--[[
 * ================== Effect Implementation ==================
 * ================== 副作用实现 ==================
]]

--[[
 * Effect cleanup operator - stops an effect or effect scope
 * 副作用清理操作符 - 停止副作用或副作用作用域
 *
 * @param this: Effect or EffectScope object / 副作用或副作用作用域对象
 * @return: nil
 *
 * This function performs complete cleanup of an effect or effect scope:
 * 1. Removes all dependency links to prevent memory leaks
 * 2. Unlinks from parent effects/scopes if any
 * 3. Clears all state flags to mark as inactive
 *
 * 该函数执行副作用或副作用作用域的完整清理：
 * 1. 移除所有依赖链接以防止内存泄漏
 * 2. 如果有的话，从父副作用/作用域取消链接
 * 3. 清除所有状态标志以标记为非活动
]]
local function effectOper(this)
    -- Unlink all dependencies
    -- 取消所有依赖的链接
    local dep = this.deps
    while(dep) do
        dep = reactive.unlink(dep, this)
    end

    -- If this effect is a dependency for other effects, unlink it
    -- 如果此副作用是其他副作用的依赖，取消其链接
    local sub = this.subs
    if sub then
        reactive.unlink(sub)
    end

    -- Clear all state flags
    -- 清除所有状态标志
    this.flags = ReactiveFlags.None
end
reactive.effectOper = effectOper

--[[
 * Creates a reactive effect that runs immediately and re-runs when dependencies change
 * 创建响应式副作用，立即运行并在依赖变化时重新运行
 *
 * @param fn: Function to execute reactively / 要响应式执行的函数
 * @return: A cleanup function that stops the effect when called / 调用时停止副作用的清理函数
 *
 * Effects are the bridge between the reactive system and the outside world.
 * They automatically track their dependencies during execution and re-run
 * whenever those dependencies change. Effects are useful for:
 * - DOM updates
 * - API calls
 * - Logging and debugging
 * - Any side effect that should respond to state changes
 *
 * 副作用是响应式系统与外部世界之间的桥梁。
 * 它们在执行期间自动跟踪其依赖，并在这些依赖发生变化时重新运行。
 * 副作用适用于：
 * - DOM 更新
 * - API 调用
 * - 日志记录和调试
 * - 任何应该响应状态变化的副作用
]]
local function effect(fn)
    -- Create the effect object
    -- 创建副作用对象
    local e = {
        fn = fn,                    -- The effect function / 副作用函数
        subs = nil,                 -- Subscribers (if this effect is a dependency) / 订阅者（如果此副作用是依赖）
        subsTail = nil,             -- End of subscribers list / 订阅者列表的末尾
        deps = nil,                 -- Dependencies linked list (head) / 依赖链表（头部）
        depsTail = nil,             -- Dependencies linked list (tail) / 依赖链表（尾部）
        flags = ReactiveFlags.Watching, -- Mark as watching (reactive) / 标记为监视（响应式）
    }

    -- Register as child of parent effect or scope if any
    -- 如果有的话，注册为父副作用或作用域的子级
    if g_activeSub then
        reactive.link(e, g_activeSub)
    elseif g_activeScope then
        reactive.link(e, g_activeScope)
    end

    -- Run the effect for the first time, collecting dependencies
    -- 第一次运行副作用，收集依赖
    local prev = reactive.setCurrentSub(e)
    local success, err = pcall(fn)
    reactive.setCurrentSub(prev)

    if not success then
        error(err)
    end

    -- Return the cleanup function
    -- 返回清理函数
    return bind(effectOper, e)
end

--[[
 * Creates a scope that collects multiple effects and provides a single cleanup function
 * 创建收集多个副作用并提供单个清理函数的作用域
 *
 * @param fn: Function that creates effects within the scope / 在作用域内创建副作用的函数
 * @return: A cleanup function that stops all effects in the scope when called / 调用时停止作用域内所有副作用的清理函数
 *
 * Effect scopes provide a way to group related effects together for easier management.
 * When the scope is cleaned up, all effects created within it are automatically
 * cleaned up as well. This is particularly useful for:
 * - Component lifecycle management
 * - Feature modules that need cleanup
 * - Temporary reactive contexts
 *
 * 副作用作用域提供了将相关副作用分组在一起以便更容易管理的方法。
 * 当作用域被清理时，在其中创建的所有副作用也会自动清理。
 * 这对以下情况特别有用：
 * - 组件生命周期管理
 * - 需要清理的功能模块
 * - 临时响应式上下文
]]
local function effectScope(fn)
    -- Create the effect scope object
    -- 创建副作用作用域对象
    local e = {
        deps = nil,           -- Dependencies linked list (head) / 依赖链表（头部）
        depsTail = nil,       -- Dependencies linked list (tail) / 依赖链表（尾部）
        subs = nil,           -- Subscribers (child effects) / 订阅者（子副作用）
        subsTail = nil,       -- End of subscribers list / 订阅者列表的末尾
        flags = ReactiveFlags.None, -- No special flags needed / 不需要特殊标志
    }

    -- Register as child of parent scope if any
    -- 如果有的话，注册为父作用域的子级
    if g_activeScope then
        reactive.link(e, g_activeScope)
    end

    -- Set this as the current scope and execute the function
    -- 将此设置为当前作用域并执行函数
    local prevSub = reactive.setCurrentSub()
    local prevScope = reactive.setCurrentScope(e)

    local success, err = pcall(function()
        fn()
    end)

    -- Restore previous scope and subscriber
    -- 恢复之前的作用域和订阅者
    reactive.setCurrentScope(prevScope)
    reactive.setCurrentSub(prevSub)

    if not success then
        error(err)
    end

    -- Return the cleanup function for the entire scope
    -- 返回整个作用域的清理函数
    return bind(effectOper, e)
end

--[[
 * ================== Module Exports ==================
 * ================== 模块导出 ==================
 *
 * This module exports the core reactive primitives and utilities needed
 * to build reactive applications. The API is designed to be simple yet
 * powerful, providing fine-grained reactivity with automatic dependency
 * tracking and efficient update propagation.
 *
 * 该模块导出构建响应式应用程序所需的核心响应式原语和工具。
 * API 设计简单而强大，提供细粒度的响应性，具有自动依赖跟踪和高效的更新传播。
]]
return {
    -- Core reactive primitives / 核心响应式原语
    signal = signal,           -- Create a reactive signal / 创建响应式信号
    computed = computed,       -- Create a computed value / 创建计算值
    effect = effect,           -- Create a reactive effect / 创建响应式副作用
    effectScope = effectScope, -- Create an effect scope / 创建副作用作用域

    -- Batch operation utilities / 批量操作工具
    startBatch = reactive.startBatch,  -- Start batch updates / 开始批量更新
    endBatch = reactive.endBatch,      -- End batch updates and flush / 结束批量更新并刷新

    -- Advanced API (for internal or advanced usage) / 高级 API（用于内部或高级用法）
    setCurrentSub = reactive.setCurrentSub,  -- Set current subscriber / 设置当前订阅者
    pauseTracking = reactive.pauseTracking,  -- Pause dependency tracking / 暂停依赖跟踪
    resumeTracking = reactive.resumeTracking, -- Resume dependency tracking / 恢复依赖跟踪
}