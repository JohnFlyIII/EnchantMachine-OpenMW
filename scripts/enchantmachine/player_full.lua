-- Player script for Dwemer Enchanting Machine
-- Handles UI, settings, and player interactions

local self = require('openmw.self')
local ui = require('openmw.ui')
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
local async = require('openmw.async')
local input = require('openmw.input')
local storage = require('openmw.storage')
local I = require('openmw.interfaces')

print("[EnchantMachine] Player script loading...")

-- Register settings page
I.Settings.registerPage({
    key = 'EnchantMachine',
    l10n = 'EnchantMachine',
    name = 'Dwemer Enchanting Machine',
    description = 'Configure the enchanting machine settings and view soul power',
})

-- Shared storage to read soul power (written by GLOBAL script, display cache only)
local sharedData = storage.globalSection('EnchantMachine_SharedData')

I.Settings.registerGroup({
    key = 'SettingsEnchantMachineStatus',
    page = 'EnchantMachine',
    l10n = 'EnchantMachine',
    name = 'Status',
    permanentStorage = false,
    settings = {
        {
            key = 'soulPowerDisplay',
            renderer = 'textLine',
            name = 'Soul Power',
            description = 'Current soul power in the bank (read-only display)',
            default = '0',
            argument = {
                disabled = true,
            },
        },
    },
})

-- Register settings
I.Settings.registerGroup({
    key = 'SettingsEnchantMachineConfig',
    page = 'EnchantMachine',
    l10n = 'EnchantMachine',
    name = 'Settings',
    permanentStorage = true,
    settings = {
        {
            key = 'enableMachine',
            renderer = 'checkbox',
            name = 'Enable Machine',
            description = 'Enable or disable the enchanting machine',
            default = true,
        },
        {
            key = 'enchantMultiplier',
            renderer = 'number',
            name = 'Enchant Multiplier',
            description = 'Multiplier for enchantment capacity (default: 10x)',
            default = 10,
            argument = {
                integer = true,
                min = 1,
                max = 100,
            },
        },
        {
            key = 'upgradeRatio',
            renderer = 'number',
            name = 'Upgrade Ratio',
            description = 'Soul power cost per capacity point (default: 100:1)',
            default = 100,
            argument = {
                integer = true,
                min = 1,
                max = 1000,
            },
        },
        {
            key = 'enableUpgradeFeature',
            renderer = 'checkbox',
            name = 'Enable Upgrades',
            description = 'Allow upgrading item enchantment capacity',
            default = false,
        },
        {
            key = 'howToAccess',
            renderer = 'textLine',
            name = 'How to Access Machine',
            description = 'Activate a machine object with script attached, OR use lua player console to send event',
            default = 'See description',
            argument = {
                disabled = true,
            },
        },
    },
})

print("[EnchantMachine] Player script registered settings pages")

-- State
local currentMenu = nil
local menuMode = false
local statusSettings = storage.playerSection('SettingsEnchantMachineStatus')
local configSettings = storage.playerSection('SettingsEnchantMachineConfig')
local updateTimer = 0
local updateInterval = 1.0

-- Helper: Set pause/menu mode
local function setMenuMode(enabled)
    menuMode = enabled
    if core.API_REVISION > 30 then
        if enabled then
            I.UI.setMode('Interface', { windows = {} })
        else
            I.UI.setMode()
        end
    end
end

-- Helper: Get current settings
local function getSettings()
    return {
        enableMachine = configSettings:get('enableMachine'),
        enchantMultiplier = configSettings:get('enchantMultiplier'),
        upgradeRatio = configSettings:get('upgradeRatio'),
        enableUpgradeFeature = configSettings:get('enableUpgradeFeature'),
    }
end

-- Helper: Get soul power (read from shared storage)
local function getSoulPower()
    return sharedData:get('soulPower') or 0
end

-- Helper: Close current menu
local function closeMenu()
    if currentMenu then
        pcall(function() currentMenu:destroy() end)
        currentMenu = nil
    end
    setMenuMode(false)
end

