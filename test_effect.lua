-- test_effect.lua
-- Test for Lua implementation of reactive system - focusing on effect functionality
print("========== Reactive System Effect Tests ==========\n")

-- Load reactive system
local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local effectScope = reactive.effectScope
local startBatch = reactive.startBatch
local endBatch = reactive.endBatch
local setCurrentSub = reactive.setCurrentSub

local utils = require("utils")
local test = utils.test
local expect = utils.expect


test('should clear subscriptions when untracked by all subscribers', function ()
    local bRunTimes = 0

    local a = signal(1)
    local b = computed(function()
        bRunTimes = bRunTimes + 1
        return a() * 2
    end)

    local stopEffect = effect(function()
        b()
    end)
    expect(bRunTimes).toBe(1)
    a(2)
    expect(bRunTimes).toBe(2)
    stopEffect()
    a(3)
    expect(bRunTimes).toBe(2)
    print("test passed\n")
end)

test('should not run untracked inner effect', function ()
    local a = signal(3)
    local b = computed(function()
        return a() > 0
    end)

    effect(function()
        if b() then
            effect(function()
                if a() == 0 then
                    error("bad")
                end
            end)
        end
    end)

    a(2)
    a(1)
    a(0)
    print("test passed\n")
end)

test('should run outer effect first', function ()
    local a = signal(1)
    local b = signal(1)

    effect(function()
        if a() > 0 then
            effect(function()
                b()
                if a() == 0 then
                    error("bad")
                end
            end)
        else
        end
    end)

    startBatch()
    b(0)
    a(0)
    endBatch()
    print("test passed\n")
end)

test('should not trigger inner effect when resolve maybe dirty', function ()
	local a = signal(0)
	local b = computed(function() return a() % 2 end)

	local innerTriggerTimes = 0

	effect(function()
		effect(function()
			b()
			innerTriggerTimes = innerTriggerTimes + 1
			if innerTriggerTimes >= 2 then
				error("bad")
			end
		end)
	end)

	a(2)
    print("test passed\n")
end)

test('should trigger inner effects in sequence', function()
	local a = signal(0)
	local b = signal(0)
	local c = computed(function() return a() - b() end)
	local order = {}

	effect(function()
		c()

		effect(function()
			table.insert(order, 'first inner')
			a()
		end)

		effect(function()
			table.insert(order, 'last inner')
			a()
			b()
		end)
    end)

	order = {}

	startBatch()
	b(1)
	a(1)
	endBatch()

	expect(order).toEqual({'first inner', 'last inner'})
    print("test passed\n")
end)

test('should trigger inner effects in sequence in effect scope', function()
	local a = signal(0)
	local b = signal(0)
	local order = {}

	effectScope(function()

		effect(function()
			table.insert(order, 'first inner')
			a()
		end)

		effect(function()
			table.insert(order, 'last inner')
			a()
			b()
		end)
	end)

	order = {}

	startBatch()
	b(1)
	a(1)
	endBatch()

	expect(order).toEqual({'first inner', 'last inner'})
    print("test passed\n")
end)

test('should custom effect support batch', function()
	function batchEffect(fn)
		return effect(function()
			startBatch()
			local result = fn()
            endBatch()
            return result
		end)
	end

	local logs = {}
	local a = signal(0)
	local b = signal(0)

	local aa = computed(function()
		table.insert(logs, 'aa-0')
		if a() == 0 then
			b(1)
		end
		table.insert(logs, 'aa-1')
	end)

	local bb = computed(function()
		table.insert(logs, 'bb')
		return b()
	end)

	batchEffect(function()
		bb()
	end)
	batchEffect(function()
		aa()
	end)

	expect(logs).toEqual({'bb', 'aa-0', 'aa-1', 'bb'})
    print("test passed\n")
end)

test('should duplicate subscribers do not affect the notify order', function()
	local src1 = signal(0)
	local src2 = signal(0)
	local order = {}

	effect(function()
		table.insert(order, 'a')
		local currentSub = setCurrentSub(nil)
		local isOne = src2() == 1
		setCurrentSub(currentSub)
		if isOne then
			src1()
		end
		src2()
		src1()
	end)
	effect(function()
		table.insert(order, 'b')
		src1()
	end)
	src2(1) -- src1.subs: a -> b -> a

	order = {}
	src1(src1() + 1)

	expect(order).toEqual({'a', 'b'})
    print("test passed\n")
end)

test('should handle side effect with inner effects', function()
	local a = signal(0)
	local b = signal(0)
	local order = {}

	effect(function()
		effect(function()
			a()
			table.insert(order, 'a')
		end)
		effect(function()
			b()
			table.insert(order, 'b')
		end)
		expect(order).toEqual({'a', 'b'})

		order = {}
		b(1)
		a(1)
		expect(order).toEqual({'b', 'a'})
	end)
    print("test passed\n")
end)

test('should handle flags are indirectly updated during checkDirty', function()
	local a = signal(false)
	local b = computed(function() return a() end)
	local c = computed(function()
		b()
		return 0
	end)
	local d = computed(function()
		c()
		return b()
	end)

	local triggers = 0

	effect(function()
		d()
		triggers = triggers + 1
	end)
	expect(triggers).toBe(1)
	a(true)
	expect(triggers).toBe(2)
    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")
