require 'bit'
require 'global'

-- Constants
local SubscriberFlags = {
    None = 0,
    Tracking = 1,
    CanPropagate = 2,
    RunInnerEffects = 4,
    ToCheckDirty = 8,
    Dirty = 16
}

-- Link class
local Link = {}
Link.__index = Link

function Link.new(dep, sub, nextDep)
    local self = setmetatable({}, Link)
    self.dep = dep
    self.sub = sub
    self.version = 0
    self.prevSub = nil
    self.nextSub = nil
    self.nextDep = nextDep
    return self
end

-- 从链接池中获取或创建新链接
local function getOrCreateLink(dep, sub, nextDep)
    if global.linkPool then
        local link = global.linkPool
        global.linkPool = link.nextDep
        link.nextDep = nextDep
        link.dep = dep
        link.sub = sub
        return link
    end
    return Link.new(dep, sub, nextDep)
end

-- 更新订阅者的依赖链接
local function updateSubscriberDeps(sub, newLink, depsTail)
    if not depsTail then
        sub.deps = newLink
    else
        depsTail.nextDep = newLink
    end
    sub.depsTail = newLink
end

-- 更新依赖的订阅者链接
local function updateDependencySubs(dep, newLink)
    if not dep.subs then
        dep.subs = newLink
    else
        local oldTail = dep.subsTail
        newLink.prevSub = oldTail
        oldTail.nextSub = newLink
    end
    dep.subsTail = newLink
end

-- 创建新的依赖链接
local function linkNewDep(dep, sub, nextDep, depsTail)
    local newLink = getOrCreateLink(dep, sub, nextDep)
    updateSubscriberDeps(sub, newLink, depsTail)
    updateDependencySubs(dep, newLink)
    return newLink
end

-- 查找或创建依赖链接
local function findOrCreateLink(dep, sub)
    local currentDep = sub.depsTail
    local nextDep = sub.deps

    if currentDep then
        nextDep = currentDep.nextDep
    end

    if nextDep and nextDep.dep == dep then
        sub.depsTail = nextDep
        return nextDep
    end

    return linkNewDep(dep, sub, nextDep, currentDep)
end

-- 检查链接是否有效
local function isValidLink(subLink, sub)
    local depsTail = sub.depsTail
    if not depsTail then
        return false
    end

    -- 使用 for 循环替代 repeat，更清晰
    for link = sub.deps, depsTail, link.nextDep do
        if link == subLink then
            return true
        end
        if link == depsTail then
            break
        end
    end

    return false
end

-- 更新子订阅者的链接
local function updateSubsLinks(subSubs, subs)
    if subSubs.nextSub then
        subSubs.prevSub = subs
        return subSubs, subSubs, true
    end
    return subSubs, subSubs, false
end

-- 确定目标标志
local function determineTargetFlag(sub, needsStack)
    if needsStack then
        return SubscriberFlags.ToCheckDirty
    end
    if sub.notify then
        return SubscriberFlags.RunInnerEffects
    end
    return SubscriberFlags.ToCheckDirty
end

-- 检查子订阅者并更新状态
local function checkSubs(sub, link, subs, stack, targetFlag)
    local subSubs = sub.subs
    if not subSubs then
        return stack, targetFlag, link
    end

    -- 更新链接并确定是否需要增加栈深度
    local newSubs, newLink, needsStack = updateSubsLinks(subSubs, subs)
    if needsStack then
        stack = stack + 1
        subs = newSubs
    end

    -- 确定新的目标标志
    targetFlag = determineTargetFlag(sub, needsStack)

    return stack, targetFlag, newLink
end

-- 检查订阅者是否可以传播更新
local function canPropagate(subFlags)
    if bit.rshift(subFlags, 2) == 0 then
        return true
    end
    return bit.band(subFlags, SubscriberFlags.CanPropagate) > 0
end

-- 更新订阅者的标志
local function updateSubscriberFlags(sub, targetFlag, isCanPropagate)
    if isCanPropagate then
        sub.flags = bit.band(sub.flags, bit.bnot(SubscriberFlags.CanPropagate))
    end
    sub.flags = bit.bor(sub.flags, targetFlag)
end

-- 处理副作用队列
local function handleEffectQueue(sub)
    if not sub.notify then return end
    if global.queuedEffectsTail then
        global.queuedEffectsTail.nextNotify = sub
    else
        global.queuedEffects = sub
    end
    global.queuedEffectsTail = sub
end

-- 处理子订阅者并检查返回条件
local function handleSubsAndCheck(sub, stack, targetFlag, link, subs)
    stack, targetFlag, link = checkSubs(sub, link, subs, stack, targetFlag)
    return stack, targetFlag, link, sub.subs ~= nil
end

-- 更新目标标志
local function updateTargetFlag(stack, link, subs)
    if link ~= subs then
        if stack > 0 then
            return SubscriberFlags.ToCheckDirty
        end
        return SubscriberFlags.Dirty
    end
    return nil
