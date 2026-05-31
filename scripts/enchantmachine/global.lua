-- Global script for Dwemer Enchanting Machine
-- Manages soul power bank, settings, enchanting, recharging, and upgrades

local storage = require('openmw.storage')
local core = require('openmw.core')
local types = require('openmw.types')
local world = require('openmw.world')
local I = require('openmw.interfaces')

-- Forwarding wrapper for the optional debug interface. Methods become no-ops
-- when debug.lua hasn't loaded yet (or doesn't expose the requested method),
-- so callers can write `dbg.info("Cat", "msg")` without a `if debug then` guard.
local dbg = setmetatable({}, {
    __index = function(_, method)
        return function(...)
            local d = I.EnchantMachineDebug
            if d and d[method] then return d[method](...) end
        end
    end,
})

-- For a Weapon/Armor/Clothing instance, returns (record, itemData, typeModule).
-- Returns nil for everything else. The typeModule (e.g. types.Weapon) is handy
-- when the caller needs to call typeModule.records[id] or createRecordDraft.
local function getEnchantable(item)
    if types.Weapon.objectIsInstance(item) then
        return types.Weapon.record(item), types.Weapon.itemData(item), types.Weapon
    elseif types.Armor.objectIsInstance(item) then
        return types.Armor.record(item), types.Armor.itemData(item), types.Armor
    elseif types.Clothing.objectIsInstance(item) then
        return types.Clothing.record(item), types.Clothing.itemData(item), types.Clothing
    end
end

-- The name used to identify the enchanting machine remote control.
-- We match by name (not recordId) because world.createRecord auto-generates IDs.
local REMOTE_ITEM_NAME = "Dwemer Enchanting Machine Remote"

-- Create a fresh remote item instance via a derived record.
-- Used by both the boss-loot path and the debug GiveRemote event.
local function createRemoteItem()
    local template = types.Miscellaneous.records["misc_dwrv_artifact00"]
        or types.Miscellaneous.records["misc_de_glass_green_01"]
    if not template then
        return nil, "No suitable template item found"
    end

    local draft = types.Miscellaneous.createRecordDraft({
        template = template,
        name = REMOTE_ITEM_NAME,
        weight = 0.5,
        value = 500,
    })
    local record = world.createRecord(draft)
    return world.createObject(record.id, 1)
end

-- Id of the looted Dwemer scroll (the encoded book) that starts EM_DwemerDiscovery.
-- The record lives in EnchantMachine.omwaddon, so — unlike the remote, which is a
-- renamed misc item built via createRecordDraft — we instantiate it directly.
local DWEMER_SCROLL_ENCODED_ID = "em_dwemer_scroll_encoded"

-- Create a fresh encoded-scroll instance. Returns (object) or (nil, err) if the
-- omwaddon record is missing (e.g. plugin not loaded / id changed in CS).
local function createDwemerScroll()
    if not types.Book.records[DWEMER_SCROLL_ENCODED_ID] then
        return nil, "Scroll record '" .. DWEMER_SCROLL_ENCODED_ID .. "' missing — is EnchantMachine.omwaddon loaded?"
    end
    return world.createObject(DWEMER_SCROLL_ENCODED_ID, 1)
end

-- In-memory data (saved/loaded with save file)
local soulPower = 0
local upgradedItems = {}
local itemBaseRecords = {}  -- Maps upgraded item ID -> original base record ID

-- Upgrade tracking (declared early so getItemCapacity / upgradeItemCapacity can both use them)
local function getUpgradedCapacity(itemRecordId)
    return upgradedItems[itemRecordId] or 0
end

local function setUpgradedCapacity(itemRecordId, additionalCapacity)
    upgradedItems[itemRecordId] = additionalCapacity
end

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

-- Get current soul power in the bank
local function getSoulPower()
    return soulPower
end

-- Add soul power to the bank
local function addSoulPower(amount)
    soulPower = soulPower + amount
    updateSharedData()
    dbg.info("SoulPower", "Added " .. amount .. ", total now: " .. soulPower)
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
    dbg.info("SoulPower", "Soul power reset to 0")
    return 0
end

