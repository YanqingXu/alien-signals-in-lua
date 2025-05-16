-- computed.lua - 处理计算属性的实现
require("global")
local ReactiveFlags = global.ReactiveFlags

-- 计算属性操作函数
-- @param computed 计算属性对象
-- @return 计算属性的当前值
local function computedOper(this)
    local flags = this.flags
	local isDirty = bit.band(flags, ReactiveFlags.Dirty) > 0
	local maybeDirty = bit.band(flags, ReactiveFlags.Pending) > 0

	if isDirty or (maybeDirty and global.checkDirty(this.deps, this)) then
		if global.updateComputed(this) then
			local subs = this.subs
			if subs then
				global.shallowPropagate(subs)
			end
		end
	elseif bit.band(flags, ReactiveFlags.Pending) > 0 then
		this.flags = bit.band(flags, bit.bnot(ReactiveFlags.Pending))
	end

	local vars = global.vars
	if vars.activeSub then
		global.link(this, vars.activeSub)
	elseif vars.activeScope then
		global.link(this, vars.activeScope)
	end

	return this.value
end

local function computed(getter)
    local c = {
        value = nil,
        subs = nil,
        subsTail = nil,
        deps = nil,
        depsTail = nil,
        flags = bit.bor(ReactiveFlags.Mutable, ReactiveFlags.Dirty),
        getter = getter,
    }

    return utils.bind(computedOper, c)
end

global.computed = computed

-- 返回模块接口
return {
    computed = computed,
}
