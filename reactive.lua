require("bit")
require("utils")

local reactive = {}

local ReactiveFlags = {
    None = 0,
    Mutable = 1,
    Watching = 2,
    RecursedCheck = 4,
    Recursed = 8,
    Dirty = 16,
    Pending = 32,
}

local EffectFlags = {
    Queued = 64, -- 1 << 6
}

local g_activeSub = nil
local g_activeScope = nil

local g_pauseStack = {}
local g_queuedEffects = {}
local g_queuedEffectsLength = 0

local g_batchDepth = 0
local g_notifyIndex = 0

function reactive.setCurrentSub(sub)
    local prevSub = g_activeSub
    g_activeSub = sub
    return prevSub
end

function reactive.setCurrentScope(scope)
    local prevScope = g_activeScope
    g_activeScope = scope
    return prevScope
end

function reactive.startBatch()
    g_batchDepth = g_batchDepth + 1
end

function reactive.endBatch()
    g_batchDepth = g_batchDepth - 1
    if 0 == g_batchDepth then
        reactive.flush()
    end
end

function reactive.pauseTracking()
    g_pauseStack[#g_pauseStack + 1] = reactive.setCurrentSub()
end

function reactive.resumeTracking()
    local top = table.remove(g_pauseStack, #g_pauseStack)
    reactive.setCurrentSub(top)
end

function reactive.flush()
    while g_notifyIndex < g_queuedEffectsLength do
        local effect = g_queuedEffects[g_notifyIndex+1]
        g_queuedEffects[g_notifyIndex+1] = nil
        g_notifyIndex = g_notifyIndex + 1

        if effect then
            effect.flags = bit.band(effect.flags, bit.bnot(EffectFlags.Queued))
            reactive.run(effect, effect.flags)
        end
    end

    g_notifyIndex = 0
    g_queuedEffectsLength = 0
end

function reactive.run(e, flags)
    local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
    local isPending = bit.band(flags, ReactiveFlags.Pending) > 0

    if isDirty or (isPending and reactive.checkDirty(e.deps, e)) then
        local prev = reactive.setCurrentSub(e)
        reactive.startTracking(e)

        local result, err = pcall(e.fn)
        if not result then
            print("Error in effect: " .. err)
        end

        reactive.setCurrentSub(prev)
        reactive.endTracking(e)

        return
    end

    if isPending then
        e.flags = bit.band(flags, bit.bnot(ReactiveFlags.Pending))
    end

    local link = e.deps
    while link do
        local dep = link.dep
        local depFlags = dep.flags

        if bit.band(depFlags, EffectFlags.Queued) > 0 then
            dep.flags = bit.band(depFlags, bit.bnot(EffectFlags.Queued))
            reactive.run(dep, dep.flags)
        end

        link = link.nextDep
    end
end

function reactive.createLink(dep, sub, prevSub, nextSub, prevDep, nextDep)
    return {
        dep = dep,
        sub = sub,
        prevSub = prevSub,
        nextSub = nextSub,
        prevDep = prevDep,
        nextDep = nextDep
    }
end

function reactive.link(dep, sub)
    local prevDep = sub.depsTail
    if prevDep and prevDep.dep == dep then
        return
    end

    local nextDep = nil

    local recursedCheck = bit.band(sub.flags, ReactiveFlags.RecursedCheck)
    if recursedCheck > 0 then
        if prevDep then
            nextDep = prevDep.nextDep
        else
            nextDep = sub.deps
        end

        if nextDep and nextDep.dep == dep then
            sub.depsTail = nextDep
            return
        end
    end

    local prevSub = dep.subsTail
    if prevSub and prevSub.sub == sub and (recursedCheck == 0 or reactive.isValidLink(prevSub, sub)) then
        return
    end

    local newLink = reactive.createLink(dep, sub, prevDep, nextDep, prevSub)
    dep.subsTail = newLink
    sub.depsTail = newLink

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

function reactive.unlink(link, sub)
    sub = sub or link.sub

    local dep = link.dep
    local prevDep = link.prevDep
    local nextDep = link.nextDep
    local nextSub = link.nextSub
    local prevSub = link.prevSub


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

    if nextSub then
        nextSub.prevSub = prevSub
    else
        dep.subsTail = prevSub
    end

    if prevSub then
        prevSub.nextSub = nextSub
    else
        dep.subs = nextSub

        if not nextSub  then
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

function reactive.startTracking(sub)
    sub.depsTail = nil

    -- 56: Recursed | Dirty | Pending  4: RecursedCheck
    sub.flags = bit.bor(bit.band(sub.flags, bit.bnot(56)), 4)
end

function reactive.endTracking(sub)
    local depsTail = sub.depsTail
    local toRemove = sub.deps
    if depsTail then
        toRemove = depsTail.nextDep
    end

    while toRemove do
        toRemove = reactive.unlink(toRemove, sub)
    end

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

-- @param signal: Signal | Computed
function reactive.update(signal)
    if signal.getter then
        return reactive.updateComputed(signal)
    end

    return reactive.updateSignal(signal, signal.value)
end

-- @param node: Signal, Computed, Effect, EffectScope
function reactive.unwatched(node)
    if node.getter then
        local toRemove = node.deps
        if toRemove then
            -- 17: Mutable | Dirty
            node.flags = 17
        end

        repeat
            toRemove = reactive.unlink(toRemove, node)
        until not toRemove
    elseif not node.previousValue then
        reactive.effectOper(node)
    end
end

-- @param e: Effect | EffectScope
function reactive.notify(e)
    local flags = e.flags
    if bit.band(flags, EffectFlags.Queued) == 0 then
        e.flags = bit.bor(flags, EffectFlags.Queued)

        local subs = e.subs
        if subs then
            reactive.notify(subs.sub)
        else
            g_queuedEffectsLength = g_queuedEffectsLength + 1
            g_queuedEffects[g_queuedEffectsLength] = e
        end
    end
end

------------------  Signal ------------------
local function signalOper(this, newValue)
    if newValue then
        if newValue ~= this.value then
            this.value = newValue
            this.flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty)

            local subs = this.subs
            if subs then
                reactive.propagate(subs)
                if g_batchDepth == 0 then
                    reactive.flush()
                end
            end
        end
    else
        local value = this.value
        if bit.band(this.flags, ReactiveFlags.Dirty) > 0 then
            if reactive.updateSignal(this, value) then
                local subs = this.subs
                if subs then
                    reactive.shallowPropagate(subs)
                end
            end
        end

        if g_activeSub then
            reactive.link(this, g_activeSub)
        end

        return value
    end
end

-- 创建信号对象
local function signal(initialValue)
    local s = {
        previousValue = initialValue,
        value = initialValue,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.Mutable,
    }

    return utils.bind(signalOper, s)
end


------------------------  Computed ------------------
local function computedOper(this)
    local flags = this.flags
    local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
    local maybeDirty = bit.band(flags, ReactiveFlags.Pending) > 0

    if isDirty or (maybeDirty and reactive.checkDirty(this.deps, this)) then
        if reactive.updateComputed(this) then
            local subs = this.subs
            if subs then
                reactive.shallowPropagate(subs)
            end
        end
    elseif bit.band(flags, ReactiveFlags.Pending) > 0 then
        this.flags = bit.band(flags, bit.bnot(ReactiveFlags.Pending))
    end

    if g_activeSub then
        reactive.link(this, g_activeSub)
    elseif g_activeScope then
        reactive.link(this, g_activeScope)
    end

    return this.value
end

local function computed(getter)
    local c = {
        value = nil,
        subs = nil,
        subsTail = nil,
        deps = nil,
        depsTail = nil,
        flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty),
        getter = getter,
    }

    return utils.bind(computedOper, c)