end

-- 获取下一个订阅者
local function getNextSubscriber(subs)
    return subs.nextSub
end

-- 更新订阅者状态
local function updateSubscriberState(nextSub, stack, link, subs)
    -- 更新目标标志
    local newFlag = updateTargetFlag(stack, link, subs)
    
    -- 更新订阅者和链接
    subs = nextSub
    link = nextSub
    
    return subs, link, newFlag
end

-- 处理依赖栈
local function processDependencyStack(stack, dep)
    stack = stack - 1
    local depSubs = dep.subs
    local prevLink = depSubs.prevSub
    depSubs.prevSub = nil
    local subs = prevLink.nextSub
    local link = subs

    if subs then
        local targetFlag = SubscriberFlags.Dirty
        if stack > 0 then
            targetFlag = SubscriberFlags.ToCheckDirty
        end
        return stack, targetFlag, link, subs, prevLink.dep, true
    end

    return stack, nil, link, subs, prevLink.dep, false
end

-- 处理非跟踪状态的订阅者
local function processNonTrackingSubscriber(sub, targetFlag, link, subs, stack)
    local isCanPropagate = canPropagate(sub.flags)
    if isCanPropagate then
        updateSubscriberFlags(sub, targetFlag, isCanPropagate)

        -- 检查子订阅者
        local newStack, newFlag, newLink, shouldReturn = handleSubsAndCheck(sub, stack, targetFlag, link, subs)
        if shouldReturn then
            return newStack, newFlag, newLink, true
        end

        -- 处理副作用队列
        handleEffectQueue(sub)
        return newStack, newFlag, newLink, false
    end

    -- 如果不能传播但需要标记为脏
    if bit.band(sub.flags, targetFlag) == 0 then
        updateSubscriberFlags(sub, targetFlag, false)
    end
    return stack, targetFlag, link, false
end

-- 处理跟踪状态的订阅者
local function processTrackingSubscriber(sub, targetFlag, link, subs, stack)
    if not isValidLink(link, sub) then
        return stack, targetFlag, link, false
    end

    if bit.rshift(sub.flags, 2) == 0 then
        updateSubscriberFlags(sub, bit.bor(targetFlag, SubscriberFlags.CanPropagate), false)
        return handleSubsAndCheck(sub, stack, targetFlag, link, subs)
    end

    -- 如果需要标记为脏
    if bit.band(sub.flags, targetFlag) == 0 then
        updateSubscriberFlags(sub, targetFlag, false)
    end
    
    return stack, targetFlag, link, false
end

-- 处理单个订阅者
local function processSubscriber(sub, targetFlag, link, subs, stack)
    -- 根据订阅者的跟踪状态选择处理函数
    if bit.band(sub.flags, SubscriberFlags.Tracking) == 0 then
        return processNonTrackingSubscriber(sub, targetFlag, link, subs, stack)
    else
        return processTrackingSubscriber(sub, targetFlag, link, subs, stack)
    end
end

-- 处理订阅者迭代
local function processSubscriberIteration(sub, stack, targetFlag, link, subs)
    local shouldReturn
    stack, targetFlag, link, shouldReturn = processSubscriber(sub, targetFlag, link, subs, stack)
    if shouldReturn then
        return stack, targetFlag, link, subs, false
    end

    local nextSub = getNextSubscriber(subs)
    if not nextSub then
        if stack > 0 then
            local dep = subs.dep
            repeat
                local newStack, newFlag, newLink, newSubs, newDep, shouldReturn = processDependencyStack(stack, dep)
                stack = newStack
                link = newLink
                subs = newSubs
                dep = newDep

                if shouldReturn then
                    targetFlag = newFlag
                    return stack, targetFlag, link, subs, false
                end
            until stack <= 0
        end
        return stack, targetFlag, link, subs, true
    end

    local newSubs, newLink, newFlag = updateSubscriberState(nextSub, stack, link, subs)
    if newFlag then
        targetFlag = newFlag
    end

    return stack, targetFlag, newLink, newSubs, false
end

local function propagate(subs)
    local targetFlag = SubscriberFlags.Dirty
    local link = subs
    local stack = 0

    repeat
        local shouldBreak = false
        local sub = link.sub
        stack, targetFlag, link, subs, shouldBreak = processSubscriberIteration(sub, stack, targetFlag, link, subs)

        if shouldBreak then break end
    until false

    if global.batchDepth <= 0 then
        global.drainQueuedEffects()
    end
end

local function checkDependencyUpdate(dep, deps)
    if not dep.update then
        return false
    end

    if dep.version ~= deps.version then
        return true
    end

    local depFlags = dep.flags
    if bit.band(depFlags, SubscriberFlags.Dirty) > 0 then
        return dep:update()
    end

    if bit.band(depFlags, SubscriberFlags.ToCheckDirty) > 0 then
        return nil, true
    end

    return false
end

