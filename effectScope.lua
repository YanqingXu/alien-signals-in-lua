require 'bit'
require 'global'
local system = require 'system'

local EffectScope = {}
EffectScope.__index = EffectScope

function EffectScope.new()
	local self = setmetatable({}, EffectScope)
	self.deps = nil
	self.depsTail = nil
	self.flags = system.SubscriberFlags.None
	return self
end

function EffectScope:notify()
	if bit.band(self.flags, system.SubscriberFlags.RunInnerEffects) > 0 then
		self.flags = bit.band(self.flags, bit.bnot(system.SubscriberFlags.RunInnerEffects))
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
	local prevSub = global.activeEffectScope
	global.activeEffectScope = self

	local success, result = pcall(fn)
	if not success then
		global.activeEffectScope = prevSub
		return
	end

	global.activeEffectScope = prevSub
	return result
end

function EffectScope:stop()
	system.startTrack(self)
	system.endTrack(self)
end

local function effectScope()
	return EffectScope.new()
end

return {
	effectScope = effectScope,
	EffectScope = EffectScope
}