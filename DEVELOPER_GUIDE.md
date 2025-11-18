## Developer Guide - Dwemer Enchanting Machine

Comprehensive guide for developers working on or extending the Dwemer Enchanting Machine mod.

## Project Structure

```
enchant-machine/
├── EnchantMachine.omwscripts         # Script registration file
├── README.md                          # User documentation
├── QUICKSTART.md                      # 5-minute setup guide
├── TESTING.md                         # Testing procedures
├── CODE_REVIEW_SUMMARY.md            # Technical review
├── ENCHANTING_LIMITATION.md          # API limitations explained
├── DEVELOPER_GUIDE.md                # This file
├── l10n/EnchantMachine/
│   └── en.lua                         # Localization strings
└── scripts/EnchantMachine/
    ├── global.lua                     # Core business logic
    ├── player.lua                     # UI and player interaction
    ├── machine.lua                    # Activator script
    ├── debug.lua                      # Debug and logging system
    ├── test_suite.lua                 # Automated tests
    ├── test_machine.lua               # Manual testing tools
    ├── quest_example.lua              # Quest integration example
    └── placement_helper.lua           # Placement utilities
```

## Architecture Overview

### Script Responsibilities

#### global.lua (Core Logic)
- **Purpose**: Business logic and data management
- **Responsibilities**:
  - Soul power management
  - Item validation and operations
  - Recharge functionality
  - Upgrade system
  - Settings access
- **Interface**: Exports functions for other scripts
- **Storage**: Uses `storage.globalSection('EnchantMachine_Data')`

#### player.lua (UI Layer)
- **Purpose**: User interface and player interaction
- **Responsibilities**:
  - Menu creation and management
  - Inventory scanning
  - User input handling
  - Visual feedback
- **Interface**: Receives events, displays UI
- **Key Functions**: `createMainMenu()`, `showDepositMenu()`, etc.

#### machine.lua (Activator)
- **Purpose**: Object activation handler
- **Responsibilities**:
  - Detect player activation
  - Send event to player script
- **Minimal**: Only 25 lines

#### debug.lua (Development Support)
- **Purpose**: Logging, metrics, and diagnostics
- **Responsibilities**:
  - Log management
  - Performance tracking
  - Metric collection
  - System validation
- **Interface**: Provides debug functions to all scripts

#### test_suite.lua (Quality Assurance)
- **Purpose**: Automated testing
- **Responsibilities**:
  - Unit tests
  - Integration tests
  - Test reporting
- **Console Command**: `em_test`

## Development Workflow

### 1. Setting Up Development Environment

```bash
# 1. Clone/download the mod
cd /path/to/OpenMW/data/

# 2. Enable developer mode in OpenMW
# Edit openmw.cfg:
lua-scripts=EnchantMachine.omwscripts

# 3. Enable console
# In-game: F3

# 4. Hot reload after changes
# Console: reloadlua
```

### 2. Making Changes

**Workflow:**
1. Edit Lua files
2. Save changes
3. In-game console: `reloadlua`
4. Test changes
5. Run automated tests: `em_test`

**Tips:**
- Use `debug.info()` liberally for logging
- Check console (F10) for errors
- Use `em_status` to verify state
- Run `em_test` before committing

### 3. Adding New Features

**Step-by-step:**

```lua
-- 1. Add function to global.lua
local function myNewFeature(item, actor)
    local debug = getDebug()
    if debug then debug.startTimer("myNewFeature") end

    -- Your logic here

    if debug then
        debug.info("MyFeature", "Feature executed")
        debug.endTimer("myNewFeature")
    end

    return true, "Success message"
end

-- 2. Export in interface
return {
    interface = {
        myNewFeature = myNewFeature,
        -- ... other functions
    },
}

-- 3. Add UI in player.lua
local function showMyFeatureMenu()
    -- Create UI elements
end

-- 4. Add to main menu
createButton("My Feature", function()
    showMyFeatureMenu()
end)

-- 5. Add test in test_suite.lua
local function test_my_new_feature()
    local machine = getMachine()
    local result = machine.myNewFeature(testItem, testActor)
    assert_true(result, "Feature should succeed")
end

-- 6. Run tests
-- Console: em_test
```

