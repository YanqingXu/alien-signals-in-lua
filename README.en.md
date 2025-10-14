# Alien Signals - Lua Reactive Programming System

**Version: 3.0.0** - Compatible with alien-signals v3.0.0

[简体中文 README](README.md)

## Introduction

This project is ported from [stackblitz/alien-signals](https://github.com/stackblitz/alien-signals), and is a Lua implementation of the original TypeScript reactive system.

Alien Signals is an efficient reactive programming system. It provides automatic dependency tracking and reactive data flow management capabilities for applications through a clean and powerful API.

### New Features in v3.0.0

- **Type Detection Functions**: Added runtime type checking functions - `isSignal`, `isComputed`, `isEffect`, `isEffectScope`
- **New Getters**: Added `getBatchDepth` and `getActiveSub` for querying reactive context state
- **API Renames**: Renamed `setCurrentSub`→`setActiveSub`, `getCurrentSub`→`getActiveSub` for clearer semantics
- **Removed Deprecated APIs**: Removed `pauseTracking`/`resumeTracking`, `setCurrentScope`/`getCurrentScope`
- **Computed Optimization**: Removed initial Dirty flag, added fast path for first computation
- **Internal Optimizations**: Removed `startTracking`/`endTracking`, inlined tracking logic for better performance
- **Link Enhancement**: Added third parameter support to `link` function for more flexible dependency management
- **Pending Flag Cleanup**: Inlined pending flag clearing logic for reduced function call overhead

> ⚠️ **Breaking Changes**: This is a major version update. Please refer to [UPGRADE_TO_3.0.0.md](UPGRADE_TO_3.0.0.md) for migration guide.

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

## HybridReactive - Vue.js Style API

In addition to the low-level reactive system, this project also provides a Vue.js-like high-level reactive API - HybridReactive, which offers a more friendly and intuitive interface.

### Core APIs

- `ref(value)` - Create reactive reference
- `reactive(obj, shallow)` - Convert object to reactive object (supports deep/shallow reactivity)
- `computed(fn)` - Create computed property

### Watching APIs

- `watch(callback)` - Watch reactive data changes
- `watchRef(ref, callback)` - Watch ref object changes
- `watchReactive(reactive, callback, shallow)` - Watch reactive object property changes

### Utility Functions

- `isRef(value)` - Check if value is a ref object
- `isReactive(value)` - Check if value is a reactive object

### Basic Usage

```lua
local HybridReactive = require("HybridReactive")

-- Create reactive reference
local count = HybridReactive.ref(0)
local name = HybridReactive.ref("Alice")

-- Access and modify values
print(count.value)  -- 0
count.value = 10
print(count.value)  -- 10

-- Create computed property
local doubled = HybridReactive.computed(function()
    return count.value * 2
end)

print(doubled.value)  -- 20

-- Create reactive object
local state = HybridReactive.reactive({
    user = "Bob",
    age = 25
})

print(state.user)  -- Bob
state.age = 30
print(state.age)   -- 30
```

### `reactive(obj, shallow)`

Convert a plain object to a reactive object.

**Parameters:**
- `obj`: Object to convert
- `shallow`: Optional boolean, defaults to `false`
  - `false` (default): Deep reactivity, nested objects are also converted to reactive
  - `true`: Shallow reactivity, only first-level properties are reactive

**Deep Reactivity (default behavior):**
```lua
local obj = HybridReactive.reactive({
    user = {
        name = "Alice",
        profile = {
            age = 25,
            address = { city = "Beijing" }
        }
    }
})

-- All nested objects are reactive
print(HybridReactive.isReactive(obj.user))                    -- true
print(HybridReactive.isReactive(obj.user.profile))           -- true
print(HybridReactive.isReactive(obj.user.profile.address))   -- true

-- Can watch changes at any level
obj.user.name = "Bob"                    -- Triggers reactive update
obj.user.profile.age = 30                -- Triggers reactive update
obj.user.profile.address.city = "Shanghai"  -- Triggers reactive update
```

**Shallow Reactivity:**
```lua
local obj = HybridReactive.reactive({
    user = { name = "Alice", age = 25 },
    settings = { theme = "light" }
}, true)  -- shallow = true

-- Only first level is reactive
print(HybridReactive.isReactive(obj.user))     -- false
print(HybridReactive.isReactive(obj.settings)) -- false

-- Can only watch first-level changes
obj.user = { name = "Bob", age = 30 }      -- Triggers reactive update
obj.user.name = "Charlie"                  -- Won't trigger reactive update (user is not reactive)
```

### watchRef - Watch ref object changes

`watchRef` is a function specifically designed to watch ref object changes. It calls the callback function when the ref's value changes, providing both new and old values as parameters.

#### Syntax

```lua
local stopWatching = HybridReactive.watchRef(refObj, callback)
```

- `refObj`: The ref object to watch
- `callback`: Callback function that receives `(newValue, oldValue)` parameters
- Return value: Function to stop watching

#### Usage Example

```lua
local HybridReactive = require("HybridReactive")

-- Watch number changes
local counter = HybridReactive.ref(0)

local stopWatching = HybridReactive.watchRef(counter, function(newValue, oldValue)
    print(string.format("Counter changed from %d to %d", oldValue, newValue))
end)

counter.value = 1  -- Output: Counter changed from 0 to 1
counter.value = 5  -- Output: Counter changed from 1 to 5
counter.value = 5  -- Won't trigger callback (value unchanged)

-- Stop watching
stopWatching()
counter.value = 10 -- Won't trigger callback
```

### watchReactive - Watch reactive object changes

`watchReactive` is a function specifically designed to watch reactive object property changes. It calls the callback function when any property of the reactive object changes.

#### Syntax

```lua
local stopWatching = HybridReactive.watchReactive(reactiveObj, callback, shallow)
```

- `reactiveObj`: The reactive object to watch
- `callback`: Callback function that receives `(key, newValue, oldValue, path)` parameters
- `shallow`: Optional boolean, defaults to `false`
  - `false` (default): Deep watching, recursively watch nested object changes
  - `true`: Shallow watching, only watch first-level property changes
- Return value: Function to stop watching

#### Basic Usage Example

```lua
local HybridReactive = require("HybridReactive")

-- Create reactive object
local user = HybridReactive.reactive({
    name = "Alice",
    age = 25,
    profile = {
        email = "alice@example.com",
        settings = {
            theme = "light"
        }
    }
})

-- Deep watching (default)
local stopWatching = HybridReactive.watchReactive(user, function(key, newValue, oldValue, path)
    print(string.format("Property '%s' at path '%s' changed from '%s' to '%s'",
          key, path or key, tostring(oldValue), tostring(newValue)))
end)

user.name = "Bob"                           -- Output: Property 'name' at path 'name' changed from 'Alice' to 'Bob'
user.profile.email = "bob@example.com"      -- Output: Property 'email' at path 'profile.email' changed from 'alice@example.com' to 'bob@example.com'
user.profile.settings.theme = "dark"       -- Output: Property 'theme' at path 'profile.settings.theme' changed from 'light' to 'dark'

-- Stop watching
stopWatching()
user.name = "Charlie"  -- Won't trigger callback
```

#### Shallow vs Deep Watching

```lua
local obj = HybridReactive.reactive({
    user = {
        name = "Alice",
        profile = { age = 25 }
    }
})

-- Shallow watching
local stopShallow = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print("Shallow watch:", key, path)
end, true)  -- shallow = true

-- Deep watching
local stopDeep = HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print("Deep watch:", key, path)
end, false)  -- shallow = false

-- Replace entire user object (both will trigger)
obj.user = { name: "Bob", profile: { age: 30 } }
-- Output:
-- Shallow watch: user user
-- Deep watch: user user

-- Modify nested property (only deep watch will trigger)
obj.user.name = "Charlie"
-- Output:
-- Deep watch: name user.name

obj.user.profile.age = 35
-- Output:
-- Deep watch: age user.profile.age

stopShallow()
stopDeep()
```

#### Same Property Names at Different Levels

`watchReactive` can accurately distinguish same property names at different levels:

```lua
local obj = HybridReactive.reactive({
    name = "root-name",           -- Root level name
    user = {
        name = "user-name",       -- User level name
        profile = {
            name = "profile-name" -- Profile level name
        }
    }
})

HybridReactive.watchReactive(obj, function(key, newValue, oldValue, path)
    print(string.format("Property '%s' at path '%s' changed", key, path))
end, false)

obj.name = "new-root-name"                    -- Output: Property 'name' at path 'name' changed
obj.user.name = "new-user-name"              -- Output: Property 'name' at path 'user.name' changed
obj.user.profile.name = "new-profile-name"   -- Output: Property 'name' at path 'user.profile.name' changed
```

### Advanced Features

#### Batch Updates

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

### v3.0.0 New Features

#### Type Detection Functions

v3.0.0 added runtime type detection functions to check if a value is a specific reactive primitive:

```lua
local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect
local effectScope = reactive.effectScope

-- Create reactive primitives
local count = signal(0)
local doubled = computed(function() return count() * 2 end)
local stopEffect = effect(function() print(count()) end)
local stopScope = effectScope(function() end)

-- Type detection
print(reactive.isSignal(count))        -- true
print(reactive.isSignal(doubled))      -- false

print(reactive.isComputed(doubled))    -- true
print(reactive.isComputed(count))      -- false

print(reactive.isEffect(stopEffect))   -- true
print(reactive.isEffectScope(stopScope)) -- true
```

#### Querying Reactive Context State

v3.0.0 added functions to query the current reactive context:

```lua
local reactive = require("reactive")
local signal = reactive.signal
local effect = reactive.effect

-- Get batch update depth
print(reactive.getBatchDepth())  -- 0

reactive.startBatch()
print(reactive.getBatchDepth())  -- 1

reactive.startBatch()
print(reactive.getBatchDepth())  -- 2

reactive.endBatch()
print(reactive.getBatchDepth())  -- 1

reactive.endBatch()
print(reactive.getBatchDepth())  -- 0

-- Get current active subscriber
local count = signal(0)
print(reactive.getActiveSub() == nil)  -- true

effect(function()
    count()
    -- Inside effect, getActiveSub returns current effect
    local sub = reactive.getActiveSub()
    print(sub ~= nil)  -- true
end)

-- Outside effect
print(reactive.getActiveSub() == nil)  -- true
```

#### API Renames

For clearer semantics, v3.0.0 renamed some APIs:

```lua
-- v2.0.7 (old API)
local prevSub = reactive.setCurrentSub(nil)
reactive.setCurrentSub(prevSub)

-- v3.0.0 (new API)
local prevSub = reactive.setActiveSub(nil)
reactive.setActiveSub(prevSub)
```

> ⚠️ **Important**: `pauseTracking`/`resumeTracking` and `setCurrentScope`/`getCurrentScope` have been removed in v3.0.0.
> To pause tracking, use `setActiveSub(nil)` instead.



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
   - Supports Lua 5.1
   - All examples and tests are compatible with both Lua 5.1 and newer versions

## HybridReactive Test Suite

To ensure the stability and correctness of HybridReactive functionality, the project provides a comprehensive test suite.

### Test Files

- **`test_hybrid_reactive.lua`** - Comprehensive test suite containing all HybridReactive functionality tests
- **`run_hybrid_reactive_tests.lua`** - Dedicated test runner

### Running Tests

```bash
# Run the complete HybridReactive test suite
lua run_hybrid_reactive_tests.lua

# Or run the test file directly
lua test_hybrid_reactive.lua
```

### Test Coverage

The test suite is divided into **6 main sections** with **17 comprehensive test cases**:

#### 1. Basic Functionality Tests
- Basic callback functionality verification
- Shallow vs deep watching tests
- Multiple watchers working together
- Watcher lifecycle management

#### 2. Path Tracking and Same Key Tests
- Distinguishing same property names at different levels (`obj.name` vs `obj.user.name`)
- Deep nested path accuracy verification

#### 3. Advanced Feature Tests
- Deep watching after object replacement
- Mixed data type handling
- Batch operation support

#### 4. Error Handling and Edge Cases
- Invalid parameter error handling
- Circular reference scenario stability

#### 5. Performance Tests
- Large object performance (500+ properties)
- Deep nesting performance (20+ levels)
- Multiple watcher performance (50+ watchers)

#### 6. Integration Tests
- Integration with `ref` objects
- Stress testing with rapid consecutive modifications

### Performance Benchmarks

Performance in standard test environment:
- **500-property object setup**: ~2ms
- **50 watcher setup**: ~1ms
- **100 rapid modifications**: ~2ms
- **20-level deep nesting**: ~1ms

### Test Result Example

```
========== Comprehensive HybridReactive.watchReactive Test Suite ==========

SECTION 1: Basic Functionality Tests
=====================================
[OK] Basic callback functionality
[OK] Shallow vs deep monitoring
[OK] Multiple watchers on same object
[OK] Watcher lifecycle and cleanup

SECTION 2: Path Tracking and Same Key Tests
============================================
[OK] Same key at different levels
[OK] Path tracking accuracy

... (other sections)

[OK] ALL WATCHREACTIVE TESTS COMPLETED SUCCESSFULLY! [OK]
```

## Complete API Reference

### Low-level Reactive System (reactive.lua) - v3.0.0

```lua
local reactive = require("reactive")

-- Core reactive primitives
local signal = reactive.signal           -- Create reactive signal
local computed = reactive.computed       -- Create computed value
local effect = reactive.effect           -- Create reactive effect
local effectScope = reactive.effectScope -- Create effect scope

-- Batch operation utilities
local startBatch = reactive.startBatch   -- Start batch updates
local endBatch = reactive.endBatch       -- End batch updates and flush

-- Advanced control API (v3.0.0)
local setActiveSub = reactive.setActiveSub       -- Set current active subscriber (v3.0.0 renamed)
local getActiveSub = reactive.getActiveSub       -- Get current active subscriber (v3.0.0 renamed)
local getBatchDepth = reactive.getBatchDepth     -- Get batch update depth (v3.0.0 new)

-- Type detection API (v3.0.0 new)
local isSignal = reactive.isSignal               -- Check if value is Signal
local isComputed = reactive.isComputed           -- Check if value is Computed
local isEffect = reactive.isEffect               -- Check if value is Effect
local isEffectScope = reactive.isEffectScope     -- Check if value is EffectScope

-- Removed APIs (v3.0.0)
-- ❌ pauseTracking - Use setActiveSub(nil) instead
-- ❌ resumeTracking - Use setActiveSub(prevSub) instead
-- ❌ setCurrentScope - Removed
-- ❌ getCurrentScope - Removed

### HybridReactive - Vue.js Style API (v3.0.0)

```lua
local HybridReactive = require("HybridReactive")

-- Reactive data creation
local ref = HybridReactive.ref           -- Create reactive references
local reactive = HybridReactive.reactive -- Create reactive objects
local computed = HybridReactive.computed -- Create computed properties

-- Watch API
local watch = HybridReactive.watch             -- Generic watch function (alias for effect)
local watchRef = HybridReactive.watchRef       -- Watch ref objects specifically
local watchReactive = HybridReactive.watchReactive -- Watch reactive objects specifically

-- Utility functions
local isRef = HybridReactive.isRef           -- Check if value is a ref object
local isReactive = HybridReactive.isReactive -- Check if value is a reactive object

-- Batch operations (exposed from reactive module)
local startBatch = HybridReactive.startBatch -- Start batch updates
local endBatch = HybridReactive.endBatch     -- End batch updates
```

### v3.0.0 Technical Features

#### Type Marker System
```lua
-- Unique type markers
local SIGNAL_MARKER = {}
local COMPUTED_MARKER = {}
local EFFECT_MARKER = {}
local EFFECTSCOPE_MARKER = {}

-- Type detection implementation
function reactive.isSignal(obj)
    if type(obj) ~= "function" then return false end
    
    -- Check marker in upvalue using debug library
    local i = 1
    while true do
        local name, value = debug.getupvalue(obj, i)
        if not name then break end
        if name == "obj" then
            return value._marker == SIGNAL_MARKER
        end
        i = i + 1
    end
    return false
end
```

#### Optimized Computed Initialization
```lua
-- v3.0.0: Removed Dirty flag, optimized first computation path
function reactive.computed(getter)
    local obj = {
        _getter = getter,
        _value = nil,
        _flags = 0,  -- v3.0.0: Initialize to 0, no longer includes Dirty flag
        _marker = COMPUTED_MARKER
    }
    
    -- First access directly computes
    return function()
        if obj._flags == 0 then
            -- Fast path: first computation
            local success, result = pcall(updateComputed, obj)
            if success then
                return result
            end
        end
        -- ...
    end
end
```

#### Inlined Tracking Optimization
```lua
-- v3.0.0: Removed startTracking/endTracking, directly inlined tracking logic
function run(obj)
    -- Directly inline check and set
    local shouldCleanup = obj._flags & RunningFlags ~= 0
    if shouldCleanup then
        obj._flags = obj._flags | NotifiedFlag
    end
    
    if shouldCleanup then
        purgeDeps(obj)
    end
    
    -- Set active subscriber
    local prevSub = g_activeSub
    g_activeSub = obj
    
    -- Execute side effect
    local status, err = pcall(obj._fn)
    
    -- Restore previous subscriber
    g_activeSub = prevSub
    
    -- Clear flags
    obj._flags = obj._flags & bit.bnot(RunningFlags | NotifiedFlag)
end
```


## HybridReactive Feature Summary

### Core Advantages

1. **Vue.js Style API**: Provides familiar `ref`, `reactive`, `computed` APIs

## HybridReactive Feature Summary

### Core Advantages

1. **Vue.js Style API**: Provides familiar `ref`, `reactive`, `computed` APIs
2. **Deep Reactivity**: Default support for deep nested object reactive conversion
3. **Precise Watching**: `watchReactive` provides precise property change watching and path tracking
4. **High Performance**: Based on efficient doubly-linked list dependency management system
5. **Type Safety**: Strict type checking and error handling
6. **Memory Safety**: Automatic cleanup of unused dependency relationships

### v3.0.0 Enhancements

- **Runtime Type Detection**: Added `isSignal`, `isComputed`, `isEffect`, `isEffectScope` functions
- **Enhanced Context Queries**: Added `getBatchDepth` and `getActiveSub` for better introspection
- **Optimized Performance**: Inlined tracking logic and optimized computed initialization
- **Cleaner API Surface**: Renamed APIs for clarity, removed deprecated functions
- **Cross-Language Portability**: Lua implementation enables usage in game engines and embedded systems
- **Dual API Architecture**: Provides both low-level primitives and high-level Vue.js-style APIs

### Use Cases

- **State Management**: State management and data flow control for complex applications
- **Data Binding**: Implementing two-way data binding between data and views
- **Reactive Computing**: Automatic computation and updates based on data changes
- **Event Systems**: Building event-driven systems based on data changes
- **Caching Systems**: Implementing smart caching and dependency invalidation mechanisms

### Best Practices

1. **Proper use of deep/shallow reactivity**: Choose appropriate reactivity depth based on needs
2. **Utilize path information**: Use `watchReactive`'s path parameter for precise change handling
3. **Timely cleanup of watchers**: Use returned stop functions to cleanup unnecessary watchers
4. **Batch update optimization**: Use `startBatch`/`endBatch` for performance when making many updates
5. **Avoid circular dependencies**: Design reasonable data structures to avoid complex circular dependencies

## License

This project is licensed under the [LICENSE](LICENSE).
