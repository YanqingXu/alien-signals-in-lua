local bit = {}

-- 位操作: 左移
function bit.lshift(a, n)
    return a * (2 ^ n)
end

-- 位操作: 右移
function bit.rshift(a, n)
    return math.floor(a / (2 ^ n))
end

-- 位操作: 与
function bit.band(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a/2)
        b = math.floor(b/2)
    end
    return result
end

-- 位操作: 或
function bit.bor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a/2)
        b = math.floor(b/2)
    end
    return result
end

-- 位操作: 异或
function bit.bxor(a, b)
    local result = 0
    local value = 1
    while a > 0 or b > 0 do
        local aa = a % 2
        local bb = b % 2
        if aa ~= bb then
            result = result + value
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        value = value * 2
    end
    return result
end

-- 位操作: 位取反
function bit.bnot(a)
	return 4294967295 - a
end

local SubscriberFlags = {
    None = 0,
    Tracking = 1,
    CanPropagate = 2,
    RunInnerEffects = 4,
    ToCheckDirty = 8,
    Dirty = 16
}

local g_activeSub = nil
local g_activeTrackId = 0
local g_lastTrackId = 0

local g_activeEffectScope = nil
local g_batchDepth = 0
local g_queuedEffects = nil
local g_queuedEffectsTail = nil
local g_linkPool = nil

local do_func = nil
local nextTrackId = nil
local setActiveSub = nil
local startTrack = nil
local endTrack = nil
local startBatch = nil
local endBatch = nil
local drainQueuedEffects = nil

local signal = nil
local effect = nil
local computed = nil
local effectScope = nil

local linkDep = nil
local propagate = nil

local Signal = {}
Signal.__index = Signal

function Signal.new(initialValue, ...)
    local self = setmetatable({}, Signal)
    self.currentValue = initialValue
    self.subs = nil
    self.subsTail = nil
    self.lastTrackedId = 0
    self.args = {...}
    return self
end

function Signal:get()
    if g_activeTrackId > 0 and self.lastTrackedId ~= g_activeTrackId then
        self.lastTrackedId = g_activeTrackId
        linkDep(self, g_activeSub)
    end
    return self.currentValue
end

function Signal:set(value)
    if self.currentValue ~= value then
        self.currentValue = value

        if self.subs then
            propagate(self.subs)
        end
    end
end

signal = function(initialValue, ...)
    return Signal.new(initialValue, ...)
end

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

    if g_linkPool then
        newLink = g_linkPool
        g_linkPool = newLink.nextDep
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

linkDep = function(dep, sub)
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