local function processSubscriberUpdate(sub, prevLink, dirty)
    if dirty then
        if sub.update() then
            return prevLink.sub, true
        end
    else
        sub.flags = bit.band(sub.flags, bit.bnot(SubscriberFlags.ToCheckDirty))
    end
    return sub, false
end

local function processDependencyStack(stack, deps, sub, dirty)
    local gototop = false
    global.do_func(function()
        stack = stack - 1
        local subSubs = sub.subs
        local prevLink = subSubs.prevSub
        subSubs.prevSub = nil

        sub, dirty = processSubscriberUpdate(sub, prevLink, dirty)

        deps = prevLink.nextDep
        if deps then
            gototop = true
            return
        end

        sub = prevLink.sub
        dirty = false
    end)
    return stack, deps, sub, dirty, gototop
end

local function processStackedDependencies(stack, deps, sub, dirty)
    repeat
        local newStack, newDeps, newSub, newDirty, shouldBreak = processDependencyStack(stack, deps, sub, dirty)
        stack = newStack
        deps = newDeps
        sub = newSub
        dirty = newDirty

        if shouldBreak then
            return stack, deps, sub, dirty, true
        end
    until stack <= 0

    return stack, deps, sub, dirty, false
end

local function processDependencyCheck(deps, stack)
    local dirty = false
    local nextDep = nil
    local shouldReturn = false
    local shouldGotoTop = false

    global.do_func(function()
        local dep = deps.dep
        local isDirty, needsCheck = checkDependencyUpdate(dep, deps)

        if needsCheck then
            dep.subs.prevSub = deps
            deps = dep.deps
            stack = stack + 1
            shouldReturn = true
            return
        end

        dirty = isDirty
        if not dirty then
            nextDep = deps.nextDep
        end

        if dirty or not nextDep then
            if stack > 0 then
                local sub = deps.sub
                stack, deps, sub, dirty, shouldGotoTop = processStackedDependencies(stack, deps, sub, dirty)
                if shouldGotoTop then
                    shouldReturn = true
                    return
                end
            end

            shouldReturn = true
            return
        end

        deps = nextDep
    end)

    return deps, stack, dirty, shouldReturn, shouldGotoTop
end

local function checkDirty(deps)
    local stack = 0
    local dirty = false

    while deps do
        local newDeps, newStack, isDirty, shouldReturn, shouldGotoTop = processDependencyCheck(deps, stack)

        deps = newDeps
        stack = newStack

        if shouldReturn then
            if not shouldGotoTop then
                return isDirty
            end
        end

        dirty = isDirty or dirty
    end

    return dirty
end

local function updateSubscriberLinks(link, nextSub, prevSub, dep)
    if nextSub then
        nextSub.prevSub = prevSub
        link.nextSub = nil
    else
        dep.subsTail = prevSub
        if dep.lastTrackedId then
            dep.lastTrackedId = 0
        end
    end

    if prevSub then
        prevSub.nextSub = nextSub
        link.prevSub = nil
    else
        dep.subs = nextSub
    end
end

local function recycleLinkToPool(link)
    link.dep = nil
    link.sub = nil
    link.nextDep = global.linkPool
    global.linkPool = link
end

local function cleanupDependency(dep, depDeps, nextDep)
    if not dep.subs and dep.deps then
        if dep.notify then
            dep.flags = SubscriberFlags.None
        else
            dep.flags = bit.bor(dep.flags, SubscriberFlags.Dirty)
        end

        if depDeps then
            dep.depsTail.nextDep = nextDep
            dep.deps = nil
            dep.depsTail = nil
            return depDeps
        end
    end
    return nextDep
end

local function clearTrack(link)
    while link do
        local nextLink = nil
        global.do_func(function()
            local dep = link.dep
            local nextDep = link.nextDep
            local nextSub = link.nextSub
            local prevSub = link.prevSub

            updateSubscriberLinks(link, nextSub, prevSub, dep)

            recycleLinkToPool(link)

            nextLink = cleanupDependency(dep, dep.deps, nextDep)
            if not nextLink then
                nextLink = nextDep
            end
        end)
        link = nextLink
    end
end

local function cleanupSubscriberDeps(sub)
    local depsTail = sub.depsTail
    if depsTail then
        if depsTail.nextDep then
            clearTrack(depsTail.nextDep)
            depsTail.nextDep = nil
        end
    elseif sub.deps then
        clearTrack(sub.deps)
        sub.deps = nil
    end
end

local function startTrack(sub)
    sub.depsTail = nil
    sub.flags = SubscriberFlags.Tracking
end

local function endTrack(sub)
    cleanupSubscriberDeps(sub)
    sub.flags = bit.band(sub.flags, bit.bnot(SubscriberFlags.Tracking))
end

return {
	SubscriberFlags = SubscriberFlags,
	link = findOrCreateLink,
    Link = Link,

    propagate = propagate,
	checkDirty = checkDirty,
    startTrack = startTrack,
    endTrack = endTrack,
}
