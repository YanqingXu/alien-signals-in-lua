require 'bit'
require 'global'
local system = require 'system'

local Computed = {}
Computed.__index = Computed

function Computed.new(getter, ...)
    local self = setmetatable({}, Computed)
    self.getter = getter    --计算函数
    self.cachedValue = nil  --缓存的计算结果
    self.version = 0        --版本号

    -- 作为依赖项的属性
    self.subs = nil         -- 订阅者链表头
    self.subsTail = nil     -- 订阅者链表尾
    self.lastTrackedId = 0  -- 最后一次追踪的ID

    -- 作为订阅者的属性
    self.deps = nil         -- 依赖项链表头
    self.depsTail = nil     -- 依赖项链表尾
    self.flags = system.SubscriberFlags.Dirty -- 状态标志
    self.args = {...}
    return self
end

function Computed:get()
    local flags = self.flags
    if bit.band(flags, system.SubscriberFlags.Dirty) > 0 then
        self:update()
    elseif bit.band(flags, system.SubscriberFlags.ToCheckDirty) > 0 then
        if system.checkDirty(self.deps) then
            self:update()
        else
            self.flags = bit.band(self.flags, bit.bnot(system.SubscriberFlags.ToCheckDirty))
        end
    end

    -- 如果当前有活动的追踪上下文，建立依赖关系
    if global.activeTrackId > 0 and self.lastTrackedId ~= global.activeTrackId then
        self.lastTrackedId = global.activeTrackId
        local link = system.link(self, global.activeSub)
        link.version = self.version
    end

    return self.cachedValue
end

function Computed:update()
    local prevSub = global.activeSub
    local prevTrackId = global.activeTrackId

    global.setActiveSub(self, global.nextTrackId())
    system.startTrack(self)

    local oldValue = self.cachedValue
    local success, newValue = pcall(self.getter, oldValue)

    global.setActiveSub(prevSub, prevTrackId)
    system.endTrack(self)

    if not success then
		return false
    end

    if oldValue ~= newValue then
        self.cachedValue = newValue
        self.version = self.version + 1
        return true
    end

    return false
end

local function computed(getter, ...)
    return Computed.new(getter, ...)
end

return {
    computed = computed,
    Computed = Computed
}