-- Get soul value from a creature record ID.
-- Returns 0 if the record is missing or has no positive soulValue.
local function getSoulValue(creatureId)
    if not creatureId or creatureId == "" then return 0 end
    local record = types.Creature.records[creatureId]
    local soulValue = record and record.soulValue or 0
    if soulValue <= 0 then
        dbg.warn("SoulValue", "No soul value for '" .. creatureId .. "'")
        return 0
    end
    return soulValue
end

-- Check if an item can be enchanted.
local function canBeEnchanted(item)
    if not item then return false end
    local record = getEnchantable(item)
    if not record then
        return false, "Only weapons, armor, and clothing can be enchanted"
    end
    if record.enchant and record.enchant ~= "" then
        return false, "Item is already enchanted"
    end
    if not record.enchantCapacity or record.enchantCapacity <= 0 then
        return false, "Item cannot hold enchantments"
    end
    return true, record
end

-- Get item's enchantment capacity.
-- Upgrades are baked into the derived record's enchantCapacity at creation time,
-- so reading record.enchantCapacity already reflects any upgrade.
local function getItemCapacity(item)
    local record = getEnchantable(item)
    return (record and record.enchantCapacity) or 0
end

-- Deposit soul from a soul gem (consumes the item)
local function depositSoul(item, actor, settings)
    dbg.startTimer("depositSoul")

    settings = settings or getSettings()
    if not settings.enableMachine then
        dbg.warn("Deposit", "Machine is disabled")
        dbg.endTimer("depositSoul")
        return false, "Machine is disabled"
    end

    if not types.Miscellaneous.objectIsInstance(item) then
        dbg.warn("Deposit", "Invalid item type")
        dbg.endTimer("depositSoul")
        return false, "Not a soul gem"
    end

    local itemData = types.Miscellaneous.itemData(item)
    if not itemData or not itemData.soul then
        dbg.warn("Deposit", "No soul in gem")
        dbg.endTimer("depositSoul")
        return false, "No soul in this item"
    end

    local soulValue = getSoulValue(itemData.soul)
    if soulValue <= 0 then
        dbg.error("Deposit", "Invalid soul value", soulValue)
        dbg.endTimer("depositSoul")
        return false, "Invalid soul"
    end

    -- Consume a single gem from the stack. Without the count, remove() takes the
    -- whole stack while we'd only credit one gem's soul value.
    item:remove(1)
    local newTotal = addSoulPower(soulValue)

    dbg.info("Deposit", "Deposited " .. soulValue .. " soul power")
    dbg.incrementMetric("totalDeposits")
    dbg.trackMetric("totalSoulPowerAdded", soulValue)
    dbg.endTimer("depositSoul")

    return true, "Deposited " .. soulValue .. " soul power. Total: " .. newTotal
end

-- Recharge an enchanted item using soul power
local function rechargeItem(item, actor, settings)
    dbg.startTimer("rechargeItem")

    settings = settings or getSettings()
    if not settings.enableMachine then
        dbg.warn("Recharge", "Machine is disabled")
        dbg.endTimer("rechargeItem")
        return false, "Machine is disabled"
    end

    local record, itemData = getEnchantable(item)
    if not record then
        return false, "This item cannot be recharged"
    end
    if not record.enchant or record.enchant == "" then
        return false, "Item is not enchanted"
    end

    local enchantment = core.magic.enchantments.records[record.enchant]
    if not enchantment then
        return false, "Invalid enchantment"
    end

    local maxCharge = enchantment.charge or 0
    local currentCharge = (itemData and itemData.enchantmentCharge) or maxCharge

    if currentCharge >= maxCharge then
        return false, "Item is already fully charged (" .. math.floor(currentCharge) .. "/" .. math.floor(maxCharge) .. ")"
    end

    local soulPowerNeeded = math.ceil(maxCharge - currentCharge) -- 1:1 ratio
    local success, remaining = subtractSoulPower(soulPowerNeeded)
    if not success then
        return false, "Not enough soul power (need " .. soulPowerNeeded .. ", have " .. remaining .. ")"
    end

    if not itemData then
        dbg.error("Recharge", "Item has no itemData - cannot set charge")
        dbg.endTimer("rechargeItem")
        return false, "Item cannot store charge data"
    end

    itemData.enchantmentCharge = maxCharge

    dbg.info("Recharge", "Recharged item using " .. soulPowerNeeded .. " soul power")
    dbg.incrementMetric("totalRecharges")
    dbg.trackMetric("totalSoulPowerSpent", soulPowerNeeded)
    dbg.endTimer("rechargeItem")

    return true, "Recharged to " .. math.floor(maxCharge) .. "/" .. math.floor(maxCharge) .. ". Soul power remaining: " .. remaining
