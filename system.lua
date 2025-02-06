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

local function linkNewDep(dep, sub, nextDep, depsTail)
    local newLink

    if global.linkPool then
        newLink = global.linkPool
        global.linkPool = newLink.nextDep
        newLink.nextDep = nextDep
        newLink.dep = dep
        newLink.sub = sub
    else
        newLink = Link.new(dep, sub, nextDep)
    end

    if not depsTail then
        sub.deps = newLink
    else
        depsTail.nextDep = newLink
    end

    if not dep.subs then
        dep.subs = newLink
    else
        local oldTail = dep.subsTail
        newLink.prevSub = oldTail
        oldTail.nextSub = newLink
    end

    sub.depsTail = newLink
    dep.subsTail = newLink

    return newLink
end

local function _link(dep, sub)
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

local function isValidLink(subLink, sub)
    local depsTail = sub.depsTail
    if not depsTail then
        return false
    end

    local link = sub.deps
    repeat
        if link == subLink then
            return true
        end

        if link == depsTail then
            break
        end

        link = link.nextDep
    until not link

    return false
end

local function checkSubs(sub, link, subs, stack, targetFlag)
	local subSubs = sub.subs
	if subSubs then
		targetFlag = SubscriberFlags.ToCheckDirty
		if subSubs.nextSub then
			subSubs.prevSub = subs
			subs = subSubs
			link = subs
			stack = stack + 1
		else
			link = subSubs
			if sub.notify then
				targetFlag = SubscriberFlags.RunInnerEffects
			end
		end
	end

	return stack, targetFlag, link
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

-- 处理单个订阅者
local function processSubscriber(sub, targetFlag, link, subs, stack)
    local subFlags = sub.flags

    -- 处理非跟踪状态的订阅者
    if bit.band(subFlags, SubscriberFlags.Tracking) == 0 then
        local isCanPropagate = canPropagate(subFlags)
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
    if isValidLink(link, sub) then
        if bit.rshift(subFlags, 2) == 0 then
            updateSubscriberFlags(sub, bit.bor(targetFlag, SubscriberFlags.CanPropagate), false)
            return handleSubsAndCheck(sub, stack, targetFlag, link, subs)
        end

        -- 如果需要标记为脏
        if bit.band(sub.flags, targetFlag) == 0 then
            updateSubscriberFlags(sub, targetFlag, false)
        end
    end
    
    return stack, targetFlag, link, false
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

-- 主传播函数
local function propagate(subs)
    -- 初始状态
    local targetFlag = SubscriberFlags.Dirty  -- 状态1: 初始化目标标志
    local link = subs                         -- 状态2: 初始化链接
    local stack = 0                           -- 状态3: 初始化栈
    local nextSub = nil                       -- 状态4: 初始化下一个订阅者

    repeat
        local bBreak = false
        global.do_func(function()
            local sub = link.sub              -- 状态5: 获取当前订阅者
            
            -- 处理当前订阅者
            local shouldReturn
            -- 状态6: 更新订阅者状态
            stack, targetFlag, link, shouldReturn = processSubscriber(sub, targetFlag, link, subs, stack)
            if shouldReturn then
                -- 状态7: 提前返回，保持当前状态
                return
            end

            -- 状态8: 准备处理下一个订阅者
            nextSub = getNextSubscriber(subs)
            if not nextSub then
                if stack > 0 then
                    -- 状态9: 开始处理依赖栈
                    local dep = subs.dep
                    repeat
                        -- 状态10: 栈回退
                        stack = stack - 1
                        local depSubs = dep.subs
                        local prevLink = depSubs.prevSub
                        -- 状态11: 清理前一个链接
                        depSubs.prevSub = nil
                        -- 状态12: 更新订阅者和链接
                        subs = prevLink.nextSub
                        link = subs

                        if subs then
                            -- 状态13: 更新目标标志
                            targetFlag = SubscriberFlags.Dirty
                            if stack > 0 then
                                targetFlag = SubscriberFlags.ToCheckDirty
                            end
                            return -- do_func return
                        end

                        -- 状态14: 继续处理依赖
                        dep = prevLink.dep
                    until stack <= 0
                end
                -- 状态15: 处理完所有依赖，准备退出
                bBreak = true
                return
            end

            -- 状态16-17: 更新订阅者状态
            local newSubs, newLink, newFlag = updateSubscriberState(nextSub, stack, link, subs)
            subs = newSubs
            link = newLink
            if newFlag then
                targetFlag = newFlag
            end
        end)

        -- 状态18: 检查是否需要退出循环
        if bBreak then
            break
        end
    until false

    -- 状态19: 处理队列中的效果
    if global.batchDepth <= 0 then
        global.drainQueuedEffects()
    end
end

local function clearTrack(link)
	repeat
		global.do_func(function()
			local dep = link.dep
			local nextDep = link.nextDep
			local nextSub = link.nextSub
			local prevSub = link.prevSub

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

			link.dep = nil
			link.sub = nil
			link.nextDep = global.linkPool
			global.linkPool = link

			if not dep.subs and dep.deps then
				if dep.notify then
					dep.flags = SubscriberFlags.None
				else
					dep.flags = bit.bor(dep.flags, SubscriberFlags.Dirty)
				end

				local depDeps = dep.deps
				if depDeps then
					link = depDeps
					dep.depsTail.nextDep = nextDep
					dep.deps = nil
					dep.depsTail = nil
					return
				end
			end

			link = nextDep
		end)
	until not link
end

local function startTrack(sub)
	sub.depsTail = nil
    sub.flags = SubscriberFlags.Tracking
end

local function endTrack(sub)
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

	sub.flags = bit.band(sub.flags, bit.bnot(SubscriberFlags.Tracking))
end

local function checkDirty(deps)
    local stack = 0
	local dirty = false
	local nextDep = nil

	repeat
		local gototop = false
		local returned = false
		global.do_func(function()
			dirty = false

			local dep = deps.dep
			if dep.update then
				if dep.version ~= deps.version then
					dirty = true
				else
					local depFlags = dep.flags
					if bit.band(depFlags, SubscriberFlags.Dirty) > 0 then
						dirty = dep:update()
					elseif bit.band(depFlags, SubscriberFlags.ToCheckDirty) > 0 then
						dep.subs.prevSub = deps
						deps = dep.deps
						stack = stack + 1
						return -- do_func return
					end
				end
			end

			if not dirty then
				nextDep = deps.nextDep
			end

			if dirty or not nextDep then
				if stack > 0 then
					local sub = deps.sub
					repeat
						global.do_func(function()
							stack = stack - 1
							local subSubs = sub.subs
							local prevLink = subSubs.prevSub
							subSubs.prevSub = nil

							if dirty then
								if sub.update() then
									sub = prevLink.sub
									dirty = true
									return -- inner do_func return
								end
							else
								sub.flags = bit.band(sub.flags, bit.bnot(SubscriberFlags.ToCheckDirty))
							end

							deps = prevLink.nextDep
							if deps then
								gototop = true
								return -- inner do_func return
							end

							sub = prevLink.sub
							dirty = false
						end)

						if gototop then
							break
						end
					until stack <= 0

					if gototop then
						return -- outter do_func return
					end
				end

				returned = true
				return
			end

			deps = nextDep
		end)

		if returned then
			return dirty
		end
	until false
end

return {
	SubscriberFlags = SubscriberFlags,
	link = _link,
    Link = Link,

    propagate = propagate,
	checkDirty = checkDirty,
    startTrack = startTrack,
    endTrack = endTrack,
}