-- Helper: Get filled soul gems
local function getFilledSoulGems()
    local inventory = types.Actor.inventory(self)
    local soulGems = {}

    for _, item in ipairs(inventory:getAll()) do
        if types.Miscellaneous.objectIsInstance(item) then
            local itemData = types.Miscellaneous.itemData(item)
            if itemData and itemData.soul then
                local record = types.Miscellaneous.record(item)

                -- PLAYER scripts can't access creature records, so show gem capacity
                -- The actual soul value will be calculated by GLOBAL script during deposit
                local gemCapacity = 0
                if record then
                    local id = record.id:lower()
                    if id:find("grand") or id:find("azura") then
                        gemCapacity = 600
                    elseif id:find("greater") then
                        gemCapacity = 300
                    elseif id:find("common") then
                        gemCapacity = 150
                    elseif id:find("lesser") then
                        gemCapacity = 100
                    elseif id:find("petty") then
                        gemCapacity = 50
                    else
                        gemCapacity = 100 -- default fallback
                    end
                end

                table.insert(soulGems, {
                    item = item,
                    record = record,
                    soul = itemData.soul,
                    soulValue = gemCapacity,  -- Display gem capacity (not actual soul value)
                })
            end
        end
    end

    return soulGems
end

-- Helper: Get rechargeable items
local function getRechargeableItems()
    local inventory = types.Actor.inventory(self)
    local items = {}

    for _, item in ipairs(inventory:getAll()) do
        local isWeapon = types.Weapon.objectIsInstance(item)
        local isArmor = types.Armor.objectIsInstance(item)
        local isClothing = types.Clothing.objectIsInstance(item)

        if isWeapon or isArmor or isClothing then
            local record
            if isWeapon then
                record = types.Weapon.record(item)
            elseif isArmor then
                record = types.Armor.record(item)
            else
                record = types.Clothing.record(item)
            end

            if record and record.enchant and record.enchant ~= "" then
                local itemData
                if isWeapon then
                    itemData = types.Weapon.itemData(item)
                elseif isArmor then
                    itemData = types.Armor.itemData(item)
                else
                    itemData = types.Clothing.itemData(item)
                end

                local enchantment = core.magic.enchantments.records[record.enchant]
                if enchantment then
                    local maxCharge = enchantment.charge or 0
                    local currentCharge = (itemData and itemData.enchantmentCharge) or maxCharge

                    if currentCharge < maxCharge then
                        table.insert(items, {
                            item = item,
                            record = record,
                            currentCharge = currentCharge,
                            maxCharge = maxCharge,
                        })
                    end
                end
            end
        end
    end

    return items
end

-- Helper: Create button
local function createButton(text, onClick, enabled)
    enabled = enabled == nil and true or enabled

    return {
        template = I.MWUI.templates.box,
        props = {
            alpha = enabled and 1.0 or 0.5,
        },
        content = ui.content{
            {
                type = ui.TYPE.Text,
                template = I.MWUI.templates.textNormal,
                props = {
                    text = text,
                    textSize = 16,
                    textColor = enabled and util.color.rgb(1, 1, 1) or util.color.rgb(0.6, 0.6, 0.6),
                },
            },
        },
        events = enabled and {
            mouseClick = async:callback(onClick),
        } or {},
    }
end

-- Show deposit menu
local function showDepositMenu()
    closeMenu()

    print("[EnchantMachine] showDepositMenu called")
    local soulGems = getFilledSoulGems()
    print("[EnchantMachine] Found " .. #soulGems .. " soul gems")

    if #soulGems == 0 then
        ui.showMessage("You have no filled soul gems to deposit.")
        async:newUnsavableSimulationTimer(1.5, function()
            createMainMenu()
        end)
        return
    end

    setMenuMode(true)

    local menuContent = {
        -- Title
        {
            template = I.MWUI.templates.boxSolid,
            content = ui.content{
                {
                    type = ui.TYPE.Text,
                    template = I.MWUI.templates.textHeader,
                    props = {
                        text = "Deposit Soul Gems",
                        textSize = 20,
                    },
                },
            },
        },
        -- Info
        {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                text = "Select a soul gem to deposit. Gems are consumed permanently.",
                textSize = 14,
            },
        },
        -- Spacing
        {
            type = ui.TYPE.Flex,
            props = {
                size = util.vector2(0, 10),
            },
        },
    }

    -- Add gem buttons
    for _, gemData in ipairs(soulGems) do
        local gemName = gemData.record.name or "Soul Gem"
        local soulName = gemData.soul or "Unknown"

        table.insert(menuContent, createButton(
            gemName .. " (" .. soulName .. ")",
            function()
                -- Send event to global script to deposit
                core.sendGlobalEvent('EnchantMachine_DepositGem', {
                    actor = self.object,
                    item = gemData.item,
                    settings = getSettings(),
                })
                ui.showMessage("Depositing soul gem...")
                closeMenu()
            end
        ))
    end

    -- Spacing
    table.insert(menuContent, {
        type = ui.TYPE.Flex,
        props = {
            size = util.vector2(0, 10),
        },
    })

    -- Back button
    table.insert(menuContent, createButton("Back", function()
        createMainMenu()
    end))

    local menu = ui.create{
        layer = 'Windows',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = util.vector2(0.5, 0.5),
            anchor = util.vector2(0.5, 0.5),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = {
                    vertical = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content(menuContent),
            },
        },
    }

    print("[EnchantMachine] Created deposit menu")
    currentMenu = menu
