-- Global script for Dwemer Enchanting Machine
-- Manages soul power bank, settings, enchanting, recharging, and upgrades

local storage = require('openmw.storage')
local core = require('openmw.core')
local types = require('openmw.types')
local world = require('openmw.world')
local I = require('openmw.interfaces')

-- Debug system reference (will be available after debug.lua loads)
local function getDebug()
    -- Access debug interface via I.EnchantMachineDebug
    return I.EnchantMachineDebug
end

-- In-memory data (saved/loaded with save file)
local soulPower = 0
local upgradedItems = {}
local itemBaseRecords = {}  -- Maps upgraded item ID -> original base record ID

-- Shared storage for PLAYER script to read (just a display cache)
local sharedData = storage.globalSection('EnchantMachine_SharedData')

-- Settings storage (shared between PLAYER and GLOBAL)
local settingsData = storage.globalSection('EnchantMachine_Settings')

-- Update shared storage when soul power changes (for UI display)
local function updateSharedData()
    sharedData:set('soulPower', soulPower)
end

-- Default settings (fallback values)
local defaultSettings = {
    enableMachine = true,
    enchantMultiplier = 10,
    upgradeRatio = 100,
    enableUpgradeFeature = false,
}

-- Initialize settings with defaults
local function ensureSettings()
    for key, value in pairs(defaultSettings) do
        if settingsData:get(key) == nil then
            settingsData:set(key, value)
        end
    end
end

-- Helper function to get settings
local function getSettings()
    ensureSettings()
    return {
        enableMachine = settingsData:get('enableMachine'),
        enchantMultiplier = settingsData:get('enchantMultiplier'),
        upgradeRatio = settingsData:get('upgradeRatio'),
        enableUpgradeFeature = settingsData:get('enableUpgradeFeature'),
    }
end

-- Helper function to update a setting (deprecated - use settings UI instead)
local function setSetting(key, value)
    local debug = getDebug()
    if debug then
        debug.warn("Settings", "setSetting() is deprecated. Please use the settings UI: Options → Scripts → Dwemer Enchanting Machine")
    end
    return false, "Settings can only be changed through the UI (Options → Scripts → Dwemer Enchanting Machine)"
end

-- Get current soul power in the bank
local function getSoulPower()
    return soulPower
end

-- Add soul power to the bank
local function addSoulPower(amount)
    soulPower = soulPower + amount
    updateSharedData()
    local debug = getDebug()
    if debug then debug.info("SoulPower", "Added " .. amount .. ", total now: " .. soulPower) end
    return soulPower
end

-- Subtract soul power from the bank (returns success, newTotal)
local function subtractSoulPower(amount)
    if soulPower >= amount then
        soulPower = soulPower - amount
        updateSharedData()
        return true, soulPower
    end
    return false, soulPower
end

-- Reset soul power to zero (useful for testing)
local function resetSoulPower()
    soulPower = 0
    updateSharedData()
    local debug = getDebug()
    if debug then debug.info("SoulPower", "Soul power reset to 0") end
    return 0
end

-- Get soul value from a creature record ID
local function getSoulValue(creatureId)
    if not creatureId or creatureId == "" then return 0 end

    -- Use types.Creature.records to look up creature
    local ok, record = pcall(function()
        return types.Creature.records[creatureId]
    end)

    if ok and record then
        -- Record is userdata, access soulValue directly
        local soulOk, soulValue = pcall(function()
            return record.soulValue
        end)

        if soulOk and soulValue and soulValue > 0 then
            print(string.format("[EnchantMachine] Soul value for '%s': %d", creatureId, soulValue))
            return soulValue
        end
    end

    print(string.format("[EnchantMachine] Could not get soul value for '%s', returning 0", creatureId))
    return 0
end

