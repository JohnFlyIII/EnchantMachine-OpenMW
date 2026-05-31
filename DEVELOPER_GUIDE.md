## Developer Guide — Dwemer Enchanting Machine

Reference for developers extending or modifying the mod.

## Project Structure

```
enchant-machine/
├── EnchantMachine.omwscripts         # Script registration
├── EnchantMachine.omwaddon           # Custom records (omwaddon)
├── README.md                         # User documentation
├── QUICKSTART.md                     # 5-minute setup guide
├── ENCHANTING_LIMITATION.md          # Why upgrades work the way they do
├── STORY_DISCOVERY.md                # Boss-encounter design notes
├── DEVELOPER_GUIDE.md                # This file
├── l10n/EnchantMachine/
│   └── en.lua                        # Localization strings
└── scripts/enchantmachine/
    ├── global.lua                    # GLOBAL: soul-power, items, upgrades, settings store
    ├── player_full.lua               # PLAYER: UI, settings page, input
    ├── machine.lua                   # CUSTOM: activator-attached, forwards to player
    ├── debug.lua                     # GLOBAL: logging, metrics, performance
    └── spawn_researcher.lua          # GLOBAL: one-time boss encounter
```

## Architecture Overview

OpenMW splits Lua execution into contexts. Each script in `EnchantMachine.omwscripts` runs in one of them:

| Script               | Context | Loads via            |
|----------------------|---------|----------------------|
| `global.lua`         | GLOBAL  | `GLOBAL:` directive  |
| `debug.lua`          | GLOBAL  | `GLOBAL:` directive  |
| `spawn_researcher.lua` | GLOBAL | `GLOBAL:` directive |
| `player_full.lua`    | PLAYER  | `PLAYER:` directive  |
| `machine.lua`        | CUSTOM  | `CUSTOM:` directive, attached to activator objects |

**Key constraint:** GLOBAL has world authority (`world.createRecord`, `world.createObject`, creature records). PLAYER has UI and input. Crossing contexts requires events — there's no shared mutable state. See `ENCHANTING_LIMITATION.md` for the deeper explanation of why upgrades must create derived records.

### Script Responsibilities

#### global.lua — Core logic
- Soul-power bank (in-memory, persisted via `onSave`/`onLoad`).
- Soul-gem deposit, item recharge, capacity upgrade.
- Custom-record creation for upgraded items (`<base>_cap<N>` IDs).
- Remote-control item handler registered via `I.ItemUsage.addHandlerForType`.
- Exports the public `EnchantMachine` interface (see API Reference).
- Receives `EnchantMachine_SyncSettings` events from PLAYER to keep its `getSettings()` consistent with the user-configured values.

#### player_full.lua — UI and input
- Registers the Settings page (`Options → Scripts → Dwemer Enchanting Machine`).
- Reads soul power from `storage.globalSection('EnchantMachine_SharedData')` (write-cached by GLOBAL).
- Builds menus via the local `createMenu{}` helper.
- Sends operation events (`EnchantMachine_DepositGem`, `EnchantMachine_RechargeItem`, `EnchantMachine_UpgradeItem`) and waits for `EnchantMachine_Result` replies.
- Detects entry into the boss cell and pings GLOBAL to spawn the encounter.

#### machine.lua — Activator handler
Twenty-line script attached to in-world activator objects. Forwards activation to the player via `actor:sendEvent('EnchantMachine_OpenMenu', …)`.

#### debug.lua — Diagnostics
Independent global script exposing `I.EnchantMachineDebug` with logging, metrics, performance timers, and reporting. All other scripts call it defensively via `local debug = getDebug()` since it loads in unspecified order.

#### spawn_researcher.lua — Boss encounter
One-time spawn of the Master Dwemer Researcher + guards at a configured Dwemer-ruin location. Persists `bossSpawned` per save file. Has fallback creature-ID candidates for mod-conflict resilience.

## Storage Sections

| Section                          | Owner   | Purpose                                  |
|----------------------------------|---------|------------------------------------------|
| `EnchantMachine_SharedData`      | GLOBAL  | Soul-power display cache for PLAYER UI.  |
| `EnchantMachine_Settings`        | GLOBAL  | User settings (synced from PLAYER each tick). |
| `EnchantMachine_Debug`           | GLOBAL  | `debug.lua` log buffer, metrics, perf.   |
| `SettingsEnchantMachineConfig`   | PLAYER  | The real settings UI store (per-player). |
| `SettingsEnchantMachineStatus`   | PLAYER  | Read-only soul-power line on settings page. |

In-memory state (`soulPower`, `upgradedItems`, `itemBaseRecords`, `bossSpawned`, `bossSpawnRequested`) is persisted via each script's `onSave` / `onLoad`.

## Cross-Context Events

| Event                            | Direction        | Purpose |
|----------------------------------|------------------|---------|
| `EnchantMachine_OpenMenu`        | GLOBAL → PLAYER  | Open the main menu (fired by remote item or activator). |
| `EnchantMachine_DepositGem`      | PLAYER → GLOBAL  | Consume a soul gem, credit soul power.   |
| `EnchantMachine_RechargeItem`    | PLAYER → GLOBAL  | Recharge an enchanted item.              |
| `EnchantMachine_UpgradeItem`     | PLAYER → GLOBAL  | Upgrade an item's `enchantCapacity`.     |
| `EnchantMachine_Result`          | GLOBAL → PLAYER  | Operation reply (`success`, `message`).  |
| `EnchantMachine_SyncSettings`    | PLAYER → GLOBAL  | Push current settings to GLOBAL.         |
| `EnchantMachine_SpawnBoss`       | PLAYER → GLOBAL  | Request boss spawn (fired on cell entry).|
| `EnchantMachine_GiveRemote`      | console → GLOBAL | Debug: add a remote to the player.       |

