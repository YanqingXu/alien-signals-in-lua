require 'global'
local system = require 'system'

local Signal = {}
Signal.__index = Signal

function Signal.new(initialValue)
    local self = setmetatable({}, Signal)
    self.currentValue = initialValue
    self.subs = nil
    self.subsTail = nil
    self.lastTrackedId = 0
    return self
end

function Signal:get()
    if global.activeTrackId > 0 and self.lastTrackedId ~= global.activeTrackId then
        self.lastTrackedId = global.activeTrackId
        system.link(self, global.activeSub)
    end
    return self.currentValue
end

function Signal:set(value)
    if self.currentValue ~= value then
        self.currentValue = value

        local subs = self.subs
        if subs then
            system.propagate(subs)
        end
    end
end

local function signal(initialValue)
    return Signal.new(initialValue)
end

return {
    signal = signal,
    Signal = Signal
}
