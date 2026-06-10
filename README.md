# Dwemer Enchanting Machine

A powerful OpenMW 0.51 RC mod that enables direct Lua enchanting, soul-power banking, item upgrades, and custom creature summons through a mysterious Dwemer artifact.

## What This Mod Does

Defeat a unique boss to obtain an ancient **Dwemer puzzle box** that lets you:
1. **Bank soul power** from filled soul gems
2. **Recharge enchanted items** anywhere, anytime
3. **Upgrade unenchanted items** to have massively increased enchantment capacity
4. **Add enchantments directly** from your known spells
5. **Mark creatures** and learn a custom `Summon {creature}` spell when the marked creature dies

The result: Create enchanted items with 10x, 50x, or even 100x the normal capacity - limited only by your soul power reserves.

## Features

### Core System ✅
- **Story-Driven Discovery**: Defeat a unique boss encounter in vanilla Dwemer ruins to obtain the Remote
- **Remote Control Device**: Ancient Dwemer puzzle box that opens the machine interface from anywhere
- **Soul Power Bank**: Deposit filled soul gems to extract and store their soul power globally
  - **Deposit All** empties every filled gem in one click, with a total-power preview
  - **Azura's Star** is never consumed — it releases its soul and stays in your inventory
- **Item Recharge**: Restore charges to enchanted items using stored soul power (1:1 ratio)
- **Enhanced Enchanting**: Permanently increase item enchantment capacity before enchanting
  - Upgrade unenchanted items to have much higher capacity (configurable, default 100:1 soul power cost)
  - Then enchant them directly through the machine or normally at any enchanter
  - Stack multiple upgrades on the same item for extreme capacity
  - Works with both direct Lua enchanting and vanilla enchanters
- **Remove Enchantment**: Strip the enchantment from any enchanted weapon, armor, or clothing
  - Refunds soul power based on the enchantment's charge
  - Frees pre-enchanted artifacts to be re-enchanted via the normal enchanting system (or upgraded here first)
- **Add Enchantment**: Creates a runtime enchantment record from one of your known spells and swaps it onto the selected item
  - Choose the cast type: Cast on Strike (weapons), Cast on Use, or Constant Effect
  - Searchable, paged spell list; name your creation as the final step
- **Soul Siphon**: A machine-exclusive Cast-on-Strike enchantment (pinned at the top of the spell list) — every hit siphons soul power from the victim straight into the bank. Built on a custom OpenMW 0.51 magic effect; cannot be made Constant (the feedback loop would tear the machine apart)
- **Custom Summons**: Mark a nearby creature, defeat it while marked, and learn a generated `Summon {creature}` spell with a 60-second duration
- **Attune Resonator**: Attunes the device to the Heart of Lorkhan — only succeeds within the final Dagoth Ur chamber (`Akulakhan's Chamber`). Attunement is permanent and grants:
  - **Heart's Resonance**: a constant +50 Enchant ability (configurable 0–100 in settings, updates live)
  - **Soul Resonance**: all deposited and siphoned souls yield 50% more power (enchantment-removal refunds are deliberately not amplified)
  - Note: the Heart is destroyed at the end of the main quest — attune before then, or never

### Technical Features ✅
- **No ESP Required**: Pure Lua + omwaddon implementation
- **Save/Load Persistent**: All data properly tied to save files
- **Clean UI**: Morrowind-styled interface with ESC key support
- **Fully Configurable**: Adjust upgrade costs and ratios in mod settings
- **Item Validation**: Smart error handling and type checking
- **Localization Ready**: Built-in English, easy to extend

### Future Plans
- **Quest Integration**: Unlock upgrade feature through in-game quests instead of settings toggle

## Requirements

- OpenMW 0.51 RC
- Lua scripting enabled

## Installation

1. Copy the `enchant-machine` folder to your OpenMW data directory
2. Add these lines to your `openmw.cfg`:
   ```
   data="path/to/enchant-machine"
   content=EnchantMachine.omwaddon
   lua-scripts=EnchantMachine.omwscripts
   ```

## Usage

### Discovering the Machine

**Story-Driven Discovery (Recommended for Standalone Mod):**

