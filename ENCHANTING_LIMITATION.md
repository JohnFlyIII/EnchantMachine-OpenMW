# Enhanced Enchanting Feature - API Status

## Status: Now Supported (API verified, runtime test pending)

> **History:** This document previously stated that custom enchanting was *impossible*
> due to OpenMW Lua API limitations (written against OpenMW 0.49, 2025-01-08). **That is
> no longer true.** As of OpenMW Lua **API revision 131** the required APIs exist, and
> this document was rewritten on 2026-06-01 to reflect that.

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

### API references (OpenMW source, rev 131)

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

No OpenMW-CS / `.omwaddon` work is required — this is pure Lua.

## Remaining unknown (needs one in-game test)

The API *surface* is confirmed; runtime *behavior* has **not** yet been verified in-game.
Before building a custom-effect UI, run one throwaway test to answer:

1. Does the engine enforce **"enchantment cost ≤ item `enchantCapacity`"** for
   runtime-assigned enchantments, or accept any cost? (This determines how the existing
   `enchantMultiplier` / soul-power economy plugs in.)
2. Does an assigned custom enchantment actually **function** — charge drains correctly,
   cast-on-strike/use fires, constant effect applies, and it shows in the item tooltip?

## Suggested rollout

| Feature | Risk | Notes |
|---------|------|-------|
| Remove Enchantment | Low | Near-copy of the upgrade handler |
| Add — *existing* enchantment | Low | Derive with `enchant = <id>` + a simple list menu |
| Add — *custom* enchantment | Medium | UI-heavy (flat button menus, no MWUI scroll container); do the runtime test first |

## Implemented today

✅ Soul power banking · soul gem deposit · item recharge · capacity upgrades · settings · debug tools

✅ **Remove Enchantment** — strips an item's enchantment (derived record with `enchant = ""`),
   refunds soul power, and leaves a blank item that can be enchanted via the game's own
   enchanting system or upgraded here. See `removeEnchantment` in
   `scripts/enchantmachine/global.lua`.

✅ **Attune** — resonator menu option that sets a persistent `Attuned` flag, but only while
   the player stands in the Heart of Lorkhan chamber (`Akulakhan's Chamber`); otherwise
   responds "The device failed to attune." See `onAttuneEvent` / `getAttuned` in `global.lua`.

⏳ **Add Enchantment** — wired to open the engine's native enchanting window
   (`I.UI.addMode('Enchanting')`) so the player picks from known spells with vanilla cost
   rules. **Pending in-game verification** that the mode opens a usable self-enchant window
   (and the soul-gem requirement, since this mod banks souls as abstract power). Remove
   already unblocks the vanilla enchanting path regardless.

---

**Last Updated:** 2026-06-01
**OpenMW Lua API Revision Verified:** 131 (source clone 2026-05-27)
**API Status:** Enchantment creation & assignment supported; Remove Enchantment + Attune implemented; native Add-Enchantment menu pending in-game test
