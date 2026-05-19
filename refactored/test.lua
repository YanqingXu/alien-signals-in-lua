--[[
运行重构版的完整测试套件。

用法：
  lua refactored/test.lua

这个脚本会把 tests/ 目录下所有 test_*.lua 文件都指向 require("refactored")。
也就是说，测试文件里原本的 require("alien_signals") 会拿到重构后的模块化实现。
]]

local function ensurePackagePath(pattern)
    if not string.find(package.path, pattern, 1, true) then
        package.path = pattern .. ";" .. package.path
    end
end

ensurePackagePath("./?.lua")
ensurePackagePath("./?/init.lua")

package.loaded["alien_signals"] = require("refactored")

local testFiles = {
    "tests/test_computed_chain.lua",
    "tests/test_computed.lua",
    "tests/test_effect_cleanup.lua",
    "tests/test_effect.lua",
    "tests/test_effectScope.lua",
    "tests/test_issue_48.lua",
    "tests/test_issue_97.lua",
    "tests/test_nil_value.lua",
    "tests/test_recursion.lua",
    "tests/test_refactored_modules.lua",
    "tests/test_topology.lua",
    "tests/test_trigger.lua",
    "tests/test_untrack.lua",
}

for _, testFile in ipairs(testFiles) do
    print("\n>>> RUN " .. testFile)
    dofile(testFile)
end

print("\n========== Refactored test suite completed ==========")
