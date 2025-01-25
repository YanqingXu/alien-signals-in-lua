# Alien Signals - Lua Version

[简体中文 README](README.md)

This is a reactive system implemented in Lua, providing reactive programming capabilities similar to modern frontend frameworks.

## Core Concepts

1. Signal
   - Used to store and track reactive values
   - Automatically notifies dependent computed properties and effects when values change

2. Computed
   - Derived values based on other reactive values
   - Recalculated only when dependent values change

3. Effect
   - Functions automatically executed when reactive values change
   - Used to handle side effects, such as updating UI, sending network requests, etc.

## Usage Example

```lua
local signal = require 'signal'
local computed = require 'computed'
local effect = require 'effect'

-- Create reactive values
local count = signal.signal(0)
local doubled = computed.computed(function()
    return count:get() * 2
end)

-- Create an effect
effect.effect(function()
    print("Count:", count:get())
    print("Doubled:", doubled:get())
end)

-- Modify values, which will automatically trigger related computations and effects
count:set(1)  -- Output: Count: 1, Doubled: 2
count:set(2)  -- Output: Count: 2, Doubled: 4
```

## Implementation Details

The system uses the following techniques to implement reactivity:

1. Dependency Tracking
   - Implements object system using Lua's metatables
   - Tracks the currently executing computation or effect through global state
   - Automatically collects and manages dependencies

2. Batch Updates
   - Supports batch updates to improve performance
   - Uses a queue to manage pending effects

3. Dirty Value Checking
   - Intelligent dirty value checking mechanism
   - Recalculates derived values only when necessary

## Considerations

1. Performance
   - Avoid accessing too many reactive values in a single computed property
   - Use batch updates judiciously to improve performance

2. Memory Management
   - System automatically manages dependency relationships
   - Reactive values no longer in use are automatically cleaned up

## License

MIT License