end


-------------------------  Effect ------------------
-- @param this: Effect | EffectScope
local function effectOper(this)
    local dep = this.deps

    while(dep) do
        dep = reactive.unlink(dep, this)
    end

    local sub = this.subs
    if sub then
        reactive.unlink(sub)
    end

    this.flags = ReactiveFlags.None
end

local function effect(fn)
    local e = {
        fn = fn,
        subs = nil,
        subsTail = nil,
        deps = nil,
        depsTail = nil,
        flags = ReactiveFlags.Watching,
    }

    if g_activeSub then
        reactive.link(e, g_activeSub)
    elseif g_activeScope then
        reactive.link(e, g_activeScope)
    end

    local prev = reactive.setCurrentSub(e)
    local success, err = pcall(fn)
    reactive.setCurrentSub(prev)

    if not success then
        error(err)
    end

    return utils.bind(effectOper, e)
end

local function effectScope(fn)
    local e = {
        deps = nil,
        depsTail = nil,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.None,
    }

    if g_activeScope then
        reactive.link(e, g_activeScope)
    end

    local prevSub = reactive.setCurrentSub()
    local prevScope = reactive.setCurrentScope(e)

    local success, err = pcall(function()
        fn()
    end)

    if not success then
        error(err)
    end

    reactive.setCurrentScope(prevScope)
    reactive.setCurrentSub(prevSub)

    return utils.bind(effectOper, e)
end

return {
    signal = signal,
    computed = computed,
    effect = effect,
    effectScope = effectScope,
    startBatch = reactive.startBatch,
    endBatch = reactive.endBatch,
    setCurrentSub = reactive.setCurrentSub,
}