1. **Enable the boss encounter** by adding to `EnchantMachine.omwscripts`:
   ```
   GLOBAL: scripts/enchantmachine/spawn_researcher.lua
   ```

2. **Load your game** - the unique encounter spawns automatically

3. **Travel to Arkngthand** (Dwemer ruin just south of Seyda Neen)

4. **Navigate to the Deep Ore Passage** (quiet area with a chest, deep in the ruins)

5. **Face the Boss Encounter**:
   - Master Dwemer Researcher (Dwarven Ghost)
   - 2x Dwarven Ghost Guards
   - 1x Steam Centurion (Level 30)
   - **Difficulty: VERY HARD** (recommended level 10+)

6. **Defeat the Master Researcher** and loot the **Remote Control** (Dwemer puzzle box)

7. **Use the Remote** from your inventory to open the machine menu anywhere!

See `STORY_DISCOVERY.md` for alternative spawn locations and detailed instructions.

**Alternative: Skip the Boss (For Testing)**

If you want to start using the machine immediately, open the console and run:

```
luags lua sendGlobalEvent('EnchantMachine_GiveRemote', {})
```

This adds the remote directly to your inventory (handler in `global.lua`).

### Using the Machine

1. **Use the Remote Control** (Dwemer puzzle box) from your inventory
2. The ancient machine interface appears with options:
   - **Deposit Soul Gems**: Convert filled soul gems into stored soul power
   - **Recharge Item**: Restore charges to enchanted items (1 soul power per charge point)
   - **Add Enchantment**: Imbue an unenchanted weapon, armor, or clothing item with one of your known spells
   - **Remove Enchantment**: Strip an item's enchantment and refund soul power
   - **Mark Summon Creature**: Mark a nearby creature; killing it teaches a 60-second summon spell
   - **Upgrade Item Capacity**: Permanently increase an unenchanted item's enchantment capacity
   - **Attune Resonator**: Attune to the Heart (only works in the final Dagoth Ur chamber)
3. **After upgrading an item**, use **Add Enchantment** or visit any enchanter in Morrowind to create incredibly powerful enchantments.

**Important Notes**:
- Press **ESC** to close any menu at any time
- The Remote is **not consumed** when used - keep it forever!
- Only **unenchanted** items can be upgraded (always upgrade before enchanting!)
- After upgrading, use **Add Enchantment** or normal Morrowind enchanters to create your powerful enchantments

### Workflow Example

1. Find/buy an unenchanted item you want to make powerful
2. Use the Remote → Upgrade Item Capacity → Select item → Upgrade (costs soul power)
3. Use Add Enchantment from the Remote, or visit any enchanter and enchant the upgraded item normally
4. Enjoy your massively more powerful enchanted item!

### Settings

Access mod settings in OpenMW under: **Settings → Scripts → Dwemer Enchanting Machine**

- **Enable Machine**: Turn the entire system on/off
- **Enchant Multiplier**: Display multiplier hint for enchantment capacity (1-100, default: 10x)
- **Upgrade Ratio**: Soul power cost per capacity point (1-1000, default: 100:1)
  - Lower = cheaper upgrades, higher = more expensive upgrades
- **Enable Upgrades**: Toggle the upgrade feature (can be quest-locked in future)

## Technical Details

### Architecture

- **load.lua**: LOAD script — defines the custom mark/summon magic effects and hidden mark spell
- **global.lua**: GLOBAL script — soul bank, item swaps, custom summon capture/spawn, settings sync, save/load, remote-item handler
- **player_full.lua**: PLAYER script — UI menus, settings page, inventory scanning, boss-cell detection
- **soul_mark_monitor.lua**: NPC/CREATURE local script — watches marked creatures for death
- **summoned.lua**: CUSTOM local script — keeps spawned summons following the player and removes them after 60 seconds
- **machine.lua**: CUSTOM script — attached to in-world activators (optional), forwards activation to the player
- **spawn_researcher.lua**: GLOBAL script — one-time boss encounter spawn
- **debug.lua**: GLOBAL script — logging, metrics, and performance tools

See `DEVELOPER_GUIDE.md` for the full architecture, event protocol, and storage section layout.

### How Upgrades Work