end

-- Show recharge menu
local function showRechargeMenu()
    closeMenu()

    local items = getRechargeableItems()

    if #items == 0 then
        ui.showMessage("You have no enchanted items that need recharging.")
        async:newUnsavableSimulationTimer(1.5, function()
            createMainMenu()
        end)
        return
    end

    setMenuMode(true)
    local soulPower = getSoulPower()
    local menuContent = {
        -- Title
        {
            template = I.MWUI.templates.boxSolid,
            content = ui.content{
                {
                    type = ui.TYPE.Text,
                    template = I.MWUI.templates.textHeader,
                    props = {
                        text = "Recharge Enchanted Items",
                        textSize = 20,
                    },
                },
            },
        },
        -- Info
        {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                text = "Soul Power: " .. math.floor(soulPower) .. " | Cost: 1 power per charge point",
                textSize = 14,
            },
        },
        -- Spacing
        {
            type = ui.TYPE.Flex,
            props = {
                size = util.vector2(0, 10),
            },
        },
    }

    -- Add item buttons
    for _, itemData in ipairs(items) do
        local itemName = itemData.record.name or "Item"
        local current = math.floor(itemData.currentCharge)
        local max = math.floor(itemData.maxCharge)
        local needed = math.ceil(itemData.maxCharge - itemData.currentCharge)
        local canAfford = soulPower >= needed

        local buttonText = string.format("%s (%d/%d) - %d power needed",
            itemName, current, max, needed)

        table.insert(menuContent, createButton(
            buttonText,
            function()
                core.sendGlobalEvent('EnchantMachine_RechargeItem', {
                    actor = self.object,
                    item = itemData.item,
                    settings = getSettings(),
                })
                ui.showMessage("Recharging item...")
                closeMenu()
            end,
            canAfford
        ))
    end

    -- Spacing
    table.insert(menuContent, {
        type = ui.TYPE.Flex,
        props = {
            size = util.vector2(0, 10),
        },
    })

    -- Back button
    table.insert(menuContent, createButton("Back", function()
        createMainMenu()
    end))

    local menu = ui.create{
        layer = 'Windows',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = util.vector2(0.5, 0.5),
            anchor = util.vector2(0.5, 0.5),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = {
                    vertical = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content(menuContent),
            },
        },
    }

    currentMenu = menu
end

-- Forward declarations for functions defined later
local showUpgradeAmountMenu
local createMainMenu

