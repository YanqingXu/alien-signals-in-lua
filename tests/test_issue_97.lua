-- test_issue_97.lua
-- Reproduction of https://github.com/stackblitz/alien-signals/issues/97
-- flush() halts remaining effects on error, leaving queue in inconsistent state

print("========== Issue #97 Regression Test ==========\n")
print("Testing: flush() queue cleanup after effect error\n")

local reactive = require("alien_signals")
local signal = reactive.signal
local effect = reactive.effect

local a = signal(0)
local b = signal(0)
local runLog = {}

-- Effect 1: depends on 'a', runs normally
effect(function()
    table.insert(runLog, "a-1:" .. a())
end)

-- Effect 2: depends on 'a', throws when a() == 2
effect(function()
    if a() == 2 then
        error("Simulated error in effect a-2")
    end
    table.insert(runLog, "a-2:" .. a())
end)

-- Effect 3: depends on 'a', runs normally
effect(function()
    table.insert(runLog, "a-3:" .. a())
end)

-- Effect 4: depends on 'b', should NOT be affected by errors in 'a' effects
effect(function()
    table.insert(runLog, "b-1:" .. b())
end)

-- Step 1: Initial effects already ran during registration
print("Step 1: Initial state (effects ran during creation)")
print("  Run log:", table.concat(runLog, ", "))
local hasAllInitial = runLog[1] == "a-1:0" and runLog[2] == "a-2:0"
                   and runLog[3] == "a-3:0" and runLog[4] == "b-1:0"
if hasAllInitial then
    print("  Initial run: PASS (all 4 effects executed)")
else
    print("  Initial run: FAIL")
end

runLog = {}

-- Step 2: Set a=1, all 'a' effects should run (b-1 should NOT re-run)
print("\nStep 2: a(1)")
a(1)
print("  Run log:", table.concat(runLog, ", "))
local a1ok = runLog[1] == "a-1:1" and runLog[2] == "a-2:1" and runLog[3] == "a-3:1"
if a1ok and #runLog == 3 then
    print("  PASS: only a-effects ran, b-1 did not re-run")
else
    print("  FAIL: expected 3 entries (a-1:1, a-2:1, a-3:1), got", #runLog)
end

runLog = {}

-- Step 3: Set a=2, effect a-2 will throw.
-- The flush() fix should:
--   1. Let a-1 run before a-2 throws
--   2. a-2 throws, caught by flush()'s pcall
--   3. Clean up remaining queue (a-3) and reset queue state
--   4. Re-throw the error
print("\nStep 3: a(2) [effect a-2 throws, flush() cleans queue]")
local success, err = pcall(function()
    a(2)
end)
if not success then
    print("  Caught error (expected):", err)
else
    print("  ERROR: Expected error was not thrown!")
end

-- Clear runLog so we only see what Step 4 triggers
runLog = {}

-- Step 4: Set b=3. With the fix, only b-1 should run.
-- Without the fix, stale a-1/a-3 from the failed flush would also run.
print("\nStep 4: b(3) [should ONLY trigger b-1]")
b(3)
print("  Run log:", table.concat(runLog, ", "))

-- Check for stale effects
local hasStaleA = false
local expectOnlyB = true
for _, entry in ipairs(runLog) do
    if string.sub(entry, 1, 1) == "a" then
        hasStaleA = true
        print("  STALE EFFECT:", entry)
        expectOnlyB = false
    end
end

if expectOnlyB and #runLog == 1 and runLog[1] == "b-1:3" then
    print("\n========== PASS: No stale effects leaked ==========")
    print("  Queue was properly cleaned up after flush error")
elseif hasStaleA then
    print("\n========== FAIL: Stale effects leaked! ==========")
    print("  Effects depending on 'a' ran when only 'b' changed")
    print("  Queue was NOT cleaned up after flush error")
end

print("\n========== Issue #97 Test Complete ==========")