When you upgrade an item:
1. Creates a **new item record** with increased `enchantCapacity` property
2. Replaces one old item instance with the upgraded version in your inventory
3. Preserves item condition and any existing charges
4. Tracks the generated record's base record in the save file (multiple upgrades on that item stack)
5. You can then enchant it normally at any enchanter for powerful results

### Data Storage

- **Soul Power**: Stored per save file, shared globally
- **Upgraded Items**: Tracked per generated record ID with base record mapping
- **Custom Summons**: Generated summon spell IDs map to captured creature record IDs
- **Settings**: Persistent per-character configuration

### API Interface

Other mods can interact with the EnchantMachine through its global interface:

```lua
local I = require('openmw.interfaces')
local machine = I.EnchantMachine

-- Soul Power Management
local power = machine.getSoulPower()                        -- Get current soul power
machine.addSoulPower(500)                                   -- Add soul power
local success, remaining = machine.subtractSoulPower(100)   -- Subtract (returns success, newTotal)
local value = machine.getSoulValue("golden saint")          -- Get soul value from creature ID

-- Item Operations
local success, msg = machine.depositSoul(item, actor)       -- Deposit soul gem
local success, msg = machine.rechargeItem(item, actor)      -- Recharge enchanted item
local capacity = machine.getItemCapacity(item)              -- Get total capacity (base + upgrades)

-- Upgrade Operations
local upgrade = machine.getUpgradedCapacity(itemRecordId)   -- Get current upgrade level
local success, msg = machine.upgradeItemCapacity(item, amount, actor)  -- Upgrade by amount

-- Custom Summons
local success, msg = machine.markCreature(creature, actor)  -- Mark a living creature
local summons = machine.getSummonSpells()                   -- Generated summon spell metadata

-- Settings
local settings = machine.getSettings()                      -- Get all settings
-- settings.enableMachine, settings.upgradeRatio, settings.enableUpgradeFeature
```

## Status

**Version**: 2.2.0
**Status**: ✅ PRODUCTION READY - Fully Functional!

All core features are implemented and working:
- ✅ **Remote Control System** - Use the remote item from inventory to access the machine
- ✅ **Boss Encounter** - Unique story-driven discovery system
- ✅ **Soul Power Banking** - Deposit and manage soul power globally
- ✅ **Item Recharge** - Restore charges to enchanted items
- ✅ **Capacity Upgrades** - Permanently increase item enchantment capacity
- ✅ **Direct Lua Enchanting** - Add enchantments from known spells without native UI handoff
- ✅ **Custom Summons** - Capture marked creatures into generated 60-second summon spells
- ✅ **Multiple Upgrades** - Stack upgrades on the same item repeatedly
- ✅ **Save/Load Persistence** - All data tied to save files properly
- ✅ **Clean UI** - Morrowind-styled menus with ESC key support
- ✅ **Configurable** - Adjust costs and multipliers via mod settings

**Latest Update (v2.2.0 - 2026-06-05):**
- Direct Lua Add Enchantment flow using runtime enchantment and item records
- Custom creature summon capture flow using 0.51 RC load-time custom magic effects
- Safer item record swaps for upgrades, add-enchant, and remove-enchant
- Upgrade tracking fixed to avoid leaking capacity upgrades across all items with the same base record

### For Developers

See **[DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** for API documentation and extension guides.

## How It Works

The mod achieves enhanced enchanting by creating runtime records in GLOBAL scripts:

1. The machine can derive an item record with higher `enchantCapacity`
2. Add Enchantment creates an enchantment record from a known spell, then derives an item record pointing at it
3. Remove Enchantment derives a blank item record and refunds soul power from the old enchantment
4. Custom summons create spell records tied to captured creature record IDs

See [ENCHANTING_LIMITATION.md](ENCHANTING_LIMITATION.md) for technical details.

## Compatibility

- **OpenMW**: 0.51 RC required
- **Save Files**: Safe to add/remove (uses persistent storage)
- **Other Mods**: Should be compatible with most mods
- **MWSE**: Not compatible (this is OpenMW-only)

## Credits

- Built for OpenMW 0.51 RC Lua scripting API
- Inspired by Morrowind's enchanting mechanics

## License

MIT License - Free to use, modify, and distribute
