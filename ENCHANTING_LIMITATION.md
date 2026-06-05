# Enhanced Enchanting Feature - API Status

## Status: Implemented for OpenMW 0.51 RC

> **History:** This document previously stated that custom enchanting was *impossible*
> due to OpenMW Lua API limitations (written against OpenMW 0.49, 2025-01-08). **That is
> no longer true.** OpenMW 0.51 RC exposes the required runtime record APIs, and
> this document now describes the implementation used by this mod.

## What is now possible

OpenMW Lua now provides everything needed to create and assign enchantments at runtime:

1. **Create new enchantment records at runtime**
   - `core.magic.enchantments.createRecordDraft(...)` builds an Enchantment draft
     (`type`, `isAutocalc`, `cost`, `charge`, `effects`).
   - `world.createRecord(draft)` registers it and returns the record with a generated id.
   - `core.magic.enchantments.records` is still read-only for *listing*, but you no longer
     need to mutate it — you register new records instead.

2. **Assign enchantments to items**
   - `WeaponRecord` / `ArmorRecord` / `ClothingRecord` expose a writable `enchant` field
     and a `createRecordDraft`. Derive a record from the item with `enchant = "<id>"`
     (or `enchant = ""` to clear it) and swap the inventory item.

3. **Effect shape** — each entry in an enchantment's `effects` list is a
   `MagicEffectWithParams`: `id`, `magnitudeMin`, `magnitudeMax`, `duration`, `range`,
   `area`, and optional `affectedSkill` / `affectedAttribute`.

### API references

| API | Location |
|-----|----------|
| `core.magic.enchantments.createRecordDraft` | `core.lua:722` |
| `world.createRecord` supports `Enchantment` | `world.lua:180` |
| Effect table shape (`MagicEffectWithParams`) | `core.lua:789` |
| Writable `enchant` field + `createRecordDraft` (Weapon/Armor/Clothing) | `types.lua:2019, 1496, 1693` |
| Enchantment types (`ENCHANTMENT_TYPE`) | `core.lua:395` |

## Implementation pattern

Both adding and removing enchantments follow the **same record-swap pattern the mod
already ships** in `upgradeItemCapacity` (`scripts/enchantmachine/global.lua:290`):

```lua
-- Runs in the GLOBAL context (world.* APIs). PLAYER sends an event, just like
-- EnchantMachine_UpgradeItem / _RechargeItem / _DepositGem.

-- Remove an enchantment:
local draft = typeMod.createRecordDraft({ template = record, enchant = "" })

-- Apply an existing enchantment:
local draft = typeMod.createRecordDraft({ template = record, enchant = existingEnchantId })

-- Create + apply a custom enchantment:
local enchDraft = core.magic.enchantments.createRecordDraft({
    type = core.magic.ENCHANTMENT_TYPE.ConstantEffect, -- or CastOnStrike / CastOnUse / CastOnce
    isAutocalc = false, cost = cost, charge = charge,
    effects = {
        { id = "fortifyhealth", magnitudeMin = 10, magnitudeMax = 10,
          duration = 0, range = 0, area = 0, affectedAttribute = "health" },
    },
})
local enchId = world.createRecord(enchDraft).id
local draft  = typeMod.createRecordDraft({ template = record, enchant = enchId })

-- Common tail (identical to upgradeItemCapacity):
local newRecordId = world.createRecord(draft).id
local newItem = world.createObject(newRecordId, 1)
-- carry over condition / enchantmentCharge from old itemData
newItem:moveInto(types.Actor.inventory(actor))
item:remove(1)
```

No OpenMW-CS work is required for item enchantment records — this is runtime Lua.

## Current implementation

The mod implements direct Add Enchantment in `scripts/enchantmachine/global.lua`:

1. PLAYER lists known castable spells and sends `EnchantMachine_AddEnchant`.
2. GLOBAL copies the selected spell's effects into a new enchantment record.
3. GLOBAL derives a weapon/armor/clothing record with `enchant = generatedEnchantId`.
4. GLOBAL swaps one inventory item instance to the generated record and charges soul power only after the swap succeeds.

## Implemented today

✅ Soul power banking · soul gem deposit · item recharge · capacity upgrades · settings · debug tools

✅ **Remove Enchantment** — strips an item's enchantment (derived record with `enchant = ""`),
   refunds soul power, and leaves a blank item that can be enchanted via the game's own
   enchanting system or upgraded here. See `removeEnchantment` in
   `scripts/enchantmachine/global.lua`.

✅ **Attune** — resonator menu option that sets a persistent `Attuned` flag, but only while
   the player stands in the Heart of Lorkhan chamber (`Akulakhan's Chamber`); otherwise
   responds "The device failed to attune." See `onAttuneEvent` / `getAttuned` in `global.lua`.

✅ **Add Enchantment** — creates a runtime enchantment from a known player spell and swaps
   a generated item record into the actor inventory. Weapons cast on strike; armor and
   clothing cast on use.

---

**Last Updated:** 2026-06-05
**OpenMW Target:** 0.51 RC
**API Status:** Enchantment creation & assignment implemented; custom summon effects are defined by a LOAD script
