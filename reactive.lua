--[[
 * Alien Signals - A reactive programming system for Lua
 * Derived from https://github.com/stackblitz/alien-signals
 * 
 * This module implements a full-featured reactivity system with automatic
 * dependency tracking and efficient updates propagation.
]]

local bit = require("bit")
local utils = require("utils")

local reactive = {}

-- Bit flags used to track the state of reactive objects
local ReactiveFlags = {
    None = 0,          -- Default state
    Mutable = 1,       -- Can be changed (signals and computed values)
    Watching = 2,      -- Actively watching for changes (effects)
    RecursedCheck = 4, -- Being checked for circular dependencies
    Recursed = 8,      -- Has been visited during recursion check
    Dirty = 16,        -- Value has changed and needs update
    Pending = 32,      -- Might be dirty, needs checking
}

local EffectFlags = {
    Queued = 64,       -- Effect is queued for execution (1 << 6)
}

-- Global state for tracking current active subscriber and scope
local g_activeSub = nil    -- Current active effect or computed value
local g_activeScope = nil  -- Current active effect scope

-- Stack for pausing and resuming tracking
local g_pauseStack = {}

-- Queue for batched effect execution
local g_queuedEffects = {}       -- Effects waiting to be executed
local g_queuedEffectsLength = 0  -- Length of the queue

-- Batch update state
local g_batchDepth = 0    -- Depth of nested batch operations
local g_notifyIndex = 0   -- Current position in the effects queue

-- Sets the current subscriber (effect or computed) and returns the previous one
function reactive.setCurrentSub(sub)
    local prevSub = g_activeSub
    g_activeSub = sub
    return prevSub
end

-- Sets the current effect scope and returns the previous one
function reactive.setCurrentScope(scope)
    local prevScope = g_activeScope
    g_activeScope = scope
    return prevScope
end

-- Starts a batch update - effects won't be executed until endBatch is called
-- This is useful for multiple updates that should be treated as one
function reactive.startBatch()
    g_batchDepth = g_batchDepth + 1
end

-- Ends a batch update and flushes pending effects if this is the outermost batch
function reactive.endBatch()
    g_batchDepth = g_batchDepth - 1
    if 0 == g_batchDepth then
        reactive.flush()
    end
end

