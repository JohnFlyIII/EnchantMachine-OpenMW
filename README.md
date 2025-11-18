# Dwemer Enchanting Machine

A powerful OpenMW mod that enables vastly more powerful enchanted items through a mysterious Dwemer artifact.

## What This Mod Does

Defeat a unique boss to obtain an ancient **Dwemer puzzle box** that lets you:
1. **Bank soul power** from filled soul gems
2. **Recharge enchanted items** anywhere, anytime
3. **Upgrade unenchanted items** to have massively increased enchantment capacity
4. Then use **normal Morrowind enchanters** to create incredibly powerful enchantments!

The result: Create enchanted items with 10x, 50x, or even 100x the normal capacity - limited only by your soul power reserves.

## Features

### Core System ✅
- **Story-Driven Discovery**: Defeat a unique boss encounter in vanilla Dwemer ruins to obtain the Remote
- **Remote Control Device**: Ancient Dwemer puzzle box that opens the machine interface from anywhere
- **Soul Power Bank**: Deposit filled soul gems to extract and store their soul power globally
- **Item Recharge**: Restore charges to enchanted items using stored soul power (1:1 ratio)
- **Enhanced Enchanting**: Permanently increase item enchantment capacity before enchanting
  - Upgrade unenchanted items to have much higher capacity (configurable, default 100:1 soul power cost)
  - Then enchant them normally at any enchanter for vastly more powerful enchantments
  - Stack multiple upgrades on the same item for extreme capacity
  - Works with vanilla enchanting mechanics - no API limitations!

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

- OpenMW 0.49 or later
- Lua scripting enabled (default in OpenMW 0.49+)

## Installation

1. Copy the `enchant-machine` folder to your OpenMW data directory
2. Add this line to your `openmw.cfg`:
   ```
   data="path/to/enchant-machine"
   ```
3. In OpenMW Launcher, enable the mod by adding:
   ```
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

If you want to start using the machine immediately, you can spawn the remote with console commands. See `give_remote.lua` helper script for details.

### Using the Machine

1. **Use the Remote Control** (Dwemer puzzle box) from your inventory
2. The ancient machine interface appears with options:
   - **Deposit Soul Gems**: Convert filled soul gems into stored soul power
   - **Recharge Item**: Restore charges to enchanted items (1 soul power per charge point)
   - **Upgrade Item Capacity**: Permanently increase an unenchanted item's enchantment capacity
3. **After upgrading an item**, visit any enchanter in Morrowind to create incredibly powerful enchantments!

**Important Notes**:
- Press **ESC** to close any menu at any time
- The Remote is **not consumed** when used - keep it forever!
- Only **unenchanted** items can be upgraded (always upgrade before enchanting!)
- After upgrading, use **normal Morrowind enchanters** to create your powerful enchantments

### Workflow Example

1. Find/buy an unenchanted item you want to make powerful
2. Use the Remote → Upgrade Item Capacity → Select item → Upgrade (costs soul power)
3. Visit any enchanter (Balmora, Vivec, etc.) and enchant the upgraded item normally
4. Enjoy your massively more powerful enchanted item!

### Settings

Access mod settings in OpenMW under: **Settings → Scripts → Dwemer Enchanting Machine**

- **Enable Machine**: Turn the entire system on/off
- **Upgrade Cost Ratio**: Soul power cost per capacity point (10-1000, default: 100:1)
  - Lower = cheaper upgrades, higher = more expensive upgrades
- **Enable Item Upgrades**: Toggle the upgrade feature (can be quest-locked in future)

## Technical Details

### Architecture

- **global.lua**: Manages soul bank, item upgrades, settings, and data persistence
- **player_full.lua**: Player script for UI, inventory interaction, and remote control
- **spawn_researcher.lua**: Boss encounter system
- **debug.lua**: Debug and logging system

### How Upgrades Work

When you upgrade an item:
1. Creates a **new item record** with increased `enchantCapacity` property
2. Replaces the old item with the upgraded version in your inventory
3. Preserves item condition and any existing charges
4. Tracks the upgrade in save file (multiple upgrades stack)
5. You can then enchant it normally at any enchanter for powerful results

### Data Storage

- **Soul Power**: Stored per save file, shared globally
- **Upgraded Items**: Tracked by record ID with base record mapping
- **Settings**: Persistent per-character configuration

### API Interface

Other mods can interact with the EnchantMachine through its global interface:

```lua
local machine = core.getGlobalScript('EnchantMachine')

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

-- Settings
local settings = machine.getSettings()                      -- Get all settings
-- settings.enableMachine, settings.upgradeRatio, settings.enableUpgradeFeature
```

## Status

**Version**: 2.1.0
**Status**: ✅ PRODUCTION READY - Fully Functional!

All core features are implemented and working:
- ✅ **Remote Control System** - Use the remote item from inventory to access the machine
- ✅ **Boss Encounter** - Unique story-driven discovery system
- ✅ **Soul Power Banking** - Deposit and manage soul power globally
- ✅ **Item Recharge** - Restore charges to enchanted items
- ✅ **Capacity Upgrades** - Permanently increase item enchantment capacity
- ✅ **Multiple Upgrades** - Stack upgrades on the same item repeatedly
- ✅ **Save/Load Persistence** - All data tied to save files properly
- ✅ **Clean UI** - Morrowind-styled menus with ESC key support
- ✅ **Configurable** - Adjust costs and multipliers via mod settings

**Latest Update (v2.1.0 - 2025-01-12):**
- ✨ Fixed remote control item - now properly opens menu from inventory
- ✨ Remote uses Dwemer puzzle box mesh and visuals
- ✨ Enhanced enchanting achieved through capacity upgrades + vanilla enchanters
- ✨ Improved atmospheric messages and UI feedback
- ✨ Cleaned up codebase and removed development artifacts

### For Developers

See **[DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** for API documentation and extension guides.

## How It Works

The mod achieves "enhanced enchanting" by **increasing item capacity before you enchant them**:

1. The machine upgrades an unenchanted item's enchantment capacity
2. You then use **normal Morrowind enchanting** (at any enchanter NPC)
3. The vanilla game lets you create much more powerful enchantments due to the increased capacity
4. Result: Massively more powerful enchanted items without needing runtime enchantment creation!

This approach works perfectly with vanilla mechanics and has no API limitations. See [ENCHANTING_LIMITATION.md](ENCHANTING_LIMITATION.md) for technical details.

## Compatibility

- **OpenMW**: 0.49+ required
- **Save Files**: Safe to add/remove (uses persistent storage)
- **Other Mods**: Should be compatible with most mods
- **MWSE**: Not compatible (this is OpenMW-only)

## Credits

- Built for OpenMW 0.49 Lua scripting API
- Inspired by Morrowind's enchanting mechanics

## License

MIT License - Free to use, modify, and distribute