-- Check if an item can be enchanted
local function canBeEnchanted(item)
    if not item then return false end

    -- Check if it's a valid enchantable type
    local isWeapon = types.Weapon.objectIsInstance(item)
    local isArmor = types.Armor.objectIsInstance(item)
    local isClothing = types.Clothing.objectIsInstance(item)

    if not (isWeapon or isArmor or isClothing) then
        return false, "Only weapons, armor, and clothing can be enchanted"
    end

    -- Get the record
    local record
    if isWeapon then
        record = types.Weapon.record(item)
    elseif isArmor then
        record = types.Armor.record(item)
    else
        record = types.Clothing.record(item)
    end

    if not record then
        return false, "Invalid item"
    end

    -- Check if item already has an enchantment
    if record.enchant and record.enchant ~= "" then
        return false, "Item is already enchanted"
    end

    -- Check if item has enchant capacity
    if not record.enchantCapacity or record.enchantCapacity <= 0 then
        return false, "Item cannot hold enchantments"
    end

    return true, record
end

-- Get item's enchantment capacity (including upgrades)
local function getItemCapacity(item)
    local isWeapon = types.Weapon.objectIsInstance(item)
    local isArmor = types.Armor.objectIsInstance(item)
    local isClothing = types.Clothing.objectIsInstance(item)

    if not (isWeapon or isArmor or isClothing) then
        return 0
    end

    local record
    if isWeapon then
        record = types.Weapon.record(item)
    elseif isArmor then
        record = types.Armor.record(item)
    else
        record = types.Clothing.record(item)
    end

    if not record then return 0 end

    local baseCapacity = record.enchantCapacity or 0
    local upgrade = getUpgradedCapacity(item.recordId)

    return baseCapacity + upgrade
end

-- Deposit soul from a soul gem (consumes the item)
local function depositSoul(item, actor, settings)
    local debug = getDebug()
    if debug then debug.startTimer("depositSoul") end

    settings = settings or getSettings()
    if not settings.enableMachine then
        if debug then
            debug.warn("Deposit", "Machine is disabled")
            debug.endTimer("depositSoul")
        end
        return false, "Machine is disabled"
    end

    if not types.Miscellaneous.objectIsInstance(item) then
        if debug then
            debug.warn("Deposit", "Invalid item type")
            debug.endTimer("depositSoul")
        end
        return false, "Not a soul gem"
    end

    local itemData = types.Miscellaneous.itemData(item)
    if not itemData or not itemData.soul then
        if debug then
            debug.warn("Deposit", "No soul in gem")
            debug.endTimer("depositSoul")
        end
        return false, "No soul in this item"
    end

    local soulValue = getSoulValue(itemData.soul)
    if soulValue <= 0 then
        if debug then
            debug.error("Deposit", "Invalid soul value", soulValue)
            debug.endTimer("depositSoul")
        end
        return false, "Invalid soul"
    end

    -- Remove the soul gem from inventory
    item:remove()

    -- Add soul power to bank
    local newTotal = addSoulPower(soulValue)

    if debug then
        debug.info("Deposit", "Deposited " .. soulValue .. " soul power")
        debug.incrementMetric("totalDeposits")
        debug.trackMetric("totalSoulPowerAdded", soulValue)
        debug.endTimer("depositSoul")
    end

    return true, "Deposited " .. soulValue .. " soul power. Total: " .. newTotal
end