local function clearTrack(link)
	repeat
		do_func(function()
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
			link.nextDep = g_linkPool
			g_linkPool = link

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

propagate = function(subs)
    local targetFlag = SubscriberFlags.Dirty
    local link = subs
    local stack = 0
	local nextSub = nil

    repeat
		local bBreak = false
		do_func(function()
			local sub = link.sub
			local subFlags = sub.flags

			if bit.band(subFlags, SubscriberFlags.Tracking) == 0 then
				local canPropagate = bit.rshift(subFlags, 2) == 0
				if not canPropagate and bit.band(subFlags, SubscriberFlags.CanPropagate) > 0 then
					sub.flags = bit.band(sub.flags, bit.bnot(SubscriberFlags.CanPropagate))
					canPropagate = true
				end

				if canPropagate then
					sub.flags = bit.bor(sub.flags, targetFlag)
					stack, targetFlag, link = checkSubs(sub, link, subs, stack, targetFlag)
					if sub.subs then
						return
					end

					if sub.notify then
						if g_queuedEffectsTail then
							g_queuedEffectsTail.nextNotify = sub
						else
							g_queuedEffects = sub
						end
						g_queuedEffectsTail = sub
					end
				elseif bit.band(sub.flags, targetFlag) == 0 then
					sub.flags = bit.bor(sub.flags, targetFlag)
				end
			elseif isValidLink(link, sub) then
				if bit.rshift(subFlags, 2) == 0 then
					sub.flags = bit.bor(sub.flags, bit.bor(targetFlag, SubscriberFlags.CanPropagate))
					stack, targetFlag, link = checkSubs(sub, link, subs, stack, targetFlag)
					if sub.subs then
						return
					end
				elseif bit.band(sub.flags, targetFlag) == 0 then
					sub.flags = bit.bor(sub.flags, targetFlag)
				end
			end

			nextSub = subs.nextSub
			if not nextSub then
				if stack > 0 then
					local dep = subs.dep
					repeat
						stack = stack - 1
						local depSubs = dep.subs
						local prevLink = depSubs.prevSub
						depSubs.prevSub = nil
						subs = prevLink.nextSub
						link = subs

						if subs then
							targetFlag = SubscriberFlags.Dirty
							if stack > 0 then
								targetFlag = SubscriberFlags.ToCheckDirty
							end
							return -- do_func return
						end

						dep = prevLink.dep
					until stack <= 0
				end
				bBreak = true
				return
			end

			if link ~= subs then
				targetFlag = SubscriberFlags.Dirty
				if stack > 0 then
					targetFlag = SubscriberFlags.ToCheckDirty
				end
			end

			subs = nextSub
			link = subs
		end)

		if bBreak then
			break
		end
    until false

    if g_batchDepth <= 0 then
        drainQueuedEffects()
    end
end

startTrack = function(sub)
	sub.depsTail = nil
    sub.flags = SubscriberFlags.Tracking
end

endTrack = function(sub)
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
		do_func(function()
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
						do_func(function()
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

local Effect = {}
Effect.__index = Effect

function Effect.new(fn, ...)
    local self = setmetatable({}, Effect)
    self.fn = fn
    self.nextNotify = nil

    -- Dependency
    self.subs = nil
    self.subsTail = nil

    -- Subscriber
    self.deps = nil
    self.depsTail = nil
    self.flags = SubscriberFlags.Dirty;

    self.args = {...}

    if g_activeTrackId > 0 then
        linkDep(self, g_activeSub)
    elseif g_activeEffectScope then
        linkDep(self, g_activeEffectScope)
    end

    return self
end

function Effect:notify()
    local flags = self.flags
    if bit.band(flags, SubscriberFlags.Dirty) > 0 then
        self:run()
        return
    end

    if bit.band(flags, SubscriberFlags.ToCheckDirty) > 0 then
        if checkDirty(self.deps) then
            self:run()
            return
        end

        self.flags = bit.band(self.flags, bit.bnot(SubscriberFlags.ToCheckDirty))
    end

    if bit.band(flags, SubscriberFlags.RunInnerEffects) > 0 then
        self.flags = bit.band(self.flags, bit.bnot(SubscriberFlags.RunInnerEffects))
        local link = self.deps

        repeat
            local dep = link.dep
            if dep.notify then
                dep:notify()
            end
            link = link.nextDep
        until not link
    end
end

function Effect:run()
    local prevSub = g_activeSub
    local prevTrackId = g_activeTrackId

    setActiveSub(self, nextTrackId())
    startTrack(self)

    local success, result = pcall(self.fn)

    setActiveSub(prevSub, prevTrackId)
    endTrack(self)

    if not success then
		return
    end

	return result
end

function Effect:stop()
    startTrack(self)
    endTrack(self)
end

effect = function(fn, ...)
    local e = Effect.new(fn, ...)
    e:run()
    return e
end

local Computed = {}
Computed.__index = Computed

function Computed.new(getter, ...)
    local self = setmetatable({}, Computed)
    self.getter = getter
    self.cachedValue = nil
    self.version = 0

    -- 作为依赖项的属性
    self.subs = nil         -- 订阅者链表头
    self.subsTail = nil     -- 订阅者链表尾
    self.lastTrackedId = 0

    -- 作为订阅者的属性
    self.deps = nil         -- 依赖项链表头
    self.depsTail = nil     -- 依赖项链表尾
    self.flags = SubscriberFlags.Dirty
    self.args = {...}
    return self
end

function Computed:get()
    local flags = self.flags
    if bit.band(flags, SubscriberFlags.Dirty) > 0 then
        self:update()
    elseif bit.band(flags, SubscriberFlags.ToCheckDirty) > 0 then
        if checkDirty(self.deps) then
            self:update()
        else
            self.flags = bit.band(self.flags, bit.bnot(SubscriberFlags.ToCheckDirty))
        end
    end

    -- 如果当前有活动的追踪上下文，建立依赖关系
    if g_activeTrackId > 0 and self.lastTrackedId ~= g_activeTrackId then
        self.lastTrackedId = g_activeTrackId
        local link = linkDep(self, g_activeSub)
        link.version = self.version
    end

    return self.cachedValue
end

function Computed:update()
    local prevSub = g_activeSub
    local prevTrackId = g_activeTrackId

    setActiveSub(self, nextTrackId())
    startTrack(self)

    local oldValue = self.cachedValue
    local success, newValue = pcall(self.getter, oldValue)

    setActiveSub(prevSub, prevTrackId)
    endTrack(self)

    if not success then
		return
    end

    if oldValue ~= newValue then
        self.cachedValue = newValue
        self.version = self.version + 1
        return true
    end

    return false
end

computed = function(getter, ...)
    return Computed.new(getter, ...)
end

local EffectScope = {}
EffectScope.__index = EffectScope

function EffectScope.new(...)
	local self = setmetatable({}, EffectScope)
	self.deps = nil
	self.depsTail = nil
	self.flags = SubscriberFlags.None
	self.args = {...}
	return self
end

function EffectScope:notify()
	if bit.band(self.flags, SubscriberFlags.RunInnerEffects) > 0 then
		self.flags = bit.band(self.flags, bit.bnot(SubscriberFlags.RunInnerEffects))
		local link = self.deps
		repeat
			local dep = link.dep
			if dep.notify then
				dep:notify()
			end
			link = link.nextDep
		until not link
	end
end

function EffectScope:run(fn)
	local prevSub = g_activeEffectScope

	g_activeEffectScope = self
	local success, result = pcall(fn)
	g_activeEffectScope = prevSub

	if not success then
		return
	end

	return result
end

function EffectScope:stop()
	startTrack(self)
	endTrack(self)
end

effectScope = function(...)
	return EffectScope.new(...)
end


nextTrackId = function()
    g_lastTrackId = g_lastTrackId + 1
    return g_lastTrackId
end

setActiveSub = function(sub, trackId)
    g_activeSub = sub
    g_activeTrackId = trackId
end

startBatch = function()
    g_batchDepth = g_batchDepth + 1
end

endBatch = function()
    g_batchDepth = g_batchDepth - 1
    if g_batchDepth <= 0 then
        drainQueuedEffects()
    end
end

drainQueuedEffects = function()
    while g_queuedEffects do
        local effect = g_queuedEffects
        local queuedNext = effect.nextNotify

        if queuedNext then
            effect.nextNotify = nil
            g_queuedEffects = queuedNext
        else
            g_queuedEffects = nil
            g_queuedEffectsTail = nil
        end

        effect:notify()
    end
end

do_func = function(func, ...)
	if func then
        return func(...)
    end
end

return {
    signal = signal,
    computed = computed,
    effect = effect,
    effectScope = effectScope,
    startBatch = startBatch,
    endBatch = endBatch,
}