### 4. Adding Localization

**Add new strings:**

```lua
-- l10n/EnchantMachine/en.lua
return {
    -- Existing strings...

    my_feature_name = "My Feature",
    my_feature_desc = "Description of my feature",
}

-- In settings registration:
{
    key = 'myFeature',
    name = 'my_feature_name',  -- References l10n
    description = 'my_feature_desc',
    -- ...
}
```

**Add new language:**

```lua
-- l10n/EnchantMachine/de.lua
return {
    my_feature_name = "Meine Funktion",
    my_feature_desc = "Beschreibung meiner Funktion",
}
```

## API Reference

### Global Script Interface

```lua
local machine = core.getGlobalScript('EnchantMachine')

-- Soul Power Management
machine.getSoulPower() -> number
machine.addSoulPower(amount) -> newTotal
machine.subtractSoulPower(amount) -> (success, remaining)
machine.getSoulValue(creatureId) -> number

-- Item Operations
machine.depositSoul(item, actor) -> (success, message)
machine.rechargeItem(item, actor) -> (success, message)
machine.canBeEnchanted(item) -> (canEnchant, recordOrMessage)
machine.getItemCapacity(item) -> number
machine.getEffectiveEnchantCapacity(item) -> number

-- Upgrade Operations
machine.getUpgradedCapacity(itemRecordId) -> number
machine.upgradeItemCapacity(item, capacityIncrease) -> (success, message)

-- Settings
machine.getSettings() -> {
    enableMachine: boolean,
    enchantMultiplier: number,
    upgradeRatio: number,
    enableUpgradeFeature: boolean,
}
```

### Debug Script Interface

```lua
local debug = core.getGlobalScript('EnchantMachineDebug')

-- Logging
debug.error(category, message, data)
debug.warn(category, message, data)
debug.info(category, message, data)
debug.debug(category, message, data)
debug.trace(category, message, data)

-- Metrics
debug.incrementMetric(metricName)
debug.trackMetric(metricName, value)
debug.getMetrics() -> table

-- Performance
debug.startTimer(timerName)
debug.endTimer(timerName) -> elapsed
debug.getPerformance() -> table

-- Reporting
debug.generateReport() -> table
debug.formatReport() -> string

-- Validation
debug.validateSystemState(machineInterface) -> (isValid, message)
```

## Testing Guide

### Automated Tests

```bash
# Run all tests
em_test

# View test results
em_test_report

# Generate XML report (CI/CD)
em_test_xml
```

### Manual Testing

```bash
# Quick setup
em_give_gems
em_add_souls 10000
em_give_upgradeable

# Test specific feature
em_give_gems
# Activate machine -> Deposit Soul Gems

# Check state
em_status
em_debug_metrics

# Monitor performance
em_debug_perf
```

### Writing Tests

```lua
-- In test_suite.lua

local function test_my_feature()
    local machine = getMachine()

    -- Setup
    local initial = machine.getSoulPower()

    -- Execute
    machine.addSoulPower(100)

    -- Assert
    local final = machine.getSoulPower()
    assert_equal(final, initial + 100, "Power should increase")

    -- Cleanup
    machine.subtractSoulPower(100)
end

-- Register test
runTest("My Feature Test", test_my_feature)
```

## Performance Best Practices

### Do's:
✅ Use performance timers for new features
✅ Cache frequently accessed data
✅ Batch inventory operations
✅ Use early returns to avoid unnecessary work
✅ Clean up UI elements when closing menus

### Don'ts:
❌ Scan entire inventory every frame
❌ Create new objects in loops
❌ Use expensive operations in UI rendering
❌ Leave debug logging in production code
❌ Store large datasets in memory

### Example:

```lua
-- Bad: Scans every frame
function onUpdate()
    local items = getAllUpgradeableItems()
    -- ...
end

-- Good: Scan only when needed
function showUpgradeMenu()
    local items = getAllUpgradeableItems()
    -- ...
end
```

