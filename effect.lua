require 'bit'
require 'global'
local system = require 'system'

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
    self.flags = system.SubscriberFlags.Dirty;

    self.args = {...}

    if global.activeTrackId > 0 then
        system.link(self, global.activeSub)
    elseif global.activeEffectScope then
        system.link(self, global.activeEffectScope)
    end

    return self
end

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
        end

        self.flags = bit.band(self.flags, bit.bnot(system.SubscriberFlags.ToCheckDirty))
    end

    if bit.band(flags, system.SubscriberFlags.RunInnerEffects) > 0 then
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

function Effect:run()
    local prevSub = global.activeSub
    local prevTrackId = global.activeTrackId

    global.setActiveSub(self, global.nextTrackId())
    system.startTrack(self)

    local success, result = pcall(self.fn)

    global.setActiveSub(prevSub, prevTrackId)
    system.endTrack(self)

    if not success then
		return
    end

	return result
end

function Effect:stop()
    system.startTrack(self)
    system.endTrack(self)
end

local function effect(fn, ...)
    local e = Effect.new(fn, ...)
    e:run()
    return e
end

return {
    effect = effect,
    Effect = Effect,
}
