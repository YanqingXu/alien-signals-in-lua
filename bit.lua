bit = {}

-- 位操作: 左移
function bit.lshift(a, n)
    return a * (2 ^ n)
end

-- 位操作: 右移
function bit.rshift(a, n)
    return math.floor(a / (2 ^ n))
end

-- 位操作: 与
function bit.band(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a/2)
        b = math.floor(b/2)
    end
    return result
end

-- 位操作: 或
function bit.bor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a/2)
        b = math.floor(b/2)
    end
    return result
end

-- 位操作: 异或
function bit.bxor(a, b)
    local result = 0
    local value = 1
    while a > 0 or b > 0 do
        local aa = a % 2
        local bb = b % 2
        if aa ~= bb then
            result = result + value
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        value = value * 2
    end
    return result
end

-- 位操作: 位取反
function bit.bnot(a)
	return 4294967295 - a
end

-- 连续多个位操作
function bit.bop(op, ...)
	local result = 0
	local args = {...}
	local func = bit[op]
	if not func then
		error("Invalid bit operation: " .. op)
		return result
	end

	if #args < 2 then
		error("At least two arguments are required for bit operation: " .. op)
		return result
	end

	for i, v in ipairs(args) do
		if i == 1 then
			result = v
		else
			result = func(result, v)
		end
	end

	return result
end
