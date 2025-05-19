-- test_effectScope.lua
-- Test for Lua implementation of reactive system - focusing on effect scope functionality
print("========== Reactive System Effect Scope Tests ==========\n")

-- Load reactive system
local reactive = require("reactive")
local signal = reactive.signal
local effect = reactive.effect
local effectScope = reactive.effectScope


local utils = require("utils")
local test = utils.test
local expect = utils.expect

test('should not trigger after stop', function ()
	local count = signal(1)

	local triggers = 0
	local effect1

	local stopScope = effectScope(function()
		effect1 = effect(function()
			triggers = triggers + 1
			count()
        end)
		expect(triggers).toBe(1)

		count(2)
		expect(triggers).toBe(2)
	end)

	count(3)
	expect(triggers).toBe(3)
	stopScope()
	count(4)
	expect(triggers).toBe(3)

    print("test passed\n")
end)

test('should dispose inner effects if created in an effect', function()
	local source = signal(1)

	local triggers = 0

	effect(function()
		local dispose = effectScope(function()
			effect(function()
				source()
				triggers = triggers + 1
            end)
		end)
		expect(triggers).toBe(1)

		source(2)
		expect(triggers).toBe(2)
		dispose()
		source(3)
		expect(triggers).toBe(2)
	end)

    print("test passed\n")
end)

print("========== All tests passed!!! ==========\n")
print("====================================================\n")

