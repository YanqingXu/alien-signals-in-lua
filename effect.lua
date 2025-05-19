-- effect.lua - 处理响应式副作用函数
require("global")
local ReactiveFlags = global.ReactiveFlags

-- @param this: Effect | EffectScope
local function effectOper(this)
	local dep = this.deps

	while(dep) do
		dep = global.unlink(dep, this)
	end

	local sub = this.subs
	if sub then
		global.unlink(sub)
	end

	this.flags = ReactiveFlags.None
end

-- 创建响应式副作用函数
local function effect(fn)
    local e = {
		fn = fn,
		subs = nil,
		subsTail = nil,
		deps = nil,
		depsTail = nil,
        flags = ReactiveFlags.Watching,
    }

	local vars = global.vars
	if vars.activeSub then
		global.link(e, vars.activeSub)
	elseif vars.activeScope then
		global.link(e, vars.activeScope)
	end

	local prev = global.setCurrentSub(e)
	local success, err = pcall(fn)
	global.setCurrentSub(prev)

	if not success then
		error(err)
	end

	return utils.bind(effectOper, e)
end

-- 创建效果作用域，用于批量清理效果
-- @return 作用域对象，包含run和cleanup方法
local function effectScope(fn)
    -- 创建效果作用域
    local e = {
		deps = nil,
		depsTail = nil,
		subs = nil,
		subsTail = nil,
		flags = ReactiveFlags.None,
    }

    local vars = global.vars
	if vars.activeScope then
		global.link(e, vars.activeScope)
	end

	local prevSub = global.setCurrentSub()
	local prevScope = global.setCurrentScope(e)

	local success, err = pcall(function()
		fn()
	end)

	if not success then
		error(err)
	end

	global.setCurrentScope(prevScope)
	global.setCurrentSub(prevSub)

	return utils.bind(effectOper, e)
end

global.effect = effect
global.effectScope = effectScope
global.effectOper = effectOper

-- 返回模块接口
return {
    effect = effect,
    effectScope = effectScope
}
