# Alien Signals - Lua Reactive Programming System

[简体中文 README](README.md)

## Introduction

This project is ported from [stackblitz/alien-signals](https://github.com/stackblitz/alien-signals), and is a Lua implementation of the original TypeScript reactive system.

Alien Signals is an efficient reactive programming system. It provides automatic dependency tracking and reactive data flow management capabilities for applications through a clean and powerful API.

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

## Linked List Structure In Detail

The core of Alien Signals is a dependency tracking system implemented using doubly-linked list structures. Each link node exists simultaneously in two different linked lists, enabling efficient dependency collection and notification propagation.

### Link Node Structure

Each link node contains the following fields:

```lua
{
    dep = dep,        -- Dependency object (Signal or Computed)
    sub = sub,        -- Subscriber object (Effect or Computed)
    prevSub = prevSub, -- Previous node in the subscriber chain
    nextSub = nextSub, -- Next node in the subscriber chain
    prevDep = prevDep, -- Previous node in the dependency chain
    nextDep = nextDep  -- Next node in the dependency chain
}
```

### Doubly Linked List Diagram

The linked list structure in the system can be represented as follows:

```
Dependency Relationship Structure:

+-------------+          +--------------+          +--------------+
|    Signal   |          |   Computed   |          |    Effect    |
| (Data Source)|         | (Derived Value)|        | (Side Effect) |
+-------------+          +--------------+          +--------------+
       ^                        ^                         ^
       |                        |                         |
       |                        |                         |
       v                        v                         v
+-----------------+    +-----------------+    +-----------------+
|Subscriber Chain |    |Subscriber Chain |    |Subscriber Chain |
|   (Vertical)    |    |   (Vertical)    |    |   (Vertical)    |
+-----------------+    +-----------------+    +-----------------+
       ^                        ^                         ^
       |                        |                         |
       |                        |                         |
+======================================================================================================================+
|                                            Link Node                                                                 |
+======================================================================================================================+
       |                        |                         |
       |                        |                         |
       v                        v                         v
+-----------------+    +-----------------+    +-----------------+
| Dependency Chain|    | Dependency Chain|    | Dependency Chain|
|  (Horizontal)   |    |  (Horizontal)   |    |  (Horizontal)   |
+-----------------+    +-----------------+    +-----------------+
```

### Link Process

When a reactive object (like Signal or Computed) is accessed, the system establishes a dependency relationship between it and the currently active effect:

1. Checks for duplicate dependencies to avoid adding the same dependency multiple times
2. Handles circular dependency cases to prevent infinite recursion
3. Creates a new link node and inserts it into both chains
4. Updates the previous and next pointers of the doubly-linked lists to ensure the complete list structure

```
Initial state:
Signal A     Effect 1
 subs=nil     deps=nil
 
Execute reactive.link(Signal A, Effect 1):

Create new link node:
+-------------------+
| Link {            |
|   dep = Signal A  |
|   sub = Effect 1  |
|   prevSub = nil   |
|   nextSub = nil   |
|   prevDep = nil   |
|   nextDep = nil   |
| }                 |
+-------------------+

Update Signal A and Effect 1:
Signal A            Effect 1
 subs=Link           deps=Link
 subsTail=Link       depsTail=Link
```

### Unlink Process

When a dependency relationship is no longer needed (e.g., when an effect is cleaned up or re-executed without needing a specific dependency), the system removes these relationships:

1. Removes the link node from the dependency chain (horizontal direction)
2. Removes the link node from the subscriber chain (vertical direction)
3. Handles special cases, like cleanup when the last subscriber is removed

```
Initial state:
Signal A                 Effect 1
 subs=Link                deps=Link
 subsTail=Link            depsTail=Link
 
   +-------------------+
   | Link {            |
   |   dep = Signal A  |
   |   sub = Effect 1  |
   |   prevSub = nil   |
   |   nextSub = nil   |
   |   prevDep = nil   |
   |   nextDep = nil   |
   | }                 |
   +-------------------+

Execute reactive.unlink(Link, Effect 1):

Remove link:
Signal A           Effect 1
 subs=nil           deps=nil
 subsTail=nil       depsTail=nil
```

### Complex Scenario Example

In practical applications, the dependency relationship network can be very complex:

```
Signal A ---> Effect 1 ---> Signal B ---> Effect 2
    |                           |
    |                           v
    +----------------------> Computed C ---> Effect 3
                               |
                               v
                            Signal D
```

This complex dependency relationship is efficiently managed through the doubly-linked list structure, achieving O(1) time complexity for dependency operations.

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

4. Lua 5.1 Compatibility
   - Supports Lua 5.1 which doesn't have __pairs and __ipairs metamethods
   - Use HybridReactive.pairs and HybridReactive.ipairs instead of standard pairs/ipairs
   - All examples and tests are compatible with both Lua 5.1 and newer versions

## Complete API Reference

```lua
local reactive = require("reactive")

-- Core APIs
local reactive = reactive.reactive   -- Create a reactive object
local computed = reactive.computed   -- Create a computed property
local effectScope = reactive.effectScope  -- Create an effect scope

-- Batch processing APIs
local startBatch = reactive.startBatch  -- Start batch updates
local endBatch = reactive.endBatch      -- End batch updates and execute updates

```

## License

This project is licensed under the [LICENSE](LICENSE).