-- Temporarily pauses dependency tracking
function reactive.pauseTracking()
    g_pauseStack[#g_pauseStack + 1] = reactive.setCurrentSub()
end

-- Resumes dependency tracking after a pause
function reactive.resumeTracking()
    local top = table.remove(g_pauseStack, #g_pauseStack)
    reactive.setCurrentSub(top)
end

-- Executes all queued effects
-- This is called automatically when a batch update ends
-- or when a signal changes outside of a batch
function reactive.flush()
    while g_notifyIndex < g_queuedEffectsLength do
        local effect = g_queuedEffects[g_notifyIndex+1]
        g_queuedEffects[g_notifyIndex+1] = nil
        g_notifyIndex = g_notifyIndex + 1

        if effect then
            -- Clear the queued flag and run the effect
            effect.flags = bit.band(effect.flags, bit.bnot(EffectFlags.Queued))
            reactive.run(effect, effect.flags)
        end
    end

    -- Reset queue state after processing all effects
    g_notifyIndex = 0
    g_queuedEffectsLength = 0
end

-- Runs an effect based on its current state
-- @param e: The effect to run
-- @param flags: Current state flags of the effect
function reactive.run(e, flags)
    local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
    local isPending = bit.band(flags, ReactiveFlags.Pending) > 0

    -- If the effect is dirty or it's pending and has dirty dependencies
    if isDirty or (isPending and reactive.checkDirty(e.deps, e)) then
        -- Track effect execution to collect dependencies
        local prev = reactive.setCurrentSub(e)
        reactive.startTracking(e)

        -- Execute the effect function safely
        local result, err = pcall(e.fn)
        if not result then
            print("Error in effect: " .. err)
        end

        -- Restore previous state and finish tracking
        reactive.setCurrentSub(prev)
        reactive.endTracking(e)

        return
    end

    -- Clear pending flag if needed
    if isPending then
        e.flags = bit.band(flags, bit.bnot(ReactiveFlags.Pending))
    end

    -- Process queued dependent effects
    local link = e.deps
    while link do
        local dep = link.dep
        local depFlags = dep.flags

        -- If dependent effect is queued, run it
        if bit.band(depFlags, EffectFlags.Queued) > 0 then
            dep.flags = bit.band(depFlags, bit.bnot(EffectFlags.Queued))
            reactive.run(dep, dep.flags)
        end

        link = link.nextDep
    end
end

-- Creates a dependency link node in the doubly-linked list
-- @param dep: Dependency (signal or computed)
-- @param sub: Subscriber (effect or computed)
-- @param prevSub, nextSub: Previous and next links in the subscriber chain
-- @param prevDep, nextDep: Previous and next links in the dependency chain
function reactive.createLink(dep, sub, prevSub, nextSub, prevDep, nextDep)
    return {
        dep = dep,        -- The dependency object
        sub = sub,        -- The subscriber object
        prevSub = prevSub, -- Previous link in the subscriber's chain
        nextSub = nextSub, -- Next link in the subscriber's chain
        prevDep = prevDep, -- Previous link in the dependency's chain
        nextDep = nextDep  -- Next link in the dependency's chain
    }
end

-- Establishes a dependency relationship between a dependency (dep) and a subscriber (sub)
-- This is the core of the dependency tracking system
-- @param dep: The reactive object being depended on (signal or computed)
-- @param sub: The reactive object depending on it (effect or computed)
function reactive.link(dep, sub)
    -- Check if this dependency is already the last one in the chain
    local prevDep = sub.depsTail
    if prevDep and prevDep.dep == dep then
        return
    end

    local nextDep = nil

    -- Handle circular dependency detection
    local recursedCheck = bit.band(sub.flags, ReactiveFlags.RecursedCheck)
    if recursedCheck > 0 then
        if prevDep then
            nextDep = prevDep.nextDep
        else
            nextDep = sub.deps
        end

        -- If we already have this dependency in the chain during recursion check
        if nextDep and nextDep.dep == dep then
            sub.depsTail = nextDep
            return
        end
    end

    -- Check if the sub is already subscribed to this dependency
    local prevSub = dep.subsTail
    if prevSub and prevSub.sub == sub and (recursedCheck == 0 or reactive.isValidLink(prevSub, sub)) then
        return
    end

    -- Create a new link and insert it in both chains
    local newLink = reactive.createLink(dep, sub, prevDep, nextDep, prevSub)
    dep.subsTail = newLink  -- Add to dependency's subscribers chain
    sub.depsTail = newLink  -- Add to subscriber's dependencies chain

    -- Update next and previous pointers for proper doubly-linked list behavior
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

-- Removes a dependency link from both chains
-- @param link: The link to remove
-- @param sub: The subscriber (can be provided explicitly or taken from link)
-- @return: The next dependency link in the chain
function reactive.unlink(link, sub)
    sub = sub or link.sub

    local dep = link.dep
    local prevDep = link.prevDep
    local nextDep = link.nextDep
    local nextSub = link.nextSub
    local prevSub = link.prevSub

    -- Remove from the dependency chain (horizontal)
    if nextDep then
        nextDep.prevDep = prevDep
    else
        sub.depsTail = prevDep
    end

    if prevDep then
        prevDep.nextDep = nextDep
    else
        sub.deps = nextDep
    end

    -- Remove from the subscriber chain (vertical)
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
        if not nextSub then
            reactive.unwatched(dep)
        end
    end

    return nextDep
end

function reactive.propagate(link)
    local next = link.nextSub
    local stack = nil

    local top = true
    local gototop = false
    local bBreak = false

    while top do
        gototop = false
        utils.do_func(function()
            local sub = link.sub
            local flags = sub.flags

            --Mutable | Watching
            if bit.band(flags, 3) then
                -- 60: RecursedCheck | Recursed | Dirty | Pending
                if bit.band(flags, 60) == 0 then
                    --32: Pending
                    sub.flags = bit.bor(flags, 32)
                elseif bit.band(flags, 12) == 0 then
                    flags = ReactiveFlags.None
                elseif bit.band(flags, 4) == 0 then
                    -- 4:RecursedCheck, 8:Recursed, 32:Pending
                    sub.flags = bit.bor(bit.band(flags, bit.bnot(8)), 32)
                elseif bit.band(flags, 48) == 0 and reactive.isValidLink(link, sub) then
                    --48:Dirty | Pending  40:Recursed | Pending
                    sub.flags = bit.bor(flags, 40)
                    flags = bit.band(flags, ReactiveFlags.Mutable)
                else
                    flags = ReactiveFlags.None
                end

                if bit.band(flags, ReactiveFlags.Watching) > 0 then
                    reactive.notify(sub)
                end

                if bit.band(flags, ReactiveFlags.Mutable) > 0 then
                    local subSubs = sub.subs
                    if subSubs then
                        link = subSubs
                        if subSubs.nextSub then
                            stack = {value = next, prev = stack}
                            next = link.nextSub
                        end
                        return
                    end
                end
            end

            link = next
            if link then
                next = link.nextSub
                return
            end

            while stack do
                link = stack.value
                stack = stack.prev

                if link then
                    next = link.nextSub
                    gototop = true
                    return
                end
            end

            bBreak = true
        end)

        if not gototop and bBreak then
            break
        end
    end
end

-- Begins dependency tracking for a subscriber
-- Called when an effect or computed value is about to execute its function
-- @param sub: The subscriber (effect or computed)
function reactive.startTracking(sub)
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

function reactive.checkDirty(link, sub)
    local stack = nil
    local checkDepth = 0

    local top = true
    local gototop = false
    local returnFlag = false
    local dirty = false

    while top do
        gototop = false

        utils.do_func(function()
            local dep = link.dep
            local depFlags = dep.flags

            dirty = false
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
                return
            end

            if not dirty and link.nextDep then
                link = link.nextDep
                return
            end

            while checkDepth > 0 do
                utils.do_func(function()
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
                            return
                        end
                    else
                        sub.flags = bit.band(sub.flags, bit.bnot(ReactiveFlags.Pending))
                    end

                    sub = link.sub
                    if link.nextDep then
                        link = link.nextDep
                        gototop = true
                        return
                    end
                    dirty = false
                end)

                if gototop then
                    break
                end
            end

            if not gototop and checkDepth <= 0 then
                returnFlag = true
            end
        end)

        if returnFlag then
            return dirty
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
    local depsTail = sub.depsTail
    if depsTail then
        local link = sub.deps
        repeat
            if link == checkLink then
                return true
            end

            if link == depsTail then
                break
            end

            link = link.depsTail
        until not link
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

-- Called when a node is no longer being watched by any subscribers
-- Cleans up the node's dependencies
-- @param node: Signal, Computed, Effect, or EffectScope object
function reactive.unwatched(node)
    if node.getter then
        -- For computed values, clean up dependencies and mark as dirty
        local toRemove = node.deps
        if toRemove then
            -- 17: Mutable | Dirty
            node.flags = 17
        end

        -- Unlink all dependencies
        repeat
            toRemove = reactive.unlink(toRemove, node)
        until not toRemove
    elseif not node.previousValue then
        -- For effects and effect scopes, clean up
        reactive.effectOper(node)
    end
end

-- Queues an effect for execution or propagates notification to parent effects
-- @param e: Effect or EffectScope object to notify
function reactive.notify(e)
    local flags = e.flags
    if bit.band(flags, EffectFlags.Queued) == 0 then
        -- Mark as queued to prevent duplicate notifications
        e.flags = bit.bor(flags, EffectFlags.Queued)

        local subs = e.subs
        if subs then
            -- If this effect has parent effects, notify the parent instead
            reactive.notify(subs.sub)
        else
            -- Otherwise, add to the queue for execution
            g_queuedEffectsLength = g_queuedEffectsLength + 1
            g_queuedEffects[g_queuedEffectsLength] = e
        end
    end
end

------------------  Signal ------------------
-- Signal operator function - handles both get and set operations
-- @param this: Signal object
-- @param newValue: New value (for set operation) or nil (for get operation)
-- @return: Current value (for get operation) or nil (for set operation)
local function signalOper(this, newValue)
    if newValue then
        -- Set operation (when called with a value)
        if newValue ~= this.value then
            this.value = newValue
            this.flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty)

            -- Notify subscribers if any
            local subs = this.subs
            if subs then
                reactive.propagate(subs)
                -- If not in batch mode, execute effects immediately
                if g_batchDepth == 0 then
                    reactive.flush()
                end
            end
        end
    else
        -- Get operation (when called without arguments)
        local value = this.value
        -- Check if the signal needs to be updated (for signals within effects)
        if bit.band(this.flags, ReactiveFlags.Dirty) > 0 then
            if reactive.updateSignal(this, value) then
                local subs = this.subs
                if subs then
                    reactive.shallowPropagate(subs)
                end
            end
        end

        -- Register this signal as a dependency of the current subscriber, if any
        if g_activeSub then
            reactive.link(this, g_activeSub)
        end

        return value
    end
end

-- Creates a new reactive signal
-- @param initialValue: Initial value for the signal
-- @return: A function that can be called to get or set the signal's value
local function signal(initialValue)
    local s = {
        previousValue = initialValue, -- For change detection
        value = initialValue,         -- Current value
        subs = nil,                   -- Linked list of subscribers (head)
        subsTail = nil,               -- Linked list of subscribers (tail)
        flags = ReactiveFlags.Mutable, -- State flags
    }

    -- Return a bound function that can be called as signal() or signal(newValue)
    return utils.bind(signalOper, s)
end


------------------------  Computed ------------------
-- Computed operator function - evaluates the computed value when accessed
-- @param this: Computed object
-- @return: Current computed value
local function computedOper(this)
    local flags = this.flags
    local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
    local maybeDirty = bit.band(flags, ReactiveFlags.Pending) > 0

    -- Recalculate value if it's dirty or possibly dirty (needs checking)
    if isDirty or (maybeDirty and reactive.checkDirty(this.deps, this)) then
        if reactive.updateComputed(this) then
            -- Notify subscribers if value changed
            local subs = this.subs
            if subs then
                reactive.shallowPropagate(subs)
            end
        end
    elseif bit.band(flags, ReactiveFlags.Pending) > 0 then
        -- Clear pending flag if we determined it's not dirty
        this.flags = bit.band(flags, bit.bnot(ReactiveFlags.Pending))
    end

    -- Register this computed as a dependency of the current subscriber or scope
    if g_activeSub then
        reactive.link(this, g_activeSub)
    elseif g_activeScope then
        reactive.link(this, g_activeScope)
    end

    return this.value
end

-- Creates a new computed value
-- @param getter: Function that calculates the computed value
-- @return: A function that returns the computed value when called
local function computed(getter)
    local c = {
        value = nil,               -- Cached value
        subs = nil,                -- Linked list of subscribers (head)
        subsTail = nil,            -- Linked list of subscribers (tail)
        deps = nil,                -- Dependencies linked list (head)
        depsTail = nil,            -- Dependencies linked list (tail)
        flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty), -- Initially dirty
        getter = getter,           -- Function to compute the value
    }

    -- Return a bound function that can be called to get the computed value
    return utils.bind(computedOper, c)
