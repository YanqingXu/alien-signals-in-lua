-- signal.lua - 处理响应式信号的实现
require("global")
local ReactiveFlags = global.ReactiveFlags

local function signalOper(this, newValue)
    if newValue then
		if newValue ~= this.value then
			this.value = newValue
			this.flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty)

			local subs = this.subs
			if subs then
				global.propagate(subs)
				if global.vars.batchDepth == 0 then
					global.flush()
				end
			end
		end
	else
		local value = this.value
		if bit.band(this.flags, ReactiveFlags.Dirty) > 0 then
			if global.updateSignal(this, value) then
				local subs = this.subs
				if subs then
					global.shallowPropagate(subs)
				end
			end
		end

		if global.vars.activeSub then
			global.link(this, global.vars.activeSub)
		end

		return value
	end
end

-- 创建信号对象
local function signal(initialValue)
    local s = {
        previousValue = initialValue,
        value = initialValue,
        subs = nil,
        subsTail = nil,
        flags = ReactiveFlags.Mutable,
    }

	return utils.bind(signalOper, s)
end

global.signal = signal

-- 返回模块接口
return {
    signal = signal,
}
