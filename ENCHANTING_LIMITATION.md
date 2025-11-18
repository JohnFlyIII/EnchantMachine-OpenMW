

# Enhanced Enchanting Feature - Technical Limitation

## Current Status: Not Implemented

The enhanced enchanting feature (creating custom enchantments with capacity multiplier) is **not currently implemented** due to OpenMW Lua API limitations.

## The Problem

OpenMW Lua (as of version 0.49) does not provide APIs to:

1. **Create new enchantment records at runtime**
   - `world.createRecord()` does not support enchantments
   - `core.magic.enchantments.records` is read-only

2. **Modify existing enchantment records**
   - Enchantment records are immutable
   - Cannot change effects, costs, or charges

3. **Assign enchantments to items dynamically**
   - Item records have `enchant` field but it references existing enchantments only
   - Cannot create item-specific enchantments

## What This Means

Users **cannot**:
- Create new enchantments through the machine UI
- Use the configurable capacity multiplier for enchanting
- Generate custom effect combinations at runtime

Users **can** (as implemented):
- Recharge existing enchanted items
- Upgrade item enchantment capacity permanently
- Deposit souls and manage soul power
- Use all UI and configuration features

## Possible Workarounds

### Option 1: Pre-defined Enchantment Pool (Recommended for Mods)

Create a large pool of enchantments in an ESP/ESM file:
```
enchant_machine_fortify_health_10
enchant_machine_fortify_health_25
enchant_machine_fortify_health_50
... (hundreds of variations)
```

Then the Lua script can:
1. Let user select effects and magnitudes
2. Find closest matching pre-defined enchantment
3. Apply that enchantment to the item

**Pros:**
- Works within current API
- Can provide hundreds of combinations
- Predictable behavior

**Cons:**
- Requires ESP file
- Limited to pre-defined combinations
- Large file size for comprehensive coverage

### Option 2: Wait for OpenMW API Enhancement

The OpenMW team may add enchantment creation APIs in future versions. This feature is logged as a wishlist item.

**Pros:**
- True dynamic enchanting
- No ESP required
- Full flexibility

**Cons:**
- Uncertain timeline
- Requires OpenMW update
- Not available now

### Option 3: Simulation via ItemData (Hacky)

Store "virtual enchantments" in item data and intercept spell casting events to apply effects manually.

**Pros:**
- Works now
- Some flexibility

**Cons:**
- Very complex implementation
- May not integrate well with game systems
- Potential bugs and edge cases
- Performance concerns

## Recommendation

For mod developers who want enchanting functionality:

1. **Use Option 1** - Create an ESP with pre-defined enchantments
2. **Design UI** to let users select:
   - Effect type (Fortify Attribute, Resist Element, etc.)
   - Magnitude tier (Small, Medium, Large, Epic)
   - Duration (Constant Effect, Cast on Strike, etc.)
3. **Map selections** to closest pre-defined enchantment
4. **Apply enchantment** using the Lua API (if it becomes available)

## Example Implementation Sketch

```lua
-- Pre-defined enchantment database (references ESP records)
local ENCHANTMENT_POOL = {
    {
        id = "em_fortify_health_const_10",
        effects = {"Fortify Health"},
        magnitude = 10,
        duration = 0, -- Constant
        cost = 1000,
    },
    -- ... hundreds more
}

function findBestMatchingEnchantment(selectedEffects, targetMagnitude)
    -- Find closest match from ENCHANTMENT_POOL
    -- Return enchantment ID
end

function applyEnchantment(item, enchantmentId)
    -- If API available: item.record.enchant = enchantmentId
    -- Currently: Not possible
end
```

## Future Plans

This feature will be reconsidered when:
1. OpenMW adds enchantment creation APIs
2. Community develops standard enchantment pools
3. Alternative implementations prove viable

## Current Feature Status

✅ **Implemented:**
- Soul power banking
- Soul gem deposit
- Item recharge
- Capacity upgrades
- Settings system
- Debug/testing tools

❌ **Not Implemented (API Limitation):**
- Custom enchantment creation
- Capacity multiplier usage for enchanting
- Dynamic effect selection

## Questions?

For technical questions or to track API developments:
- OpenMW Forums: https://forum.openmw.org/
- OpenMW GitLab: https://gitlab.com/OpenMW/openmw
- Lua API Docs: https://openmw.readthedocs.io/

## Contributing

If you discover a workaround or OpenMW adds relevant APIs:
1. Test thoroughly in OpenMW
2. Document the approach
3. Submit a PR or issue

---

**Last Updated:** 2025-01-08
**OpenMW Version Tested:** 0.49
**API Status:** Enchantment creation not supported