-- Show upgrade menu (item selection)
local function showUpgradeMenu()
    closeMenu()
    setMenuMode(true)

    local settings = getSettings()
    if not settings.enableUpgradeFeature then
        ui.showMessage("Upgrade feature is locked. Enable it in settings!")
        async:newUnsavableSimulationTimer(1.5, function()
            createMainMenu()
        end)
        return
    end

    -- Get upgradeable items (weapons, armor, clothing with enchant capacity)
    local inventory = types.Actor.inventory(self)
    local items = {}

    for _, item in ipairs(inventory:getAll()) do
        local isWeapon = types.Weapon.objectIsInstance(item)
        local isArmor = types.Armor.objectIsInstance(item)
        local isClothing = types.Clothing.objectIsInstance(item)

        if isWeapon or isArmor or isClothing then
            local record
            if isWeapon then
                record = types.Weapon.record(item)
            elseif isArmor then
                record = types.Armor.record(item)
            else
                record = types.Clothing.record(item)
            end

            -- Only include unenchanted items (can't upgrade enchanted items)
            if record and record.enchantCapacity and record.enchantCapacity > 0 then
                if not record.enchant or record.enchant == "" then
                    table.insert(items, {
                        item = item,
                        record = record,
                    })
                end
            end
        end
    end

    if #items == 0 then
        ui.showMessage("You have no items that can be upgraded.")
        async:newUnsavableSimulationTimer(1.5, function()
            createMainMenu()
        end)
        return
    end

    local soulPower = getSoulPower()
    local ratio = settings.upgradeRatio or 100

    local menuContent = {
        -- Title
        {
            template = I.MWUI.templates.boxSolid,
            content = ui.content{
                {
                    type = ui.TYPE.Text,
                    template = I.MWUI.templates.textHeader,
                    props = {
                        text = "Upgrade Item Capacity",
                        textSize = 20,
                    },
                },
            },
        },
        -- Info
        {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                text = string.format("Soul Power: %d | Cost: %d power per capacity point",
                    math.floor(soulPower), ratio),
                textSize = 14,
            },
        },
        -- Warning about unenchanted items only
        {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                text = "Note: Only unenchanted items can be upgraded. Upgrade before enchanting!",
                textSize = 12,
                textColor = util.color.rgb(1, 1, 0),
            },
        },
        -- Spacing
        {
            type = ui.TYPE.Flex,
            props = {
                size = util.vector2(0, 10),
            },
        },
    }

    -- Add item buttons
    for _, itemData in ipairs(items) do
        local itemName = itemData.record.name or "Item"
        local capacity = math.floor(itemData.record.enchantCapacity or 0)

        table.insert(menuContent, createButton(
            string.format("%s (Capacity: %d)", itemName, capacity),
            function()
                showUpgradeAmountMenu(itemData, ratio, soulPower)
            end
        ))
    end

    -- Spacing
    table.insert(menuContent, {
        type = ui.TYPE.Flex,
        props = {
            size = util.vector2(0, 10),
        },
    })

    -- Back button
    table.insert(menuContent, createButton("Back", function()
        createMainMenu()
    end))

    local menu = ui.create{
        layer = 'Windows',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = util.vector2(0.5, 0.5),
            anchor = util.vector2(0.5, 0.5),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = {
                    vertical = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content(menuContent),
            },
        },
    }

    currentMenu = menu
end

-- Show upgrade amount selection menu
showUpgradeAmountMenu = function(itemData, ratio, soulPower)
    closeMenu()
    setMenuMode(true)

    local itemName = itemData.record.name or "Item"
    local currentCapacity = math.floor(itemData.record.enchantCapacity or 0)

    local menuContent = {
        -- Title
        {
            template = I.MWUI.templates.boxSolid,
            content = ui.content{
                {
                    type = ui.TYPE.Text,
                    template = I.MWUI.templates.textHeader,
                    props = {
                        text = "Upgrade: " .. itemName,
                        textSize = 20,
                    },
                },
            },
        },
        -- Info
        {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                text = string.format("Current Capacity: %d | Soul Power: %d",
                    currentCapacity, math.floor(soulPower)),
                textSize = 14,
            },
        },
        -- Spacing
        {
            type = ui.TYPE.Flex,
            props = {
                size = util.vector2(0, 10),
            },
        },
    }

    -- Upgrade options
    local upgradeOptions = {1, 5, 10, 25, 50, 100}

    for _, amount in ipairs(upgradeOptions) do
        local cost = amount * ratio
        local canAfford = soulPower >= cost
        local newCapacity = currentCapacity + amount

        table.insert(menuContent, createButton(
            string.format("+%d capacity (%d power) → %d total",
                amount, cost, newCapacity),
            function()
                core.sendGlobalEvent('EnchantMachine_UpgradeItem', {
                    actor = self.object,
                    item = itemData.item,
                    amount = amount,
                    settings = getSettings(),
                })
                ui.showMessage("Upgrading item...")
                closeMenu()
            end,
            canAfford
        ))
    end

    -- Spacing
    table.insert(menuContent, {
        type = ui.TYPE.Flex,
        props = {
            size = util.vector2(0, 10),
        },
    })

    -- Back button
    table.insert(menuContent, createButton("Back", function()
        showUpgradeMenu()
    end))

    local menu = ui.create{
        layer = 'Windows',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = util.vector2(0.5, 0.5),
            anchor = util.vector2(0.5, 0.5),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = {
                    vertical = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content(menuContent),
            },
        },
    }

    currentMenu = menu
end

