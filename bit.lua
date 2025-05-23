local bit = {}

function bit.lshift(a, n)
    return a * (2 ^ n)
end

function bit.rshift(a, n)
    return math.floor(a / (2 ^ n))
end

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

function bit.bnot(a)
    return 4294967295 - a
end

return bit