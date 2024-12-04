require 'bit'
require 'global'
local system = require 'system'

local Effect = {}
Effect.__index = Effect

-- 创建一个副作用函数
function Effect.new(fn)
    local self = setmetatable({}, Effect)
    self.fn = fn
    self.nextNotify = nil

    -- Dependency
    self.subs = nil
    self.subsTail = nil

    -- Subscriber
    self.deps = nil
    self.depsTail = nil
    self.flags = system.SubscriberFlags.Dirty;

    return self
end

-- 通知副作用函数重新运行
function Effect:notify()
    local flags = self.flags
    if bit.band(flags, system.SubscriberFlags.Dirty) > 0 then
        self:run()
        return
    end

    if bit.band(flags, system.SubscriberFlags.ToCheckDirty) > 0 then
        if system.checkDirty(self.deps) then
            self:run()
            return
        else
            self.flags = bit.band(self.flags, bit.bnot(system.SubscriberFlags.ToCheckDirty))
        end
    end

    if bit.band(flags, system.SubscriberFlags.RunInnerEffects) ~= 0 then
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

-- 运行副作用函数
function Effect:run()
    local prevSub = global.activeSub
    local prevTrackId = global.activeTrackId
    global.setActiveSub(self, global.nextTrackId())
    system.startTrack(self)

    local success, result = pcall(self.fn)
    if not success then
        global.setActiveSub(prevSub, prevTrackId)
        system.endTrack(self)
		return
    end

	global.setActiveSub(prevSub, prevTrackId)
	system.endTrack(self)
	return result
end

-- 停止副作用函数
function Effect:stop()
    system.startTrack(self)
    system.endTrack(self)
end

local function effect(fn)
    local e = Effect.new(fn)
    e:run()
    return e
end

return {
    effect = effect,
    Effect = Effect,
}