end

-- Upgrade an item's enchantment capacity by registering a new derived record
-- and swapping the inventory item to it.
local function upgradeItemCapacity(item, capacityIncrease, actor, settings)
    dbg.startTimer("upgradeItemCapacity")

    settings = settings or getSettings()
    if not settings.enableUpgradeFeature then
        dbg.endTimer("upgradeItemCapacity")
        return false, "Upgrade feature is not unlocked"
    end

    if capacityIncrease <= 0 then
        dbg.endTimer("upgradeItemCapacity")
        return false, "Increase must be positive"
    end

    local record, _oldData, typeMod = getEnchantable(item)
    if not record then
        dbg.endTimer("upgradeItemCapacity")
        return false, "Only weapons, armor, and clothing can be upgraded"
    end
    if not record.enchantCapacity or record.enchantCapacity <= 0 then
        dbg.endTimer("upgradeItemCapacity")
        return false, "Item cannot hold enchantments"
    end
    if record.enchant and record.enchant ~= "" then
        dbg.endTimer("upgradeItemCapacity")
        return false, "Cannot upgrade enchanted items. Only unenchanted items can be upgraded."
    end

    local ratio = settings.upgradeRatio or 100
    local soulCost = capacityIncrease * ratio
    local success, newTotal = subtractSoulPower(soulCost)
    if not success then
        dbg.endTimer("upgradeItemCapacity")
        return false, "Not enough soul power (need " .. soulCost .. ", have " .. newTotal .. ")"
    end

    -- Walk back to the original base record. The pattern-match fallback handles
    -- items from older save formats that pre-date itemBaseRecords.
    local baseRecordId = itemBaseRecords[item.recordId]
        or item.recordId:match("^(.-)_cap%d+$")
        or item.recordId

    local baseRecord = typeMod.records[baseRecordId]
    local baseCapacity = baseRecord.enchantCapacity
    local currentUpgrade = getUpgradedCapacity(baseRecordId)
    local newCapacity = baseCapacity + currentUpgrade + capacityIncrease

    -- world.createRecord auto-generates the id (the draft.id field is ignored),
    -- so we always register a fresh record and trust the returned id.
    local draft = typeMod.createRecordDraft({ template = record, enchantCapacity = newCapacity })
    local newRecordId = world.createRecord(draft).id
    itemBaseRecords[newRecordId] = baseRecordId

    local newItem = world.createObject(newRecordId, 1)

    -- Carry over condition and remaining enchant charge.
    local oldData = typeMod.itemData(item)
    local newData = typeMod.itemData(newItem)
    if oldData and newData then
        if oldData.condition then newData.condition = oldData.condition end
        if oldData.enchantmentCharge then newData.enchantmentCharge = oldData.enchantmentCharge end
    end

    if actor and types.Actor.objectIsInstance(actor) then
        newItem:moveInto(types.Actor.inventory(actor))
    end
    -- Consume one item from the stack; we only created one upgraded replacement.
    item:remove(1)

    setUpgradedCapacity(baseRecordId, newCapacity - baseCapacity)

    dbg.info("Upgrade", "Upgraded " .. record.name .. " " .. baseCapacity .. " -> " .. newCapacity .. " (base " .. baseRecordId .. ")")
    dbg.incrementMetric("totalUpgrades")
    dbg.endTimer("upgradeItemCapacity")

    return true, "Upgraded " .. record.name .. " capacity from " .. math.floor(record.enchantCapacity) .. " to " .. math.floor(newCapacity) .. ". Soul power remaining: " .. math.floor(newTotal)
end

-- Calculate effective enchantment capacity for new enchantments
local function getEffectiveEnchantCapacity(item)
    local settings = getSettings()
    local baseCapacity = getItemCapacity(item)
    local multiplier = settings.enchantMultiplier or 10
    return baseCapacity * multiplier