-- Recharge an enchanted item using soul power
local function rechargeItem(item, actor, settings)
    local debug = getDebug()
    if debug then debug.startTimer("rechargeItem") end

    settings = settings or getSettings()
    if not settings.enableMachine then
        if debug then
            debug.warn("Recharge", "Machine is disabled")
            debug.endTimer("rechargeItem")
        end
        return false, "Machine is disabled"
    end

    -- Check if it's an enchantable item type
    local isWeapon = types.Weapon.objectIsInstance(item)
    local isArmor = types.Armor.objectIsInstance(item)
    local isClothing = types.Clothing.objectIsInstance(item)

    if not (isWeapon or isArmor or isClothing) then
        return false, "This item cannot be recharged"
    end

    -- Get the record
    local record
    if isWeapon then
        record = types.Weapon.record(item)
    elseif isArmor then
        record = types.Armor.record(item)
    else
        record = types.Clothing.record(item)
    end

    if not record or not record.enchant or record.enchant == "" then
        return false, "Item is not enchanted"
    end

    -- Get enchantment data
    local enchantment = core.magic.enchantments.records[record.enchant]
    if not enchantment then
        return false, "Invalid enchantment"
    end

    -- Get item data to check current charge
    local itemData
    if isWeapon then
        itemData = types.Weapon.itemData(item)
    elseif isArmor then
        itemData = types.Armor.itemData(item)
    else
        itemData = types.Clothing.itemData(item)
    end

    local maxCharge = enchantment.charge or 0
    local currentCharge = (itemData and itemData.enchantmentCharge) or maxCharge

    if currentCharge >= maxCharge then
        return false, "Item is already fully charged (" .. math.floor(currentCharge) .. "/" .. math.floor(maxCharge) .. ")"
    end

    local chargeNeeded = maxCharge - currentCharge
    local soulPowerNeeded = math.ceil(chargeNeeded) -- 1:1 ratio for recharging

    -- Check if we have enough soul power
    local success, remaining = subtractSoulPower(soulPowerNeeded)
    if not success then
        return false, "Not enough soul power (need " .. soulPowerNeeded .. ", have " .. remaining .. ")"
    end

    -- Recharge the item
    if not itemData then
        if debug then
            debug.error("Recharge", "Item has no itemData - cannot set charge")
            debug.endTimer("rechargeItem")
        end
        return false, "Item cannot store charge data"
    end

    itemData.enchantmentCharge = maxCharge

    if debug then
        debug.info("Recharge", "Recharged item using " .. soulPowerNeeded .. " soul power")
        debug.incrementMetric("totalRecharges")
        debug.trackMetric("totalSoulPowerSpent", soulPowerNeeded)
        debug.endTimer("rechargeItem")
    end

    return true, "Recharged to " .. math.floor(maxCharge) .. "/" .. math.floor(maxCharge) .. ". Soul power remaining: " .. remaining
end

-- Get upgraded capacity for an item
local function getUpgradedCapacity(itemRecordId)
    return upgradedItems[itemRecordId] or 0
end

-- Set upgraded capacity for an item
local function setUpgradedCapacity(itemRecordId, additionalCapacity)
    upgradedItems[itemRecordId] = additionalCapacity
end