## API Reference

```lua
local machine = core.getGlobalScript('EnchantMachine')

-- Soul Power Management
machine.getSoulPower() -> number
machine.addSoulPower(amount) -> newTotal
machine.subtractSoulPower(amount) -> (success, remaining)
machine.resetSoulPower() -> 0
machine.getSoulValue(creatureId) -> number

-- Item Operations
machine.depositSoul(item, actor, settings?) -> (success, message)
machine.rechargeItem(item, actor, settings?) -> (success, message)
machine.canBeEnchanted(item) -> (canEnchant, recordOrMessage)
machine.getItemCapacity(item) -> number
machine.getEffectiveEnchantCapacity(item) -> number

-- Upgrade Operations
machine.getUpgradedCapacity(itemRecordId) -> number
machine.upgradeItemCapacity(item, capacityIncrease, actor, settings?) -> (success, message)

-- Settings
machine.getSettings() -> {
    enableMachine: boolean,
    enchantMultiplier: number,
    upgradeRatio: number,
    enableUpgradeFeature: boolean,
}
```

Settings UI is the only supported way to change settings at runtime; there is no `setSetting` API.

### Debug Interface

```lua
local debug = I.EnchantMachineDebug  -- available in GLOBAL scripts

debug.error(category, message, data?)
debug.warn(category, message, data?)
debug.info(category, message, data?)
debug.debug(category, message, data?)
debug.trace(category, message, data?)

debug.incrementMetric(name)
debug.trackMetric(name, value)
debug.getMetrics() -> table

debug.startTimer(name)
debug.endTimer(name) -> elapsedSeconds

debug.generateReport() -> table
debug.formatReport() -> string

debug.setLogLevel("INFO" | "WARN" | "ERROR" | "DEBUG" | "TRACE")
debug.setDebugEnabled(bool)
```

## Working with Upgrades

The upgrade pipeline lives in `global.lua:upgradeItemCapacity`:

1. Resolve the **base** record ID: check `itemBaseRecords[item.recordId]`, then fall back to pattern-matching `^(.-)_cap%d+$`, then the item's own recordId.
2. Read the cumulative upgrade delta from `upgradedItems[baseRecordId]`.
3. Compute `newCapacity = baseCapacity + previousUpgrade + capacityIncrease`.
4. Create a derived record with id `<base>_cap<newCapacity>` and the new `enchantCapacity`. Store `itemBaseRecords[newId] = baseRecordId`.
5. Instantiate the new item, copy `condition` and `enchantmentCharge` from the old instance, move into the actor, then remove the old item.
6. Update `upgradedItems[baseRecordId]`.

`getItemCapacity` simply returns `record.enchantCapacity` — the upgrade is already baked in.

## Save Format

`global.lua`:
```lua
{
    version = 2,
    soulPower = number,
    upgradedItems = { [baseRecordId] = totalUpgrade, ... },
    itemBaseRecords = { [generatedRecordId] = baseRecordId, ... },
}
```

`spawn_researcher.lua`:
```lua
{ version = 1, bossSpawned = boolean }
```

`player_full.lua`:
```lua
{ version = 1, bossSpawnRequested = boolean }
```

When changing the schema, bump `version` and handle migration in `onLoad`.

## Adding a Feature

1. Add the operation function in `global.lua`. Validate inputs and return `(success, message)`.
2. Export it on the interface table at the bottom of `global.lua`.
3. If the operation needs the player, define a `EnchantMachine_*` event handler in `eventHandlers` and reply via `actor:sendEvent('EnchantMachine_Result', …)`.
4. Add a `show*Menu` function in `player_full.lua`. **Add a forward declaration at the top of the file** alongside the existing ones — Lua resolves closure upvalues at parse time, so any reference to a not-yet-declared local silently becomes a global.
5. Wire the new menu into `createMainMenu`.
6. Pass the current settings on the outgoing event (`settings = getSettings()`).

## Debugging Tips

- Set log level: `I.EnchantMachineDebug.setLogLevel("TRACE")`.
- Generate a report: `print(I.EnchantMachineDebug.formatReport())`.
- Reset state: `I.EnchantMachineDebug.clearLogs()`, `clearMetrics()`, `clearPerformance()`.
- After a save/load, `I.ItemUsage` handlers do not persist — `global.lua` re-registers them in `onLoad`. If you add another handler, do the same.

## Code Style

- 4-space indentation.
- Functions: `camelCase`. Constants: `UPPER_SNAKE_CASE`. Locals: `lowerCase`.
- Prefer the `local function` form. For mutually-recursive locals (e.g., menu functions), declare them all up front and assign with `name = function(...)`.
- Wrap engine calls that may fail in `pcall` (`world.createRecord`, `world.createObject`, `creature:teleport`).
- Comment only the non-obvious: workarounds, invariants, lifecycle constraints.

## Resources

- **OpenMW Lua Docs**: https://openmw.readthedocs.io/en/stable/reference/lua-scripting/
- **OpenMW Forums**: https://forum.openmw.org/