end

-- ItemUsage handlers don't persist across save/load — must be re-registered from
-- both onInit() and onLoad() so the remote keeps working after loading a save.
-- Handler signature per OpenMW API: handler(object, actor, options).
local function registerRemoteHandler()
    I.ItemUsage.addHandlerForType(types.Miscellaneous, function(object, actor, _options)
        local record = types.Miscellaneous.records[object.recordId]
        local itemName = record and record.name or ""
        if itemName == REMOTE_ITEM_NAME then
            if types.Player.objectIsInstance(actor) then
                actor:sendEvent('EnchantMachine_OpenMenu', {})
            end
            return false  -- Skip subsequent handlers and the standard use action
        end
        return nil
    end)
end

local function onInit()
    updateSharedData()
    registerRemoteHandler()
    dbg.info("Init", "Initialized with soul power " .. soulPower)
end

local function onSave()
    dbg.info("Save", "Saving soul power: " .. soulPower)
    return {
        version = 2,
        soulPower = soulPower,
        upgradedItems = upgradedItems,
        itemBaseRecords = itemBaseRecords,
    }
end

local function onLoad(data)
    if data and data.version then
        soulPower = data.soulPower or 0
        upgradedItems = data.upgradedItems or {}
        itemBaseRecords = data.itemBaseRecords or {}
        dbg.info("Load", "Loaded soul power " .. soulPower)
    else
        soulPower = 0
        upgradedItems = {}
        itemBaseRecords = {}
        dbg.info("Load", "New game, starting at 0 soul power")
    end

    updateSharedData()

    -- ItemUsage handlers don't persist across save/load — re-register each time.
    registerRemoteHandler()
end

-- Dispatch an operation event: validates actor+item, runs op, replies with result.
-- `op` receives (item, actor, settings) and returns (success, message).
local function handleOperationEvent(name, op, eventData)
    dbg.info("Event", "Received " .. name)

    local actor = eventData.actor
    local item = eventData.item
    if not actor or not item then
        dbg.error("Event", "Missing actor or item in " .. name)
        if actor then
            actor:sendEvent('EnchantMachine_Result', {
                success = false,
                message = "Invalid " .. name .. " request",
            })
        end
        return
    end

    local settings = eventData.settings or getSettings()
    local success, message = op(item, actor, settings, eventData)

    actor:sendEvent('EnchantMachine_Result', {
        success = success,
        message = message,
        operation = name,
    })
end

local function onDepositGemEvent(eventData)
    handleOperationEvent('deposit', depositSoul, eventData)
end

local function onRechargeItemEvent(eventData)
    handleOperationEvent('recharge', rechargeItem, eventData)
end

local function onUpgradeItemEvent(eventData)
    handleOperationEvent('upgrade', function(item, actor, settings, ev)
        return upgradeItemCapacity(item, ev.amount or 1, actor, settings)
    end, eventData)
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

        -- Custom item creation
        createRemoteItem = createRemoteItem,
        createDwemerScroll = createDwemerScroll,

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

        -- PLAYER pushes its current settings here so machine.getSettings() (the
        -- documented public API) returns what the user actually configured,
        -- rather than the default fallbacks.
        EnchantMachine_SyncSettings = function(data)
            if not data then return end
            for _, key in ipairs({'enableMachine', 'enchantMultiplier', 'upgradeRatio', 'enableUpgradeFeature'}) do
                if data[key] ~= nil then
                    settingsData:set(key, data[key])
                end
            end
        end,

        -- Debug: spawn a remote into the player's inventory (callable from console).
        EnchantMachine_GiveRemote = function(data)
            local player = world.players[1]
            if not player then return end
            local remote, err = createRemoteItem()
            if remote then
                remote:moveInto(types.Actor.inventory(player))
            else
                print("[EnchantMachine] GiveRemote failed: " .. tostring(err))
            end
            -- Also hand over the Dwemer scroll so the dev flow exercises the full
            -- loot (and the EM_DwemerDiscovery quest start).
            local scroll, serr = createDwemerScroll()
            if scroll then
                scroll:moveInto(types.Actor.inventory(player))
            else
                print("[EnchantMachine] GiveScroll failed: " .. tostring(serr))
            end
        end,
    },
}
