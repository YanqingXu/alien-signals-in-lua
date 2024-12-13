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

local function propagate(subs)
    local targetFlag = SubscriberFlags.Dirty
    local link = subs
    local stack = 0

    repeat
		local bBreak = false
		global.do_func(function()
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
					local subSubs = sub.subs
					if subSubs then
						if subSubs.nextSub then
							subSubs.prevSub = subs
							subs = subSubs
							link = subs
							targetFlag = SubscriberFlags.ToCheckDirty
							stack = stack + 1
						else
							link = subSubs
							targetFlag = sub.notify and SubscriberFlags.RunInnerEffects or SubscriberFlags.ToCheckDirty
						end
						return
					end

					if sub.notify then
						if global.queuedEffectsTail then
							global.queuedEffectsTail.nextNotify = sub
						else
							global.queuedEffects = sub
						end
						global.queuedEffectsTail = sub
					end
				end
			elseif isValidLink(link, sub) then
				if bit.rshift(subFlags, 2) == 0 then
					sub.flags = bit.bor(sub.flags, bit.bor(targetFlag, SubscriberFlags.CanPropagate))
					local subSubs = sub.subs
					if subSubs then
						if subSubs.nextSub then
							subSubs.prevSub = subs
							subs = subSubs
							link = subs
							targetFlag = SubscriberFlags.ToCheckDirty
							stack = stack + 1
						else
							link = subSubs
							targetFlag = sub.notify and SubscriberFlags.RunInnerEffects or SubscriberFlags.ToCheckDirty
						end
						return
					end
				elseif bit.band(sub.flags, targetFlag) == 0 then
					sub.flags = bit.bor(sub.flags, targetFlag)
				end
			end

			local nextSub = subs.nextSub
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
							targetFlag = stack > 0 and SubscriberFlags.ToCheckDirty or SubscriberFlags.Dirty
							return
						end

						dep = prevLink.dep
					until stack <= 0
				end
				bBreak = true
				return
			end


			if link ~= subs then
				targetFlag = stack > 0 and SubscriberFlags.ToCheckDirty or SubscriberFlags.Dirty
			end

			subs = nextSub
			link = subs
		end)

		if bBreak then
			break
		end
    until false

    if global.batchDepth <= 0 then
        global.drainQueuedEffects()
    end
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

local function isFlagDirty(flag)
	return flag > 0 and bit.band(flag, SubscriberFlags.Dirty) > 0
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
					if isFlagDirty(depFlags) then
						dirty = dep:update()
					elseif bit.band(depFlags, SubscriberFlags.ToCheckDirty) > 0 then
						dep.subs.prevSub = deps
						deps = dep.deps
						stack = stack + 1
						return -- 跳出最外层 do_func
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
									return -- 跳出内层 do_func
								end
							else
								sub.flags = bit.band(sub.flags, bit.bnot(SubscriberFlags.Dirtys))
							end

							deps = prevLink.nextDep
							if deps then
								gototop = true
								return
							end

							sub = prevLink.sub
							dirty = false
						end)

						if gototop then
							break -- 跳出 repeat until stack <= 0
						end
					until stack <= 0

					if gototop then
						return -- 跳出最外层 do_func
					end
				end

				returned = true
				return -- 跳出最外层 do_func
			end
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