end


-------------------------  Effect ------------------
-- Effect cleanup operator - stops an effect or effect scope
-- @param this: Effect or EffectScope object
-- @return: nil
local function effectOper(this)
    -- Unlink all dependencies
    local dep = this.deps
    while(dep) do
        dep = reactive.unlink(dep, this)
    end

    -- If this effect is a dependency for other effects, unlink it
    local sub = this.subs
    if sub then
        reactive.unlink(sub)
    end

    -- Clear all state flags
    this.flags = ReactiveFlags.None
end
reactive.effectOper = effectOper

-- Creates a reactive effect that runs immediately and re-runs when dependencies change
-- @param fn: Function to execute reactively
-- @return: A cleanup function that stops the effect when called
local function effect(fn)
    -- Create the effect object
    local e = {
        fn = fn,                    -- The effect function
        subs = nil,                 -- Subscribers (if this effect is a dependency)
        subsTail = nil,             -- End of subscribers list
        deps = nil,                 -- Dependencies linked list (head)
        depsTail = nil,             -- Dependencies linked list (tail)
        flags = ReactiveFlags.Watching, -- Mark as watching (reactive)
    }

    -- Register as child of parent effect or scope if any
    if g_activeSub then
        reactive.link(e, g_activeSub)
    elseif g_activeScope then
        reactive.link(e, g_activeScope)
    end

    -- Run the effect for the first time, collecting dependencies
    local prev = reactive.setCurrentSub(e)
    local success, err = pcall(fn)
    reactive.setCurrentSub(prev)

    if not success then
        error(err)
    end

    -- Return the cleanup function
    return utils.bind(effectOper, e)
