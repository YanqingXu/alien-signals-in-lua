# Alien Signals - Lua Version

[简体中文 README](README.md)

This is a reactive system implemented in Lua, providing reactive programming capabilities similar to modern frontend frameworks. It offers a clean API for reactive data flow management and automatic dependency tracking.

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

## Usage Example

```lua
local signal = require 'signal'
local computed = require 'computed'
local effect = require 'effect'

-- Create reactive values
local count = signal.signal(0)
local doubled = computed.computed(function()
    return count() * 2
end)

-- Create an effect
local stopEffect = effect.effect(function()
    print("Count:", count())
    print("Doubled:", doubled())
end)

-- Modify values, which will automatically trigger related computations and effects
count(1)  -- Output: Count: 1, Doubled: 2
count(2)  -- Output: Count: 2, Doubled: 4

-- Stop effect listening
stopEffect()
count(3)  -- Won't trigger any output

-- Using effect scope
local cleanup = effect.effectScope(function()
    -- All effect functions created within this scope
    effect.effect(function()
        print("Scoped effect:", count())
    end)
    
    effect.effect(function()
        print("Another effect:", doubled())
    end)
end)

count(4)  -- Triggers all effect functions in the scope
cleanup()  -- Cleans up all effect functions in the scope
count(5)  -- Won't trigger any output
```

## Implementation Details

The system uses the following techniques to implement reactivity:

1. Dependency Tracking
   - Uses function closures and binding mechanism for object system
   - Tracks the currently executing computation or effect through global state
   - Automatically collects and manages dependencies, building a reactive data dependency graph

2. Doubly Linked List Dependency Management
   - Uses efficient doubly linked list structure to manage dependencies
   - O(1) time complexity for dependency addition and removal operations
   - Automatically cleans up dependencies that are no longer needed, preventing memory leaks

3. Batch Updates
   - Supports batch updates to improve performance
   - Uses a queue to manage pending effect functions
   - Intelligently merges multiple updates to reduce unnecessary computations

4. Dirty Value Checking
   - Employs efficient bit operations for dirty value checking
   - Recalculates derived values only when necessary
   - Precise dependency graph traversal algorithm

## Advanced Features

1. Batch Operations
   ```lua
   global.startBatch()
   -- Multiple signal value changes, won't trigger effect functions immediately
   count(10)
   count(20)
   count(30)
   global.endBatch() -- Triggers effect functions just once here
   ```

2. Handling Circular Dependencies
   - System can intelligently handle circular dependencies between reactive values
   - Uses flags to prevent infinite recursion and stack overflow

## Considerations

1. Performance
   - Avoid accessing too many reactive values in a single computed property
   - Use batch updates judiciously to improve performance
   - Don't modify other reactive values inside computed properties

2. Memory Management
   - System automatically manages dependency relationships
   - Reactive values no longer in use are automatically cleaned up
   - Use effectScope to manage effect functions in complex components

## License

MIT License