-- Create main menu
createMainMenu = function()
    closeMenu()

    local soulPower = getSoulPower()
    local settings = getSettings()

    setMenuMode(true)

    -- Build menu content
    local menuContent = {}

    -- Title
    table.insert(menuContent, {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textHeader,
        props = {
            text = "Dwemer Enchanting Machine",
            textSize = 30,
        },
    })

    -- Soul power display
    table.insert(menuContent, {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = {
            text = "Soul Power: " .. math.floor(soulPower),
            textSize = 20,
        },
    })

    -- Spacing
    table.insert(menuContent, {
        type = ui.TYPE.Flex,
        props = {
            size = util.vector2(0, 20),
        },
    })

    -- Deposit button
    table.insert(menuContent, createButton("Deposit Soul Gems", function()
        showDepositMenu()
    end))

    -- Recharge button
    table.insert(menuContent, createButton("Recharge Enchanted Items", function()
        showRechargeMenu()
    end))

    -- Upgrade button (or locked message)
    if settings.enableUpgradeFeature then
        table.insert(menuContent, createButton("Upgrade Item Capacity", function()
            showUpgradeMenu()
        end))
    else
        table.insert(menuContent, {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = {
                text = "[Upgrade Capacity - Locked]",
                textSize = 18,
                textColor = util.color.rgb(0.5, 0.5, 0.5),
            },
        })
    end

    -- Spacing
    table.insert(menuContent, {
        type = ui.TYPE.Flex,
        props = {
            size = util.vector2(0, 20),
        },
    })

    -- Exit button
    table.insert(menuContent, createButton("Exit", function()
        closeMenu()
    end))

    -- Create the menu
    local menu = ui.create{
        layer = 'Windows',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = util.vector2(0.5, 0.5),
            anchor = util.vector2(0.5, 0.5),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                props = {
                    vertical = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content(menuContent),
            },
        },
    }

    print("[EnchantMachine] Created main menu")
    currentMenu = menu
end

-- Update loop
local function onUpdate(dt)
    -- Update soul power display in settings
    updateTimer = updateTimer + dt
    if updateTimer >= updateInterval then
        updateTimer = 0
        local soulPower = getSoulPower()
        statusSettings:set('soulPowerDisplay', tostring(math.floor(soulPower)))
    end
end

-- Key press handler
local function onKeyPress(key)
    -- Close menu on ESC
    if key.symbol == 'Escape' and currentMenu then
        closeMenu()
        return
    end
end

-- Event handler for results from global script
local function onMachineResult(eventData)
    if eventData.success then
        ui.showMessage(eventData.message)
    else
        ui.showMessage("Error: " .. eventData.message)
    end

    -- Reopen main menu after operation completes
    async:newUnsavableSimulationTimer(1.5, function()
        createMainMenu()
    end)
end

-- Boss spawn detection: track cell changes
local lastCellName = nil
local BOSS_CELL_NAME = "Arkngthand, Deep Ore Passage"
local bossSpawnRequested = false

local function checkBossCellEntry()
    -- Get current cell name
    local currentCell = self.object.cell
    if not currentCell then return end

    local currentCellName = currentCell.name or ""

    -- Check if cell changed
    if currentCellName ~= lastCellName then
        print("[EnchantMachine] Player changed cells: " .. currentCellName)
        lastCellName = currentCellName

        -- Check if entered boss cell
        if not bossSpawnRequested and currentCellName == BOSS_CELL_NAME then
            print("[EnchantMachine] Player entered boss cell! Requesting spawn...")
            bossSpawnRequested = true
            core.sendGlobalEvent('EnchantMachine_SpawnBoss', {})
        end
    end
end

print("[EnchantMachine] Player script loaded successfully")

return {
    engineHandlers = {
        onUpdate = function(dt)
            checkBossCellEntry()
            onUpdate(dt)
        end,
        onKeyPress = onKeyPress,
        onInactive = function()
            closeMenu()
        end,
    },
    eventHandlers = {
        EnchantMachine_Result = onMachineResult,
        EnchantMachine_OpenMenu = function(eventData)
            print("[EnchantMachine] Received OpenMenu event!")
            ui.showMessage("The ancient Dwemer machine hums to life, its crystalline interface beginning to shimmer with ethereal light...")

            -- Brief delay for atmospheric effect
            async:newUnsavableSimulationTimer(1.5, function()
                local ok, err = pcall(function()
                    createMainMenu()
                end)
                if not ok then
                    print("[EnchantMachine] ERROR creating menu:", err)
                    ui.showMessage("The machine sputters and falls silent... Something went wrong.")
                else
                    print("[EnchantMachine] Menu opened successfully!")
                end
            end)
        end,
        -- KEY FIX: OpenMW fires this when UI mode changes (e.g., ESC pressed)
        UiModeChanged = function(data)
            -- When mode becomes nil, Interface mode was exited (ESC pressed)
            if currentMenu and data.newMode == nil then
                print("[EnchantMachine] UI mode exited (ESC pressed), cleaning up menu")
                closeMenu()
            end
        end,
    },
}
