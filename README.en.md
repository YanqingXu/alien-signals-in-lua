# Alien Signals - Lua Reactive Programming System

[简体中文 README](README.md)

## Introduction

Alien Signals is an efficient reactive programming system implemented in Lua, inspired by reactive systems in modern frontend frameworks like Vue and React. It provides automatic dependency tracking and reactive data flow management capabilities for Lua applications through a clean and powerful API.

## Core Concepts

1. Signal
   - Used to store and track reactive values
   - Automatically notifies dependent computed properties and effects when values change
   - Read and write values directly via function calls

2. Computed
   - Derived values based on other reactive values
   - Recalculated only when dependent values change
   - Automatically caches results to avoid unnecessary recalculations

3. Effect
   - Functions automatically executed when reactive values change
   - Used to handle side effects, such as updating UI, sending network requests, etc.
   - Supports cleanup and unsubscription

4. EffectScope
   - Used to batch manage and clean up multiple reactive effect functions
   - Simplifies memory management in complex systems
   - Supports nested scope structures

## Usage Example

```lua
local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local effectScope = reactive.effectScope

-- Create reactive values
local count = signal(0)
local doubled = computed(function()
    return count() * 2
end)

-- Create an effect
local stopEffect = effect(function()
    print("Count:", count())
    print("Doubled:", doubled())
end)
-- Output: Count: 0, Doubled: 0

-- Modify values, which will automatically trigger related computations and effects
count(1)  -- Output: Count: 1, Doubled: 2
count(2)  -- Output: Count: 2, Doubled: 4

-- Stop effect listening
stopEffect()
count(3)  -- Won't trigger any output

-- Using effect scope
local cleanup = effectScope(function()
    -- All effect functions created within this scope
    effect(function()
        print("Scoped effect:", count())
    end)
    
    effect(function()
        print("Another effect:", doubled())
    end)
end)

count(4)  -- Triggers all effect functions in the scope
cleanup()  -- Cleans up all effect functions in the scope
count(5)  -- Won't trigger any output
```

## Advanced Features

### Batch Updates

When performing multiple state updates, you can use batch update mode to avoid triggering effects multiple times, improving performance.

```lua
local reactive = require("reactive")
local signal = reactive.signal
local effect = reactive.effect
local startBatch = reactive.startBatch
local endBatch = reactive.endBatch

local count = signal(0)
local multiplier = signal(1)

effect(function()
    print("Result:", count() * multiplier())
end)
-- Output: Result: 0

-- Without batch updates: the effect executes twice
count(5) -- Output: Result: 5
multiplier(2) -- Output: Result: 10

-- With batch updates: the effect executes only once
startBatch()
count(10)
multiplier(3)
endBatch() -- Output: Result: 30
```

## Implementation Details

The system uses the following techniques to implement reactivity:

1. Dependency Tracking
   - Uses function closures and binding mechanism for the object system
   - Tracks the currently executing computation or effect through global state
   - Automatically collects and manages dependencies, building a reactive data dependency graph

2. Doubly Linked List Dependency Management
   - Uses efficient doubly linked list structure to manage dependencies
   - O(1) time complexity for dependency addition and removal operations
   - Automatically cleans up dependencies that are no longer needed, preventing memory leaks

3. Dirty Value Checking and Optimization
   - Employs efficient bit operations for dirty value checking
   - Intelligently determines when to recalculate derived values
   - Precise dependency graph traversal algorithm

4. Update Scheduling System
   - Uses a queue to manage pending effect functions
   - Intelligently merges multiple updates to reduce unnecessary computations
   - Supports batch updates to improve performance

## Considerations

1. Performance Optimization
   - Avoid accessing too many reactive values in a single computed property
   - Use batch updates judiciously to improve performance
   - Don't modify other reactive values inside computed properties

2. Circular Dependencies
   - Although the system can intelligently handle some circular dependencies
   - It's still recommended to avoid complex circular dependencies
   - Uses bit flags to prevent infinite recursion and stack overflow

3. Memory Management
   - System automatically manages dependency relationships
   - Effects no longer in use are automatically cleaned up
   - Use effectScope to manage multiple effects in complex components

## Complete API Reference

```lua
local reactive = require("reactive")

-- Core APIs
local signal = reactive.signal       -- Create a reactive signal
local computed = reactive.computed   -- Create a computed property
local effect = reactive.effect       -- Create an effect
local effectScope = reactive.effectScope  -- Create an effect scope

-- Batch processing APIs
local startBatch = reactive.startBatch  -- Start batch updates
local endBatch = reactive.endBatch      -- End batch updates and execute updates
```

## License

This project is licensed under the [LICENSE](LICENSE).
