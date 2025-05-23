local utils = {}

-- 计数
function utils.count_i(tbl, pred)
    if not pred then
        return #tbl
    end

    local result = 0
    for i, v in ipairs(tbl) do
        if pred(v, i) then
            result = result + 1
        end
    end

    return result
end

function utils.unpack(tbl, i, count)
    count = count or utils.count_i(tbl)
    i = i or 1

    if i <= count then
        return tbl[i], utils.unpack(tbl, i + 1, count)
    end
end

function utils.do_func(func)
    func = func or function() end
    if type(func) == "function" then
        return func()
    end
end

function utils.concat(tbl, ...)
    local result = {}
    for _, v in ipairs(tbl) do
        table.insert(result, v)
    end

    for _, v in ipairs({...}) do
        for _, vv in ipairs(v) do
            table.insert(result, vv)
        end
    end

    return result
end

function utils.bind(func, ...)
    local args = {...}
    return function(...)
        return func(utils.unpack(utils.concat(args, {...})))
    end
end

function utils.test(name, fn)
    print(name)
    fn()
end

function utils.expect(actual)
    return {
        toBe = function(expected)
            assert(actual == expected)
        end,

        toEqual = function(expected)
            if type(actual) == "table" and type(expected) == "table" then
                for k, v in pairs(expected) do
                    assert(actual[k] == v)
                end
            else
                assert(actual == expected)
            end
        end,
    }
end

return utils