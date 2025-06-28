--[[
 * Shopping Cart Reactive System Example
 * 购物车响应式系统示例
 *
 * This example demonstrates a complex reactive system with multi-level dependencies,
 * batch updates, and side effects as described in the WIKI documentation.
 * 这个示例展示了一个复杂的响应式系统，具有多层依赖、批量更新和副作用，
 * 如 WIKI 文档中所述。
]]

local reactive = require("reactive")
local signal = reactive.signal
local computed = reactive.computed
local effect = reactive.effect

print("=== Shopping Cart Reactive System Demo ===\n")

-- 1. Basic data signals / 基础数据信号
print("1. Creating basic signals")
local itemPrice = signal(100)      -- Item unit price / 商品单价
local quantity = signal(2)         -- Item quantity / 商品数量
local discountRate = signal(0.1)   -- Discount rate / 折扣率
local taxRate = signal(0.08)       -- Tax rate / 税率

-- 2. First-level computed values / 第一层计算值
print("2. Creating first-level computeds")
local subtotal = computed(function()
    print("  -> Computing subtotal")
    return itemPrice() * quantity()
end)

local discountAmount = computed(function()
    print("  -> Computing discountAmount")
    return subtotal() * discountRate()
end)

-- 3. Second-level computed values / 第二层计算值
print("3. Creating second-level computeds")
local afterDiscount = computed(function()
    print("  -> Computing afterDiscount")
    return subtotal() - discountAmount()
end)

local taxAmount = computed(function()
    print("  -> Computing taxAmount")
    return afterDiscount() * taxRate()
end)

-- 4. Final computed value / 最终计算值
print("4. Creating final computed")
local finalTotal = computed(function()
    print("  -> Computing finalTotal")
    return afterDiscount() + taxAmount()
end)

-- 5. Side effect: UI updates / 副作用：UI 更新
print("5. Creating UI effect")
local uiUpdateCount = 0
local stopUIEffect = effect(function()
    local total = finalTotal()
    uiUpdateCount = uiUpdateCount + 1
    print(string.format("  [UI] Update #%d - Total: $%.2f",
                       uiUpdateCount, total))
end)

-- 6. Side effect: Logging / 副作用：日志记录
print("6. Creating log effect")
local stopLogEffect = effect(function()
    print(string.format("  [LOG] Subtotal: $%.2f, Discount: $%.2f",
                       subtotal(), discountAmount()))
end)

print("\n=== Initialization Complete ===")
print("Initial state:")
print(string.format("  Item Price: $%.2f", itemPrice()))
print(string.format("  Quantity: %d", quantity()))
print(string.format("  Discount Rate: %.1f%%", discountRate() * 100))
print(string.format("  Tax Rate: %.1f%%", taxRate() * 100))

-- Test single update / 测试单个更新
print("\n=== Test 1: Single Update - Quantity Change ===")
print("Updating quantity from 2 to 3")
quantity(3)

-- Test batch update / 测试批量更新
print("\n=== Test 2: Batch Update - Price and Discount ===")
print("Starting batch update")
reactive.startBatch()

print("Updating item price from $100 to $120")
itemPrice(120)

print("Updating discount rate from 10% to 15%")
discountRate(0.15)

print("Ending batch update (effects will run now)")
reactive.endBatch()

-- Test multiple quick updates / 测试多个快速更新
print("\n=== Test 3: Multiple Quick Updates ===")
print("Testing rapid updates with batching")

reactive.startBatch()
print("Batch: quantity 3->4->5, price $120->$110->$130")
quantity(4)
quantity(5)
itemPrice(110)
itemPrice(130)
reactive.endBatch()

-- Final state / 最终状态
print("\n=== Final State Summary ===")
print(string.format("Item Price: $%.2f", itemPrice()))
print(string.format("Quantity: %d", quantity()))
print(string.format("Subtotal: $%.2f", subtotal()))
print(string.format("Discount (%.1f%%): $%.2f",
                   discountRate() * 100, discountAmount()))
print(string.format("After Discount: $%.2f", afterDiscount()))
print(string.format("Tax (%.1f%%): $%.2f",
                   taxRate() * 100, taxAmount()))
print(string.format("Final Total: $%.2f", finalTotal()))
print(string.format("Total UI Updates: %d", uiUpdateCount))

-- Cleanup / 清理
print("\n=== Cleanup ===")
print("Stopping effects")
stopUIEffect()
stopLogEffect()

print("\nDemo completed!")
