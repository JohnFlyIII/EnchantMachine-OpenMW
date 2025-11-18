# Quick Start Guide - Dwemer Enchanting Machine

## 5-Minute Test Setup

This guide gets you testing the mod in under 5 minutes.

### Step 1: Verify Installation (30 seconds)

Check that these files exist:
```
enchant-machine/
├── EnchantMachine.omwscripts
├── l10n/EnchantMachine/en.lua
└── scripts/EnchantMachine/
    ├── global.lua
    ├── player.lua
    ├── machine.lua
    └── test_machine.lua
```

### Step 2: Enable in OpenMW (1 minute)

1. Open **OpenMW Launcher**
2. Go to **Data Files** tab
3. Make sure your data path includes: `enchant-machine`
4. Edit `openmw.cfg` and add:
   ```
   data="/path/to/enchant-machine"
   lua-scripts=EnchantMachine.omwscripts
   ```
5. Save and launch OpenMW

### Step 3: Create Test Machine (2 minutes)

**In-Game:**

1. Load any save
2. Press **F3** (open console)
3. Type: `player->coc "balmora, guild of mages"`
4. Look at any object (door, chest, etc.)
5. Type: `"reference"->addscript "scripts/EnchantMachine/test_machine.lua"`
6. Close console (**F3**)
7. **Activate the object**

You should see the machine menu!

### Step 4: Get Test Items (1 minute)

Press **F3** and run these commands:

```
em_give_gems          # Get soul gems
em_add_souls 10000    # Get 10,000 soul power
em_give_upgradeable   # Get items to upgrade
```

### Step 5: Test Features (1 minute)

**Test Deposit:**
1. Open machine
2. Click "Deposit Soul Gems"
3. Select a gem
4. Watch your soul power increase!

**Test Recharge:**
1. Get enchanted item: `player->additem "glass dagger_enamor" 1`
2. Use it a few times to drain charges
3. Open machine → "Recharge Item"
4. Select the dagger
5. It's fully charged!

**Test Upgrade:**
1. Go to **Settings → Scripts → Dwemer Enchanting Machine**
2. Enable "Enable Item Upgrades"
3. Open machine → "Upgrade Item Capacity"
4. Select an item (e.g., "Exquisite Shirt")
5. Choose "+10 capacity"
6. Item capacity permanently increased!

## Quick Commands Reference

| Command | What It Does |
|---------|--------------|
| `em_help` | Show all commands |
| `em_status` | Show soul power and settings |
| `em_give_gems` | Get filled soul gems |
| `em_give_upgradeable` | Get test items |
| `em_add_souls 10000` | Add 10k soul power |

## Keyboard Shortcuts

- **F3** - Open/close console
- **F10** - Toggle console history (see detailed output)
- **ESC** - Close machine menu

## Common Issues

**"No global script found"**
→ Make sure `lua-scripts=EnchantMachine.omwscripts` is in openmw.cfg

**Machine doesn't activate**
→ Make sure you attached the script to an activator (not a static object)

**Settings not showing**
→ Go to Settings → Scripts → Dwemer Enchanting Machine

**"Machine is disabled"**
→ Enable it in: Settings → Scripts → Dwemer Enchanting Machine → Enable Machine

## Next Steps

- See **[TESTING.md](TESTING.md)** for comprehensive testing guide
- See **[README.md](README.md)** for full documentation
- See **[CODE_REVIEW_SUMMARY.md](CODE_REVIEW_SUMMARY.md)** for technical details

## Cleaning Up

To remove the test machine:
1. Select the object in console
2. Type: `disable`
3. Type: `markfordelete`

To reset your test data:
1. Delete storage files in:
   - Windows: `%USERPROFILE%\Documents\My Games\OpenMW\storage\`
   - Linux: `~/.local/share/openmw/storage/`
2. Look for files with "EnchantMachine" in the name

## Support

If something doesn't work:
1. Check OpenMW version (need 0.49+)
2. Check console (F10) for error messages
3. Run `em_status` to verify system state
4. See **[TESTING.md](TESTING.md)** troubleshooting section