## Debugging Tips

### 1. Enable Debug Logging

```lua
-- Set log level
local debug = getDebug()
debug.setLogLevel("DEBUG")  -- or "TRACE" for more detail
```

### 2. Use Performance Timers

```lua
local debug = getDebug()
debug.startTimer("myOperation")
-- ... operation ...
local elapsed = debug.endTimer("myOperation")
print("Took " .. elapsed .. "s")
```

### 3. Validate System State

```lua
local debug = getDebug()
local machine = getMachine()
local isValid, message = debug.validateSystemState(machine)
if not isValid then
    print("System issue: " .. message)
end
```

### 4. Check Metrics

```lua
em_debug_metrics  -- Console command
```

### 5. View Logs

```lua
em_debug_logs  -- Console command
```

## Common Issues

### Issue: "Global script not found"
**Solution**: Ensure `EnchantMachine.omwscripts` is loaded
- Check `openmw.cfg` has: `lua-scripts=EnchantMachine.omwscripts`
- Verify file path is correct

### Issue: Scripts not reloading
**Solution**: Use `reloadlua` command
- Only works for unarchived files
- Restart OpenMW if using BSA

### Issue: UI doesn't appear
**Solution**: Check for errors
- Press F10 to view console log
- Look for Lua errors
- Verify script is attached to activator

### Issue: Settings not saving
**Solution**: Check storage permissions
- Ensure OpenMW has write access to config directory
- Use `permanentStorage = false` in settings

## Extending the Mod

### Adding Custom Items

```lua
-- Create custom soul gems
local customGem = world.createObject("misc_soulgem_common", 1)
local gemData = types.Miscellaneous.itemData(customGem)
gemData.soul = "dremora"
customGem:moveInto(playerInventory)
```

### Integrating with Quests

See `quest_example.lua` for complete example:

```lua
-- Listen for soul deposits
eventHandlers = {
    SoulDeposited = function(data)
        -- Your quest logic
    end,
}
```

### Custom Machine Placements

See `placement_helper.lua` for utilities:

```bash
em_place_help       # Show placement guide
em_place_locations  # List predefined locations
```

## CI/CD Integration

### Automated Testing

```bash
#!/bin/bash
# test.sh

# Start OpenMW headless (if available)
openmw --skip-menu --script-console

# Run tests via console
echo "em_test" | openmw-console

# Check exit code
if [ $? -eq 0 ]; then
    echo "Tests passed"
else
    echo "Tests failed"
    exit 1
fi
```

### Version Management

```lua
-- In global.lua onSave/onLoad
return {
    version = 2,  -- Increment when making breaking changes
}

-- Handle migrations
if data.version == 1 then
    -- Migrate from v1 to v2
    migrateData(data)
end
```

## Contributing

### Pull Request Checklist

- [ ] Code follows existing style
- [ ] Added debug logging for new features
- [ ] Added tests for new functionality
- [ ] Updated documentation
- [ ] Tested with `em_test`
- [ ] No performance regressions (`em_debug_perf`)
- [ ] Added localization strings
- [ ] Updated CHANGELOG

### Code Style

- Use 4 spaces for indentation
- Functions are `camelCase`
- Constants are `UPPER_SNAKE_CASE`
- Local variables are `lowerCase`
- Add comments for complex logic
- Use descriptive variable names

## Resources

- **OpenMW Lua Docs**: https://openmw.readthedocs.io/en/stable/reference/lua-scripting/
- **OpenMW Forums**: https://forum.openmw.org/
- **GitLab**: https://gitlab.com/OpenMW/openmw
- **Discord**: https://discord.gg/openmw

## Support

For bugs or feature requests:
1. Check existing issues
2. Provide OpenMW version
3. Include reproduction steps
4. Attach debug logs (`em_debug_logs`)
5. Share system validation (`em_status`)

---

**Last Updated:** 2025-01-08
**Mod Version:** 0.3.0-beta
**OpenMW Version:** 0.49+
