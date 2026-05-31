# Quick Start Guide — Dwemer Enchanting Machine

Get the mod running and tested in a few minutes.

## Step 1: Install

Copy the `enchant-machine/` folder into your OpenMW data directory, then edit your `openmw.cfg`:

```
data="/path/to/enchant-machine"
content=EnchantMachine.omwaddon
lua-scripts=EnchantMachine.omwscripts
```

Required files:

```
enchant-machine/
├── EnchantMachine.omwscripts
├── EnchantMachine.omwaddon
├── l10n/EnchantMachine/en.lua
└── scripts/enchantmachine/
    ├── global.lua
    ├── player_full.lua
    ├── machine.lua
    ├── debug.lua
    └── spawn_researcher.lua
```

Requires OpenMW 0.49 or later.

## Step 2: Get the Remote

**Story path:** load a save, travel to Arkngthand → Deep Ore Passage, defeat the Master Dwemer Researcher and his guards, then loot the **Dwemer Enchanting Machine Remote** from his body.

**Skip path (testing):** press F3 to open the console and run:

```
luags lua sendGlobalEvent('EnchantMachine_GiveRemote', {})
```

The remote appears in your inventory immediately.

## Step 3: Use the Remote

1. Open your inventory.
2. Double-click the **Dwemer Enchanting Machine Remote** (a small Dwemer artifact).
3. The machine menu opens. The remote is **not consumed** — keep it.

The menu offers:
- **Deposit Soul Gems** — consume filled gems for soul power.
- **Recharge Enchanted Items** — restore charges (1 power per charge point).
- **Upgrade Item Capacity** — permanently raise an unenchanted item's `enchantCapacity` (locked behind a setting toggle).

Press **ESC** to close any menu.

## Step 4: Try Each Feature

**Deposit:**
1. Make sure you have at least one filled soul gem.
2. Remote → Deposit Soul Gems → click the gem.

**Recharge:**
1. Use an enchanted item until its charge drops.
2. Remote → Recharge Enchanted Items → click the item.

**Upgrade:**
1. Open Settings → Scripts → Dwemer Enchanting Machine and turn on **Enable Upgrades**.
2. Pick an unenchanted weapon/armor/clothing item with non-zero enchant capacity.
3. Remote → Upgrade Item Capacity → pick item → choose an amount.
4. Take the upgraded item to any enchanter and enchant it normally — the higher capacity unlocks much stronger enchantments.

## Settings

`Options → Scripts → Dwemer Enchanting Machine`

- **Enable Machine** — master on/off switch.
- **Enchant Multiplier** — display hint (default 10x).
- **Upgrade Ratio** — soul power per capacity point (default 100).
- **Enable Upgrades** — gates the upgrade menu.
- **Soul Power** — read-only display under the Status section.

## Troubleshooting

| Symptom | Check |
|---|---|
| Remote doesn't open a menu | Confirm `lua-scripts=EnchantMachine.omwscripts` is set; reload the save. |
| Settings page missing | Confirm OpenMW 0.49+ and the `lua-scripts=` line. |
| Boss didn't spawn | Look at the OpenMW log for `[EnchantMachine]` lines — the boss spawns when the player enters `Arkngthand, Deep Ore Passage`. |
| "Machine is disabled" message | Toggle **Enable Machine** in Settings. |

For deeper debugging, see [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md). Logs and metrics are accessible via the `EnchantMachineDebug` interface from any GLOBAL script.
