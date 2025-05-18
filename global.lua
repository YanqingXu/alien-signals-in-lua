-- global.lua - 集中管理响应式系统的全局变量和状态

-- 导入bit库
require("bit")
require("utils")

-- 创建全局模块表
global = {}

-- 响应式系统标志位
local ReactiveFlags = {
	None = 0,
    Mutable = 1,
    Watching = 2,
	RecursedCheck = 4,
	Recursed = 8,
    Dirty = 16,
	Pending = 32,
}

global.ReactiveFlags = ReactiveFlags

local EffectFlags = {
	Queued = 64, -- 1 << 6
}

global.EffectFlags = EffectFlags

-- 初始化全局变量
local vars = {
    activeSub = nil,
    activeScope = nil,

	pauseStack = {},
	queuedEffects = {},
	queuedEffectsLength = 0,

    isTracking = false,
    currentNode = nil,
    batchDepth = 0,
    pendingEffects = {},
    pendingEffectsLength = 0,
	notifyIndex = 0,
}

global.vars = vars

function global.getCurrentSub()
	return vars.activeSub
end

function global.setCurrentSub(sub)
	local prevSub = vars.activeSub
	vars.activeSub = sub
	return prevSub
end

function global.getCurrentScope()
	return vars.activeScope
end

function global.setCurrentScope(scope)
	local prevScope = vars.activeScope
	vars.activeScope = scope
	return prevScope
end

function global.startBatch()
	vars.batchDepth = vars.batchDepth + 1
end

function global.endBatch()
	vars.batchDepth = vars.batchDepth - 1
	if 0 == vars.batchDepth then
		global.flush()
	end
end

