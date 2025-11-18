# Dwemer Enchanting Machine

A powerful OpenMW mod that adds advanced enchanting capabilities through a Dwemer-crafted machine.

## Features

### Implemented ✅
- **Story-Driven Discovery**: Unique boss encounter in vanilla Dwemer ruins to obtain the Remote
- **Remote Control Item**: Use an in-game scroll to open the machine menu (no console commands!)
- **Soul Power Bank**: Deposit filled soul gems to extract and store their soul power globally
- **Soul Gem Consumption**: Deposited soul gems are consumed (removed from inventory)
- **Recharge System**: Restore charges to enchanted items using stored soul power (1:1 ratio)
- **Item Capacity Upgrades**: Permanently increase item enchantment capacity (configurable ratio, default 100:1)
  - Creates new item records with higher enchantment capacity
  - Supports multiple upgrades on the same item
  - Only works on unenchanted items (upgrade before enchanting!)
- **Persistent Storage**: Soul power and upgrades persist across game sessions via save files
- **Enhanced UI**: Clean, Morrowind-styled interface with ESC key support
- **Configurable Settings**: Adjust power multipliers and upgrade costs in mod settings
- **Localization Support**: Built-in English localization (easy to extend to other languages)
- **Comprehensive Validation**: Smart error handling and item type checking
- **Unique Boss Encounter**: One-time boss fight against the Master Dwemer Researcher and guards
- **No ESP Required**: Pure Lua implementation, works as a standalone mod

### Planned (Coming Soon)
- **Enhanced Enchanting**: Create custom enchantments with 10x vanilla capacity (configurable)
- **Quest Integration**: Unlock upgrade feature through in-game quests instead of settings

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

6. **Defeat the Master Researcher** and loot the **Remote Control scroll**

7. **Use the Remote** from your inventory to open the machine menu!

See `STORY_DISCOVERY.md` for alternative spawn locations and detailed instructions.

**Alternative: Skip the Boss (For Testing)**

If you want to start using the machine immediately, you can spawn the remote with console commands. See `give_remote.lua` helper script for details.

### Using the Machine

1. **Use the Remote Control scroll** from your inventory (looks like "Windwalker")
2. The main menu will appear with options:
   - **Deposit Soul Gems**: Select filled soul gems from your inventory to deposit
   - **Recharge Item**: Restore charges to enchanted items (costs 1 soul power per charge point)
   - **Upgrade Item Capacity**: Permanently increase unenchanted item capacity (requires feature enabled in settings)
   - **Enchant Item** (coming soon): Create powerful enchantments

**Note**:
- Press **ESC** to close any menu at any time
- The Remote is **not consumed** when used - keep it forever!
- Only **unenchanted** items can be upgraded (upgrade before enchanting!)

### Settings

Access mod settings in OpenMW under: **Settings → Scripts → Dwemer Enchanting Machine**

- **Enable Machine**: Turn the system on/off
- **Enchant Power Multiplier**: Set max enchantment value (1-100x, default: 10x)
- **Upgrade Cost Ratio**: Soul power cost per capacity point (10-1000, default: 100:1)
- **Enable Item Upgrades**: Toggle the upgrade feature (can be quest-locked)

## Technical Details

### Architecture

- **global.lua**: Manages soul bank, settings, and data persistence
- **machine.lua**: Local script for activator objects, handles activation
- **player.lua**: Player script for UI and inventory interaction

### Data Storage

- **Soul Power**: Stored globally, shared across all machines
- **Upgraded Items**: Tracked by record ID in global storage
- **Settings**: Persistent per-character storage

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
local canEnchant, record = machine.canBeEnchanted(item)     -- Check if item can be enchanted
local capacity = machine.getItemCapacity(item)              -- Get total capacity (base + upgrades)
local effectiveCap = machine.getEffectiveEnchantCapacity(item)  -- Get capacity with multiplier

-- Upgrade Operations
local upgrade = machine.getUpgradedCapacity(itemRecordId)   -- Get upgrade for item type
local success, msg = machine.upgradeItemCapacity(item, 50)  -- Upgrade item capacity

-- Settings
local settings = machine.getSettings()                      -- Get all settings
-- settings.enableMachine, settings.enchantMultiplier, settings.upgradeRatio, settings.enableUpgradeFeature
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
- ✨ Improved atmospheric messages and UI feedback
- ✨ Cleaned up codebase and removed development artifacts

### For Developers

See **[DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** for API documentation and extension guides.

## Known Issues

- **Enhanced enchanting not implemented**: OpenMW Lua API doesn't support runtime enchantment creation. See [ENCHANTING_LIMITATION.md](ENCHANTING_LIMITATION.md) for details and potential workarounds.
- **Quest integration**: Currently uses settings toggle. In-game quest system planned for future update.

All other features are fully functional and production-ready.

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