end

-- Creates a scope that collects multiple effects and provides a single cleanup function
-- @param fn: Function that creates effects within the scope
-- @return: A cleanup function that stops all effects in the scope when called
local function effectScope(fn)
    -- Create the effect scope object
    local e = {
        deps = nil,           -- Dependencies linked list (head)
        depsTail = nil,       -- Dependencies linked list (tail)
        subs = nil,           -- Subscribers (child effects)
        subsTail = nil,       -- End of subscribers list
        flags = ReactiveFlags.None, -- No special flags needed
    }

    -- Register as child of parent scope if any
    if g_activeScope then
        reactive.link(e, g_activeScope)
    end

    -- Set this as the current scope and execute the function
    local prevSub = reactive.setCurrentSub()
    local prevScope = reactive.setCurrentScope(e)

    local success, err = pcall(function()
        fn()
    end)

    -- Restore previous scope and subscriber
    reactive.setCurrentScope(prevScope)
    reactive.setCurrentSub(prevSub)

    if not success then
        error(err)
    end

    -- Return the cleanup function for the entire scope
    return utils.bind(effectOper, e)
end

-- Module exports
return {
    -- Core reactive primitives
    signal = signal,           -- Create a reactive signal
    computed = computed,       -- Create a computed value
    effect = effect,           -- Create a reactive effect
    effectScope = effectScope, -- Create an effect scope

    -- Batch operation utilities
    startBatch = reactive.startBatch,  -- Start batch updates
    endBatch = reactive.endBatch,      -- End batch updates and flush

    -- Advanced API (for internal or advanced usage)
    setCurrentSub = reactive.setCurrentSub,  -- Set current subscriber
}