-- Upgrade an item's enchantment capacity (FUNCTIONAL - creates new record)
local function upgradeItemCapacity(item, capacityIncrease, actor, settings)
    local debug = getDebug()
    if debug then debug.startTimer("upgradeItemCapacity") end

    settings = settings or getSettings()
    if not settings.enableUpgradeFeature then
        if debug then debug.endTimer("upgradeItemCapacity") end
        return false, "Upgrade feature is not unlocked"
    end

    if capacityIncrease <= 0 then
        if debug then debug.endTimer("upgradeItemCapacity") end
        return false, "Increase must be positive"
    end

    -- Validate item type
    if not (types.Weapon.objectIsInstance(item) or types.Armor.objectIsInstance(item) or types.Clothing.objectIsInstance(item)) then
        if debug then debug.endTimer("upgradeItemCapacity") end
        return false, "Only weapons, armor, and clothing can be upgraded"
    end

    -- Get record
    local record
    if types.Weapon.objectIsInstance(item) then
        record = types.Weapon.record(item)
    elseif types.Armor.objectIsInstance(item) then
        record = types.Armor.record(item)
    else
        record = types.Clothing.record(item)
    end

    if not record or not record.enchantCapacity or record.enchantCapacity <= 0 then
        if debug then debug.endTimer("upgradeItemCapacity") end
        return false, "Item cannot hold enchantments"
    end

    -- Check if item is already enchanted (CRITICAL: can't upgrade enchanted items)
    if record.enchant and record.enchant ~= "" then
        if debug then debug.endTimer("upgradeItemCapacity") end
        return false, "Cannot upgrade enchanted items. Only unenchanted items can be upgraded."
    end

    -- Calculate cost
    local ratio = settings.upgradeRatio or 100
    local soulCost = capacityIncrease * ratio

    -- Check and deduct soul power
    local success, newTotal = subtractSoulPower(soulCost)
    if not success then
        if debug then debug.endTimer("upgradeItemCapacity") end
        return false, "Not enough soul power (need " .. soulCost .. ", have " .. newTotal .. ")"
    end

    -- Get the base record ID (original unupgraded item)
    -- First check if we have a stored mapping (for generated IDs)
    local baseRecordId = itemBaseRecords[item.recordId]

    -- If not found, try pattern matching (for _cap### IDs)
    if not baseRecordId then
        baseRecordId = item.recordId:match("^(.-)_cap%d+$")
    end

    -- If still not found, this is the base item
    if not baseRecordId then
        baseRecordId = item.recordId
    end

    -- Get total upgrade amount for this base item
    local currentUpgrade = getUpgradedCapacity(baseRecordId)

    -- Get original base capacity (from the base record, not current item)
    local baseCapacity
    if types.Weapon.objectIsInstance(item) then
        local baseRecord = types.Weapon.records[baseRecordId]
        baseCapacity = baseRecord.enchantCapacity
    elseif types.Armor.objectIsInstance(item) then
        local baseRecord = types.Armor.records[baseRecordId]
        baseCapacity = baseRecord.enchantCapacity
    else
        local baseRecord = types.Clothing.records[baseRecordId]
        baseCapacity = baseRecord.enchantCapacity
    end

    -- Calculate new capacity: original base + previous upgrades + new upgrade
    local newCapacity = baseCapacity + currentUpgrade + capacityIncrease

    -- Generate unique record ID based on BASE record, not current item
    local newRecordId = baseRecordId .. "_cap" .. math.floor(newCapacity)

    -- Check if record already exists
    local recordExists = false
    local checkOk, existingRecord = pcall(function()
        if types.Weapon.objectIsInstance(item) then
            return types.Weapon.records[newRecordId]
        elseif types.Armor.objectIsInstance(item) then
            return types.Armor.records[newRecordId]
        else
            return types.Clothing.records[newRecordId]
        end
    end)

    recordExists = checkOk and existingRecord ~= nil

    -- Create new record if it doesn't exist
    if not recordExists then
        if debug then debug.info("Upgrade", "Creating new record: " .. newRecordId) end

        local draft
        if types.Weapon.objectIsInstance(item) then
            draft = types.Weapon.createRecordDraft({
                template = record,
                id = newRecordId,
                enchantCapacity = newCapacity,
            })
        elseif types.Armor.objectIsInstance(item) then
            draft = types.Armor.createRecordDraft({
                template = record,
                id = newRecordId,
                enchantCapacity = newCapacity,
            })
        else -- Clothing
            draft = types.Clothing.createRecordDraft({
                template = record,
                id = newRecordId,
                enchantCapacity = newCapacity,
            })
        end

        -- Register the new record in the world database
        local createdRecord = world.createRecord(draft)

        -- Get the actual ID from the created record (might be modified by engine)
        newRecordId = createdRecord.id

        -- Store mapping from generated ID -> base record ID (for future upgrades)
        itemBaseRecords[newRecordId] = baseRecordId

        if debug then debug.info("Upgrade", "Created record with capacity " .. newCapacity .. ", ID: " .. newRecordId .. " -> base: " .. baseRecordId) end
    end

    -- Create new item instance from upgraded record (use ID string)
    local newItem = world.createObject(newRecordId, 1)

    -- Copy item data from old to new
    local oldData, newData

    if types.Weapon.objectIsInstance(item) then
        oldData = types.Weapon.itemData(item)
        newData = types.Weapon.itemData(newItem)
    elseif types.Armor.objectIsInstance(item) then
        oldData = types.Armor.itemData(item)
        newData = types.Armor.itemData(newItem)
    else
        oldData = types.Clothing.itemData(item)
        newData = types.Clothing.itemData(newItem)
    end

    -- Copy condition and charges if they exist
    if oldData and newData then
        if oldData.condition then
            newData.condition = oldData.condition
        end
        if oldData.enchantmentCharge then
            newData.enchantmentCharge = oldData.enchantmentCharge
        end
    end

    -- Add new item to actor's inventory
    if actor and types.Actor.objectIsInstance(actor) then
        newItem:moveInto(types.Actor.inventory(actor))
    end

    -- Remove old item
    item:remove()

    -- Update tracking (store total upgrade amount for BASE record)
    setUpgradedCapacity(baseRecordId, newCapacity - baseCapacity)

    if debug then
        debug.info("Upgrade", "Upgraded " .. record.name .. " from base " .. baseCapacity .. " to " .. newCapacity .. " (base: " .. baseRecordId .. ")")
        debug.incrementMetric("totalUpgrades")
        debug.endTimer("upgradeItemCapacity")
    end

    -- Show current capacity -> new capacity in message (not base capacity)
    return true, "Upgraded " .. record.name .. " capacity from " .. math.floor(record.enchantCapacity) .. " to " .. math.floor(newCapacity) .. ". Soul power remaining: " .. math.floor(newTotal)
end

-- Calculate effective enchantment capacity for new enchantments
local function getEffectiveEnchantCapacity(item)
    local settings = getSettings()
    local baseCapacity = getItemCapacity(item)
    local multiplier = settings.enchantMultiplier or 10
    return baseCapacity * multiplier
end

-- Helper function to register the remote item handler
-- Must be called from both onInit() and onLoad() to work with save games
local function registerRemoteHandler()
    print("[EnchantMachine] Registering remote item handler for Misc items...")
    I.ItemUsage.addHandlerForType(types.Miscellaneous, function(object, actor)
        -- Check if this specific misc item is our remote control
        if object.recordId == "enchant_machine_remote" then
            if types.Player.objectIsInstance(actor) then
                print("[EnchantMachine] Remote item used, opening menu...")
                actor:sendEvent('EnchantMachine_OpenMenu', {})
            end
            return false  -- Don't consume the item, block other handlers
        end
        -- Not our item, let other handlers process it
        return nil
    end)
    print("[EnchantMachine] Remote item handler registered for Misc type")
end

-- Event handlers
local function onInit()
    print("[EnchantMachine] Global script initializing...")

    -- Initialize shared storage for PLAYER script to read
    updateSharedData()

    -- Register remote control item handler
    local ok, err = pcall(registerRemoteHandler)
    if ok then
        print("[EnchantMachine] Global script initialized successfully")
        print("[EnchantMachine] Soul power: " .. soulPower)
    else
        print("[EnchantMachine] ERROR registering handler: " .. tostring(err))
    end
end

local function onSave()
    local debug = getDebug()
    if debug then debug.info("Save", "Saving soul power: " .. soulPower) end

    return {
        version = 2,  -- Increment version for itemBaseRecords support
        soulPower = soulPower,
        upgradedItems = upgradedItems,
        itemBaseRecords = itemBaseRecords,
    }
end

local function onLoad(data)
    local debug = getDebug()

    if data and data.version then
        -- Restore soul power from save file
        soulPower = data.soulPower or 0
        upgradedItems = data.upgradedItems or {}
        itemBaseRecords = data.itemBaseRecords or {}

        if debug then debug.info("Load", "Loaded soul power: " .. soulPower .. ", base record mappings: " .. tostring(#itemBaseRecords)) end
    else
        -- New game or old save without our data
        soulPower = 0
        upgradedItems = {}
        itemBaseRecords = {}

        if debug then debug.info("Load", "New game, starting with 0 soul power") end
    end

    -- Sync to shared storage so PLAYER script can read it
    updateSharedData()

    -- CRITICAL: Register the remote item handler when loading saves
    -- ItemUsage handlers don't persist across save/load, must re-register each time
    print("[EnchantMachine] Registering handler after loading save...")
    local ok, err = pcall(registerRemoteHandler)
    if not ok then
        print("[EnchantMachine] ERROR registering handler: " .. tostring(err))
    end
end

-- Event handlers for cross-context communication
local function onDepositGemEvent(eventData)
    local debug = getDebug()
    if debug then debug.info("Event", "Received DepositGem event") end

    local actor = eventData.actor
    local item = eventData.item
    local settings = eventData.settings or getSettings()  -- Use settings from event, fallback to storage

    if not actor or not item then
        if debug then debug.error("Event", "Missing actor or item in DepositGem event") end
        if actor then
            actor:sendEvent('EnchantMachine_Result', {
                success = false,
                message = "Invalid deposit request"
            })
        end
        return
    end

    local success, message = depositSoul(item, actor, settings)

    -- Send result back to player
    actor:sendEvent('EnchantMachine_Result', {
        success = success,
        message = message,
        operation = 'deposit'
    })
end

local function onRechargeItemEvent(eventData)
    local debug = getDebug()
    if debug then debug.info("Event", "Received RechargeItem event") end

    local actor = eventData.actor
    local item = eventData.item
    local settings = eventData.settings or getSettings()  -- Use settings from event, fallback to storage

    if not actor or not item then
        if debug then debug.error("Event", "Missing actor or item in RechargeItem event") end
        if actor then
            actor:sendEvent('EnchantMachine_Result', {
                success = false,
                message = "Invalid recharge request"
            })
        end
        return
    end

    local success, message = rechargeItem(item, actor, settings)

    -- Send result back to player
    actor:sendEvent('EnchantMachine_Result', {
        success = success,
        message = message,
        operation = 'recharge'
    })
end

local function onUpgradeItemEvent(eventData)
    local debug = getDebug()
    if debug then debug.info("Event", "Received UpgradeItem event") end

    local actor = eventData.actor
    local item = eventData.item
    local amount = eventData.amount or 1
    local settings = eventData.settings or getSettings()  -- Use settings from event, fallback to storage

    if not actor or not item then
        if debug then debug.error("Event", "Missing actor or item in UpgradeItem event") end
        if actor then
            actor:sendEvent('EnchantMachine_Result', {
                success = false,
                message = "Invalid upgrade request"
            })
        end
        return
    end

    -- Pass actor and settings to upgradeItemCapacity for inventory management
    local success, message = upgradeItemCapacity(item, amount, actor, settings)

    -- Send result back to player
    actor:sendEvent('EnchantMachine_Result', {
        success = success,
        message = message,
        operation = 'upgrade'
    })
end

-- Export interface for other scripts
return {
    interfaceName = 'EnchantMachine',
    interface = {
        -- Soul power management
        getSoulPower = getSoulPower,
        addSoulPower = addSoulPower,
        subtractSoulPower = subtractSoulPower,
        resetSoulPower = resetSoulPower,
        getSoulValue = getSoulValue,

        -- Soul gem operations
        depositSoul = depositSoul,

        -- Item operations
        rechargeItem = rechargeItem,
        canBeEnchanted = canBeEnchanted,
        getItemCapacity = getItemCapacity,
        getEffectiveEnchantCapacity = getEffectiveEnchantCapacity,

        -- Upgrade operations
        getUpgradedCapacity = getUpgradedCapacity,
        upgradeItemCapacity = upgradeItemCapacity,

        -- Settings access
        getSettings = getSettings,
        setSetting = setSetting,
    },
    engineHandlers = {
        onInit = onInit,
        onSave = onSave,
        onLoad = onLoad,
    },
    eventHandlers = {
        EnchantMachine_DepositGem = onDepositGemEvent,
        EnchantMachine_RechargeItem = onRechargeItemEvent,
        EnchantMachine_UpgradeItem = onUpgradeItemEvent,
    },
}