function global.pauseTracking()
	vars.pauseStack[#vars.pauseStack + 1] = global.setCurrentSub()
end

function global.resumeTracking()
	local top = table.remove(vars.pauseStack, #vars.pauseStack)
	global.setCurrentSub(top)
end

function global.flush()
	while vars.notifyIndex < vars.queuedEffectsLength do
		local effect = vars.queuedEffects[vars.notifyIndex+1]
		vars.queuedEffects[vars.notifyIndex+1] = nil
		vars.notifyIndex = vars.notifyIndex + 1

		if effect then
			effect.flags = bit.band(effect.flags, bit.bnot(EffectFlags.Queued))
			global.run(effect, effect.flags)
		end
	end

	vars.notifyIndex = 0
	vars.queuedEffectsLength = 0
end

function global.run(e, flags)
	local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
	local isPending = bit.band(flags, ReactiveFlags.Pending) > 0

	if isDirty or (isPending and global.checkDirty(e.deps, e)) then
		local prev = global.setCurrentSub(e)
		global.startTracking(e)

		local result, err = pcall(e.fn)
		if not result then
			print("Error in effect: " .. err)
		end

		global.setCurrentSub(prev)
		global.endTracking(e)

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
			global.run(dep, dep.flags)
		end

		link = link.nextDep
	end
end

--[[===================================================================================
响应式节点 (ReactiveNode)

所有响应式对象（信号、计算属性、效果）的基础结构。每个响应式节点维护两种关系：
1. 依赖关系(deps)：当前节点依赖的其他节点链表
2. 订阅关系(subs)：依赖当前节点的其他节点链表

字段说明：
- deps: 指向第一个依赖链接的指针，链表头
- depsTail: 指向最后一个依赖链接的指针，用于快速添加新依赖
- subs: 指向第一个订阅者链接的指针，链表头
- subsTail: 指向最后一个订阅者链接的指针，用于快速添加新订阅者
- flags: 节点的状态标志，使用位运算高效管理状态

此结构遵循TypeScript版本的设计，使用双向链表跟踪依赖关系
===================================================================================--]]
global.ReactiveNode = {
	create = function()
		return {
			deps = nil,     -- 第一个依赖链接
			depsTail = nil, -- 最后一个依赖链接
			subs = nil,     -- 第一个订阅者链接
			subsTail = nil, -- 最后一个订阅者链接
			flags = ReactiveFlags.Mutable -- 节点状态标志
		}
	end
}

--[[===================================================================================
链接对象 (Link)

维护响应式节点之间的依赖关系，使用双向链表结构连接依赖节点和订阅节点。
每个Link实例代表一个dep->sub的依赖关系。

字段说明：
- dep: 依赖节点（被依赖的节点）
- sub: 订阅节点（依赖其他节点的节点）
- prevSub: 在订阅者链表中的前一个链接，用于反向遍历
- nextSub: 在订阅者链表中的下一个链接，用于正向遍历
- prevDep: 在依赖链表中的前一个链接，用于反向遍历
- nextDep: 在依赖链表中的下一个链接，用于正向遍历

使用双向链表可以实现O(1)时间复杂度的节点删除操作，优于单链表实现
===================================================================================--]]
global.Link = {
	create = function(dep, sub, prevSub, nextSub, prevDep, nextDep)
		return {
			dep = dep,      -- 依赖节点
			sub = sub,      -- 订阅节点
			prevSub = prevSub,  -- 订阅链表中的前一个链接
			nextSub = nextSub,  -- 订阅链表中的下一个链接
			prevDep = prevDep,  -- 依赖链表中的前一个链接
			nextDep = nextDep   -- 依赖链表中的下一个链接
		}
	end
}

function global.link(dep, sub)
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
    if prevSub and prevSub.sub == sub and (recursedCheck == 0 or global.isValidLink(prevSub, sub)) then
        return
    end

    -- 创建新的连接对象
    local newLink = global.Link.create(dep, sub, prevDep, nextDep, prevSub)
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

function global.unlink(link, sub)
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
            global.unwatched(dep)
        end
    end

    return nextDep
end

function global.propagate(link)
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
				elseif bit.band(flags, 48) == 0 and global.isValidLink(link, sub) then
					--48:Dirty | Pending  40:Recursed | Pending
					sub.flags = bit.bor(flags, 40)
					flags = bit.band(flags, ReactiveFlags.Mutable)
				else
					flags = ReactiveFlags.None
				end

				if bit.band(flags, ReactiveFlags.Watching) > 0 then
					global.notify(sub)
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

function global.startTracking(sub)
    sub.depsTail = nil

	-- 56: Recursed | Dirty | Pending  4: RecursedCheck
    sub.flags = bit.bor(bit.band(sub.flags, bit.bnot(56)), 4)
end

function global.endTracking(sub)
    local depsTail = sub.depsTail
    local toRemove = sub.deps
    if depsTail then
        toRemove = depsTail.nextDep
    end

    while toRemove do
        toRemove = global.unlink(toRemove, sub)
    end

    sub.flags = bit.band(sub.flags, bit.bnot(ReactiveFlags.RecursedCheck))
end

function global.checkDirty(link, sub)
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
				if global.update(dep) then
					local subs = dep.subs
					if subs.nextSub then
						global.shallowPropagate(subs)
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
						if global.update(sub) then
							if hasMultipleSubs then
								global.shallowPropagate(firstSub)
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

function global.shallowPropagate(link)
    repeat
        local sub = link.sub
        local nextSub = link.nextSub
        local subFlags = sub.flags

        -- 48: Pending | Dirty,  32: Pending
        if bit.band(subFlags, 48) == 32 then
            sub.flags = bit.bor(subFlags, ReactiveFlags.Dirty)

			if bit.band(subFlags, ReactiveFlags.Watching) > 0 then
				global.notify(sub)
			end
        end

        link = nextSub
    until not link
end

function global.isValidLink(checkLink, sub)
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

function global.updateSignal(signal, value)
	signal.flags = ReactiveFlags.Mutable
	if signal.previousValue == value then
		return false
	end

	signal.previousValue = value
	return true
end

function global.updateComputed(c)
	local prevSub = global.setCurrentSub(c)
	global.startTracking(c)

	local oldValue = c.value
	local newValue = oldValue

	local result, err = pcall(function()
		newValue = c.getter(oldValue)
		c.value = newValue
	end)

	if not result then
		print("Error in computed: " .. err)
	end

	global.setCurrentSub(prevSub)
	global.endTracking(c)

	return newValue ~= oldValue
end

-- @param signal: Signal | Computed
function global.update(signal)
	if signal.getter then
		return global.updateComputed(signal)
	end

	return global.updateSignal(signal, signal.value)
end

-- @param node: Signal, Computed, Effect, EffectScope
function global.unwatched(node)
	if node.getter then
		local toRemove = node.deps
		if toRemove then
			-- 17: Mutable | Dirty
			node.flags = 17
		end

		repeat
			toRemove = global.unlink(toRemove, node)
		until not toRemove
	elseif not node.previousValue then
		global.effectOper(node)
	end
end

-- @param e: Effect | EffectScope
function global.notify(e)
	local flags = e.flags
	if bit.band(flags, EffectFlags.Queued) == 0 then
		e.flags = bit.bor(flags, EffectFlags.Queued)

		local subs = e.subs
		if subs then
			global.notify(subs.sub)
		else
			vars.queuedEffectsLength = vars.queuedEffectsLength + 1
			vars.queuedEffects[vars.queuedEffectsLength] = e
		end
	end
end