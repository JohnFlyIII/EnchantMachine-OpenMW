-- Global script for Dwemer Enchanting Machine
-- Manages soul power bank, settings, enchanting, recharging, and upgrades

local storage = require('openmw.storage')
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
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

local CAPTURE_MARK_EFFECT_ID = "em_capture_mark"
local CAPTURE_MARK_SPELL_ID = "em_capture_mark_spell"
local SUMMON_EFFECT_ID = "em_summon_echo"
local SUMMON_DURATION = 60
local SUMMON_POLL_INTERVAL = 0.5
local SUMMON_SCRIPT = "scripts/enchantmachine/summoned.lua"

-- Soul Siphon effect/spell records are injected by load.lua via openmw.content.
local SIPHON_EFFECT_ID = "em_soul_siphon"
local SIPHON_SPELL_ID = "em_soul_siphon_spell"

-- Reusable soul gems release their soul on deposit instead of being consumed.
local REUSABLE_SOULGEMS = {
    ["misc_soulgem_azura"] = true,  -- Azura's Star
}

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
local attuned = false       -- Set once the resonator is attuned at the Heart (Attune feature)
local attuneAbility = nil   -- { id, magnitude } of the granted Heart's Resonance ability record
local summonSpells = {}     -- Maps generated summon spell ID -> captured creature metadata
local summonPollTimer = 0

-- Soul Resonance: while attuned, deposited and siphoned souls yield 50% more
-- power. Deliberately NOT applied to Remove Enchantment refunds — amplifying
-- refunds would make enchant->remove->repeat print soul power. Keep in sync
-- with RESONANCE_MULT in player_full.lua (menu previews).
local RESONANCE_MULT = 1.5

-- The interior cell holding the Heart of Lorkhan in Dagoth Ur's facility. Attune
-- only succeeds while the player stands here; the vanilla cell name is matched
-- exactly (verify in-game with `player.cell.name` if this ever drifts).
local FINAL_CHAMBER_CELL = "Akulakhan's Chamber"

local function isValidObject(object)
    if not object then return false end
    local ok, valid = pcall(function() return object:isValid() end)
    return ok and valid
end

local function resolveBaseRecordId(item)
    return itemBaseRecords[item.recordId]
        or item.recordId:match("^(.-)_cap%d+$")
        or item.recordId
end

-- Upgrade tracking (declared early so getItemCapacity / upgradeItemCapacity can both use them)
local function getUpgradedCapacity(itemRecordId)
    return upgradedItems[itemRecordId] or 0
end

local function setUpgradedCapacity(itemRecordId, additionalCapacity)
    if additionalCapacity and additionalCapacity > 0 then
        upgradedItems[itemRecordId] = additionalCapacity
    else
        upgradedItems[itemRecordId] = nil
    end
end

local function getItemUpgradeAmount(item, record, typeMod)
    local baseRecordId = resolveBaseRecordId(item)
    local baseRecord = typeMod.records[baseRecordId] or record
    local baseCapacity = baseRecord.enchantCapacity or record.enchantCapacity or 0
    local storedUpgrade = getUpgradedCapacity(item.recordId)
    if storedUpgrade > 0 then
        return storedUpgrade, baseRecordId, baseCapacity
    end
    return math.max(0, (record.enchantCapacity or baseCapacity) - baseCapacity), baseRecordId, baseCapacity
end

-- Shared storage for PLAYER script to read (just a display cache)
local sharedData = storage.globalSection('EnchantMachine_SharedData')

-- Settings storage (shared between PLAYER and GLOBAL)
local settingsData = storage.globalSection('EnchantMachine_Settings')

-- Update shared storage when soul power changes (for UI display)
local function updateSharedData()
    sharedData:set('soulPower', soulPower)
    sharedData:set('attuned', attuned)
end

-- Default settings (fallback values)
local defaultSettings = {
    enableMachine = true,
    enchantMultiplier = 10,
    upgradeRatio = 100,
    enableUpgradeFeature = false,
    attuneEnchantBonus = 50,
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
        attuneEnchantBonus = settingsData:get('attuneEnchantBonus'),
    }
end

-- Soul Resonance multiplier (see RESONANCE_MULT above).
local function resonantValue(value)
    if attuned then
        return math.floor(value * RESONANCE_MULT)
    end
    return value
end

-- Heart's Resonance: a constant Fortify Enchant ability granted on attunement.
-- Abilities are always-on and persist in the save with their runtime-created
-- spell record. The magnitude follows the attuneEnchantBonus setting; if it
-- changes, syncAttunementAbility swaps the old ability for a fresh record.
local function createAttuneAbilityRecord(bonus)
    local draft = core.magic.spells.createRecordDraft({
        name = "Heart's Resonance",
        type = core.magic.SPELL_TYPE.Ability,
        cost = 0,
        isAutocalc = false,
        starterSpellFlag = false,
        effects = {
            {
                id = core.magic.EFFECT_TYPE.FortifySkill,
                affectedSkill = 'enchant',
                range = core.magic.RANGE.Self,
                area = 0,
                duration = 0,
                magnitudeMin = bonus,
                magnitudeMax = bonus,
            },
        },
    })
    return world.createRecord(draft).id
end

-- Idempotent: safe to call on attune, on settings change, and when a player
-- joins (covers saves that attuned before this perk existed). No-op until
-- attuned. bonus == 0 removes the ability entirely.
local function syncAttunementAbility(player)
    if not attuned then return end
    player = isValidObject(player) and player or world.players[1]
    if not isValidObject(player) or not types.Player.objectIsInstance(player) then return end

    local bonus = math.max(0, math.floor(tonumber(settingsData:get('attuneEnchantBonus')) or 50))

    local ok, err = pcall(function()
        local spells = types.Actor.spells(player)
        if attuneAbility and attuneAbility.magnitude ~= bonus then
            if spells[attuneAbility.id] then
                spells:remove(attuneAbility.id)
            end
            attuneAbility = nil
        end
        if bonus == 0 then return end
        if not attuneAbility then
            attuneAbility = { id = createAttuneAbilityRecord(bonus), magnitude = bonus }
        end
        if not spells[attuneAbility.id] then
            spells:add(attuneAbility.id)
            dbg.info("Attune", "Granted Heart's Resonance (+" .. bonus .. " Enchant)")
        end
    end)
    if not ok then
        dbg.error("Attune", "Ability sync failed", tostring(err))
    end
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
    soulValue = resonantValue(soulValue)

    -- Reusable gems (Azura's Star) release their soul; itemData.soul = nil is the
    -- documented way to empty a gem. Ordinary gems are consumed: remove a single
    -- gem from the stack — without the count, remove() takes the whole stack
    -- while we'd only credit one gem's soul value.
    local kept = REUSABLE_SOULGEMS[item.recordId]
    if kept then
        itemData.soul = nil
    else
        item:remove(1)
    end
    local newTotal = addSoulPower(soulValue)

    dbg.info("Deposit", "Deposited " .. soulValue .. " soul power" .. (kept and " (gem kept)" or ""))
    dbg.incrementMetric("totalDeposits")
    dbg.trackMetric("totalSoulPowerAdded", soulValue)
    dbg.endTimer("depositSoul")

    if kept then
        return true, "The star releases its soul: " .. soulValue .. " power. Total: " .. newTotal
    end
    return true, "Deposited " .. soulValue .. " soul power. Total: " .. newTotal
end

-- Deposit every filled soul gem in the actor's inventory at once. Stacks are
-- handled per-entry: a stack of identical filled gems shares one itemData, so we
-- credit soulValue * count and remove the whole stack. Reusable gems are emptied
-- in place, never consumed.
local function depositAllSouls(actor, settings)
    dbg.startTimer("depositAllSouls")

    settings = settings or getSettings()
    if not settings.enableMachine then
        dbg.endTimer("depositAllSouls")
        return false, "Machine is disabled"
    end

    local total, gemCount = 0, 0
    for _, item in ipairs(types.Actor.inventory(actor):getAll(types.Miscellaneous)) do
        local itemData = types.Miscellaneous.itemData(item)
        if itemData and itemData.soul then
            local soulValue = resonantValue(getSoulValue(itemData.soul))
            if soulValue > 0 then
                if REUSABLE_SOULGEMS[item.recordId] then
                    itemData.soul = nil
                    total = total + soulValue
                    gemCount = gemCount + 1
                else
                    local count = item.count or 1
                    item:remove(count)
                    total = total + soulValue * count
                    gemCount = gemCount + count
                end
            end
        end
    end

    if gemCount == 0 then
        dbg.endTimer("depositAllSouls")
        return false, "No filled soul gems to deposit"
    end

    local newTotal = addSoulPower(total)

    dbg.info("Deposit", "Deposited " .. gemCount .. " souls for " .. total .. " power")
    dbg.incrementMetric("totalDeposits")
    dbg.trackMetric("totalSoulPowerAdded", total)
    dbg.endTimer("depositAllSouls")

    return true, string.format("Deposited %d souls for %d power. Total: %d",
        gemCount, total, math.floor(newTotal))
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
    if not itemData then
        dbg.error("Recharge", "Item has no itemData - cannot set charge")
        dbg.endTimer("rechargeItem")
        return false, "Item cannot store charge data"
    end

    local success, remaining = subtractSoulPower(soulPowerNeeded)
    if not success then
        return false, "Not enough soul power (need " .. soulPowerNeeded .. ", have " .. remaining .. ")"
    end

    itemData.enchantmentCharge = maxCharge

    dbg.info("Recharge", "Recharged item using " .. soulPowerNeeded .. " soul power")
    dbg.incrementMetric("totalRecharges")
    dbg.trackMetric("totalSoulPowerSpent", soulPowerNeeded)
    dbg.endTimer("rechargeItem")

    return true, "Recharged to " .. math.floor(maxCharge) .. "/" .. math.floor(maxCharge) .. ". Soul power remaining: " .. remaining
end

-- Upgrade an item's enchantment capacity by registering a new derived record
-- and swapping the inventory item to it. customName (optional) renames the
-- upgraded item.
local function upgradeItemCapacity(item, capacityIncrease, actor, settings, customName)
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
    if soulPower < soulCost then
        dbg.endTimer("upgradeItemCapacity")
        return false, "Not enough soul power (need " .. soulCost .. ", have " .. soulPower .. ")"
    end

    if type(customName) ~= 'string' or customName:match('^%s*$') then
        customName = nil
    end

    local _existingUpgrade, baseRecordId, baseCapacity = getItemUpgradeAmount(item, record, typeMod)
    local oldCapacity = record.enchantCapacity or baseCapacity
    local newCapacity = oldCapacity + capacityIncrease

    local ok, result = pcall(function()
        -- world.createRecord auto-generates the id (the draft.id field is ignored),
        -- so we always register a fresh record and trust the returned id.
        local draftSpec = { template = record, enchantCapacity = newCapacity }
        if customName then draftSpec.name = customName end
        local draft = typeMod.createRecordDraft(draftSpec)
        local newRecordId = world.createRecord(draft).id
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

        return { newRecordId = newRecordId }
    end)
    if not ok then
        dbg.error("Upgrade", "Record swap failed", tostring(result))
        dbg.endTimer("upgradeItemCapacity")
        return false, "The machine could not upgrade that item"
    end

    local _success, newTotal = subtractSoulPower(soulCost)
    itemBaseRecords[result.newRecordId] = baseRecordId
    setUpgradedCapacity(result.newRecordId, newCapacity - baseCapacity)

    local shownName = customName or record.name
    dbg.info("Upgrade", "Upgraded " .. shownName .. " " .. baseCapacity .. " -> " .. newCapacity .. " (base " .. baseRecordId .. ")")
    dbg.incrementMetric("totalUpgrades")
    dbg.endTimer("upgradeItemCapacity")

    return true, "Upgraded " .. shownName .. " capacity from " .. math.floor(oldCapacity) .. " to " .. math.floor(newCapacity) .. ". Soul power remaining: " .. math.floor(newTotal)
end

-- Remove an item's enchantment by registering a derived record with the enchant
-- cleared and swapping the inventory item to it. Refunds soul power based on the
-- removed enchantment's charge (consistent with recharge: 1 power per charge point).
-- The resulting blank item can then be enchanted via the game's own enchant system
-- (or upgraded via this machine, which only accepts unenchanted items).
local function removeEnchantment(item, actor, settings)
    dbg.startTimer("removeEnchantment")

    settings = settings or getSettings()
    if not settings.enableMachine then
        dbg.endTimer("removeEnchantment")
        return false, "The machine is disabled"
    end

    local record, oldData, typeMod = getEnchantable(item)
    if not record then
        dbg.endTimer("removeEnchantment")
        return false, "Only weapons, armor, and clothing can be modified"
    end
    if not record.enchant or record.enchant == "" then
        dbg.endTimer("removeEnchantment")
        return false, "Item is not enchanted"
    end

    -- Refund value from the enchantment's charge capacity, falling back to its cost.
    local ench = core.magic.enchantments.records[record.enchant]
    local refund = 0
    if ench then
        local charge = ench.charge or 0
        refund = math.floor(charge > 0 and charge or (ench.cost or 0))
    end

    -- Preserve the base-record mapping so later capacity upgrades still resolve.
    local existingUpgrade, baseRecordId = getItemUpgradeAmount(item, record, typeMod)

    local ok, result = pcall(function()
        -- world.createRecord auto-generates the id (draft.id is ignored), so register
        -- fresh and trust the returned id — same pattern as upgradeItemCapacity.
        local draft = typeMod.createRecordDraft({ template = record, enchant = "" })
        local newRecordId = world.createRecord(draft).id
        local newItem = world.createObject(newRecordId, 1)

        -- Carry over condition. enchantmentCharge is meaningless now (no enchant), so skip it.
        local newData = typeMod.itemData(newItem)
        if oldData and newData and oldData.condition then
            newData.condition = oldData.condition
        end

        if actor and types.Actor.objectIsInstance(actor) then
            newItem:moveInto(types.Actor.inventory(actor))
        end
        -- Consume one item from the stack; we only created one replacement.
        item:remove(1)

        return { newRecordId = newRecordId }
    end)
    if not ok then
        dbg.error("RemoveEnchant", "Record swap failed", tostring(result))
        dbg.endTimer("removeEnchantment")
        return false, "The machine could not remove that enchantment"
    end

    itemBaseRecords[result.newRecordId] = baseRecordId
    setUpgradedCapacity(result.newRecordId, existingUpgrade)

    if refund > 0 then addSoulPower(refund) end

    dbg.info("RemoveEnchant", "Removed enchant from " .. (record.name or "item") .. ", refunded " .. refund)
    dbg.incrementMetric("totalEnchantRemovals")
    dbg.endTimer("removeEnchantment")

    return true, string.format(
        "Removed the enchantment from %s. Refunded %d soul power. The item can now be enchanted normally.",
        record.name or "item", refund)
end

-- Enchant an unenchanted item by deriving an Enchantment record from one of the
-- player's known spells and swapping the inventory item to a record that points at
-- it. This replaces the old native-UI handoff (I.UI.addMode('Enchanting')), which
-- failed on this engine because EnchantingDialog needs an engine-side Ptr that the
-- Lua API can't supply. Same record-swap pattern as upgrade/remove.
--
-- The cast type comes from the menu as eventData.enchantType (a key of
-- PLAYER_ENCHANT_TYPES); older callers that omit it get the legacy default of
-- strike for weapons, use for armor & clothing. The charge pool is the item's
-- capacity scaled by enchantMultiplier (the mod's signature boost), and we fill
-- it to full up front for `charge` soul power (1:1, consistent with recharge).
-- Constant Effect ignores charge in-engine, but is priced the same here.
local PLAYER_ENCHANT_TYPES = {
    CastOnStrike = core.magic.ENCHANTMENT_TYPE.CastOnStrike,
    CastOnUse = core.magic.ENCHANTMENT_TYPE.CastOnUse,
    ConstantEffect = core.magic.ENCHANTMENT_TYPE.ConstantEffect,
}

local function addEnchantment(item, actor, settings, eventData)
    dbg.startTimer("addEnchantment")

    settings = settings or getSettings()
    if not settings.enableMachine then
        dbg.endTimer("addEnchantment")
        return false, "The machine is disabled"
    end

    local spellId = eventData and eventData.spellId
    if not spellId then
        dbg.endTimer("addEnchantment")
        return false, "No spell selected"
    end

    local record, oldData, typeMod = getEnchantable(item)
    if not record then
        dbg.endTimer("addEnchantment")
        return false, "Only weapons, armor, and clothing can be enchanted"
    end
    if record.enchant and record.enchant ~= "" then
        dbg.endTimer("addEnchantment")
        return false, "Item is already enchanted"
    end
    if not record.enchantCapacity or record.enchantCapacity <= 0 then
        dbg.endTimer("addEnchantment")
        return false, "Item cannot hold enchantments"
    end

    local spell = core.magic.spells.records[spellId]
    if not spell then
        dbg.endTimer("addEnchantment")
        return false, "Unknown spell"
    end

    -- Copy the spell's effects into plain tables. MagicEffectWithParams shares the
    -- same field set between spells and enchantments, so this maps straight across.
    local effects = {}
    for _, e in ipairs(spell.effects) do
        effects[#effects + 1] = {
            id = e.id,
            affectedSkill = e.affectedSkill,
            affectedAttribute = e.affectedAttribute,
            range = e.range,
            area = e.area,
            magnitudeMin = e.magnitudeMin,
            magnitudeMax = e.magnitudeMax,
            duration = e.duration,
        }
    end
    if #effects == 0 then
        dbg.endTimer("addEnchantment")
        return false, "That spell has no usable effects"
    end

    local enchType
    local requestedType = eventData and eventData.enchantType
    if requestedType then
        enchType = PLAYER_ENCHANT_TYPES[requestedType]
        if not enchType then
            dbg.endTimer("addEnchantment")
            return false, "Unknown enchantment type: " .. tostring(requestedType)
        end
        if enchType == core.magic.ENCHANTMENT_TYPE.CastOnStrike and typeMod ~= types.Weapon then
            dbg.endTimer("addEnchantment")
            return false, "Only weapons can cast on strike"
        end
    else
        enchType = (typeMod == types.Weapon)
            and core.magic.ENCHANTMENT_TYPE.CastOnStrike
            or core.magic.ENCHANTMENT_TYPE.CastOnUse
    end

    -- Constant effects only work self-targeted (matching the vanilla enchanter,
    -- which restricts constant enchantments to Self-range effects). Soul Siphon
    -- is banned here: a constant self-siphon re-applies forever and the poll
    -- would bank power in an infinite loop.
    if enchType == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        for _, e in ipairs(effects) do
            if e.id == SIPHON_EFFECT_ID then
                dbg.endTimer("addEnchantment")
                return false, "Soul Siphon cannot be made constant — the feedback would tear the machine apart"
            end
            e.range = core.magic.RANGE.Self
        end
    end

    local multiplier = settings.enchantMultiplier or 10
    local charge = math.floor((record.enchantCapacity or 0) * multiplier)
    if charge <= 0 then
        dbg.endTimer("addEnchantment")
        return false, "Item cannot hold enchantments"
    end
    local castCost = math.max(1, math.floor(spell.cost or 1))

    -- Charge the bank for filling the enchantment to full (1 power per charge point).
    if soulPower < charge then
        dbg.endTimer("addEnchantment")
        return false, "Not enough soul power (need " .. charge .. ", have " .. soulPower .. ")"
    end

    -- Optional player-chosen display name for the created item.
    local customName = eventData and eventData.customName
    if type(customName) ~= 'string' or customName:match('^%s*$') then
        customName = nil
    end

    -- Build the enchantment record, then a derived item record pointing at it.
    -- Guard creation: a bad effect set should report, not hard-error or charge the bank.
    local existingUpgrade, baseRecordId = getItemUpgradeAmount(item, record, typeMod)
    local ok, result = pcall(function()
        local enchDraft = core.magic.enchantments.createRecordDraft({
            type = enchType,
            isAutocalc = false,
            cost = castCost,
            charge = charge,
            effects = effects,
        })
        local enchId = world.createRecord(enchDraft).id

        local draftSpec = { template = record, enchant = enchId }
        if customName then draftSpec.name = customName end
        local draft = typeMod.createRecordDraft(draftSpec)
        local newRecordId = world.createRecord(draft).id
        local newItem = world.createObject(newRecordId, 1)

        -- Carry over condition; the new item arrives fully charged.
        local newData = typeMod.itemData(newItem)
        if newData then
            if oldData and oldData.condition then newData.condition = oldData.condition end
            newData.enchantmentCharge = charge
        end

        if actor and types.Actor.objectIsInstance(actor) then
            newItem:moveInto(types.Actor.inventory(actor))
        end
        -- Consume one item from the stack; we only created one replacement.
        item:remove(1)

        return {
            enchId = enchId,
            newRecordId = newRecordId,
        }
    end)
    if not ok then
        dbg.error("AddEnchant", "Record swap failed", tostring(result))
        dbg.endTimer("addEnchantment")
        return false, "The machine could not imbue that enchantment"
    end

    local _success, remaining = subtractSoulPower(charge)
    itemBaseRecords[result.newRecordId] = baseRecordId
    setUpgradedCapacity(result.newRecordId, existingUpgrade)

    local shownName = customName or record.name or "item"
    dbg.info("AddEnchant", "Enchanted " .. shownName .. " with " .. (spell.name or spellId) .. " (charge " .. charge .. ")")
    dbg.incrementMetric("totalEnchantsAdded")
    dbg.endTimer("addEnchantment")

    return true, string.format(
        "Imbued %s with %s. Soul power remaining: %d",
        shownName, spell.name or spellId, math.floor(remaining))
end

-- Calculate effective enchantment capacity for new enchantments
local function getEffectiveEnchantCapacity(item)
    local settings = getSettings()
    local baseCapacity = getItemCapacity(item)
    local multiplier = settings.enchantMultiplier or 10
    return baseCapacity * multiplier
end

local function getSpellForCreature(creatureId)
    for spellId, info in pairs(summonSpells) do
        if info.creatureId == creatureId then
            return spellId, info
        end
    end
end

local function createSummonSpell(creatureId, creatureName)
    local spellName = "Summon " .. creatureName
    local draft = core.magic.spells.createRecordDraft({
        name = spellName,
        type = core.magic.SPELL_TYPE.Spell,
        cost = 25,
        isAutocalc = false,
        starterSpellFlag = false,
        effects = {
            {
                id = SUMMON_EFFECT_ID,
                range = core.magic.RANGE.Self,
                area = 0,
                duration = SUMMON_DURATION,
            },
        },
    })
    return world.createRecord(draft).id, spellName
end

local function markCreature(target, actor, settings)
    settings = settings or getSettings()
    if not settings.enableMachine then
        return false, "The machine is disabled"
    end
    if not isValidObject(actor) or not types.Player.objectIsInstance(actor) then
        return false, "Only the player can bind a summon"
    end
    if not isValidObject(target) or not types.Creature.objectIsInstance(target) then
        return false, "Only creatures can be marked for summoning"
    end
    if types.Actor.isDead(target) then
        return false, "That creature is already dead"
    end
    if types.Actor.activeSpells(target):isSpellActive(CAPTURE_MARK_SPELL_ID) then
        return false, "That creature is already marked"
    end

    local record = types.Creature.record(target)
    local creatureName = (record and record.name and record.name ~= "" and record.name) or target.recordId
    local ok, err = pcall(function()
        types.Actor.activeSpells(target):add({
            id = CAPTURE_MARK_SPELL_ID,
            effects = { 0 },
            name = "Resonant Mark",
        })
        target:sendEvent('EnchantMachine_SetSoulMark', {
            marker = actor,
            markSpellId = CAPTURE_MARK_SPELL_ID,
        })
    end)
    if not ok then
        dbg.error("SummonMark", "Mark failed", tostring(err))
        return false, "The machine could not mark that creature"
    end

    dbg.info("SummonMark", "Marked " .. creatureName .. " for " .. (actor.recordId or "player"))
    return true, "Marked " .. creatureName .. ". Defeat it to bind its summon."
end

local function learnSummonFromCreature(creature, actor)
    if not isValidObject(creature) or not types.Creature.objectIsInstance(creature) then
        return false, "Marked target is no longer available"
    end
    actor = isValidObject(actor) and actor or world.players[1]
    if not isValidObject(actor) or not types.Player.objectIsInstance(actor) then
        return false, "No player is available to receive the summon"
    end

    local record = types.Creature.record(creature)
    local creatureId = creature.recordId
    if not record or not types.Creature.records[creatureId] then
        return false, "The machine could not identify that creature"
    end

    local creatureName = (record.name and record.name ~= "" and record.name) or creatureId
    local spellId, info = getSpellForCreature(creatureId)
    if not spellId then
        local ok, createdSpellId, spellName = pcall(function()
            local newSpellId, newSpellName = createSummonSpell(creatureId, creatureName)
            return newSpellId, newSpellName
        end)
        if not ok then
            dbg.error("SummonLearn", "Spell creation failed", tostring(createdSpellId))
            return false, "The machine could not create that summon spell"
        end
        spellId = createdSpellId
        info = {
            creatureId = creatureId,
            creatureName = creatureName,
            spellName = spellName,
            duration = SUMMON_DURATION,
        }
        summonSpells[spellId] = info
    end

    local ok, err = pcall(function()
        local spells = types.Actor.spells(actor)
        if not spells[spellId] then
            spells:add(spellId)
        end
    end)
    if not ok then
        dbg.error("SummonLearn", "Adding spell failed", tostring(err))
        return false, "The machine created the spell, but could not teach it"
    end

    dbg.info("SummonLearn", "Learned " .. info.spellName .. " from " .. creatureId)
    return true, "Bound " .. creatureName .. ". You learned " .. info.spellName .. "."
end

local function spawnSummon(actor, info)
    if not isValidObject(actor) then
        return false, "No summoner is available"
    end
    if not info or not info.creatureId or not types.Creature.records[info.creatureId] then
        return false, "That summon no longer has a valid creature record"
    end

    local ok, result = pcall(function()
        local summon = world.createObject(info.creatureId, 1)
        local spawnPos = actor.position + util.vector3(128, 0, 0)
        summon:teleport(actor.cell, spawnPos)
        summon:addScript(SUMMON_SCRIPT, {
            owner = actor,
            duration = info.duration or SUMMON_DURATION,
            creatureName = info.creatureName,
        })
        return summon
    end)
    if not ok then
        dbg.error("SummonCast", "Summon spawn failed", tostring(result))
        return false, "The summon failed to manifest"
    end

    return true, "Summoned " .. (info.creatureName or "creature") .. " for " .. SUMMON_DURATION .. " seconds."
end

local function checkSummonCasts()
    for _, player in ipairs(world.players) do
        if isValidObject(player) then
            local activeSpells = types.Actor.activeSpells(player)
            for _, activeSpell in pairs(activeSpells) do
                local info = summonSpells[activeSpell.id]
                if info then
                    local success, message = spawnSummon(player, info)
                    pcall(function() activeSpells:remove(activeSpell.activeSpellId) end)
                    player:sendEvent('EnchantMachine_Message', {
                        success = success,
                        message = message,
                    })
                    break
                end
            end
        end
    end
end

-- Soul Siphon: the custom effect has no engine behaviour, so we poll active
-- actors for it. Each strike with a siphon enchantment puts a fresh active spell
-- on the victim (3s duration, comfortably longer than the 0.5s poll); we bank
-- the rolled magnitude as soul power and strip the active spell so it can't be
-- banked twice. Removals are collected first — mutating the active-spell list
-- while iterating it is undefined.
local function checkSoulSiphons(player)
    local totalSiphoned = 0
    for _, actor in ipairs(world.activeActors) do
        if isValidObject(actor) then
            local activeSpells = types.Actor.activeSpells(actor)
            local toRemove = {}
            for _, activeSpell in pairs(activeSpells) do
                local siphoned = 0
                for _, effect in pairs(activeSpell.effects) do
                    if effect.id == SIPHON_EFFECT_ID then
                        siphoned = siphoned
                            + math.max(1, math.floor(effect.magnitudeThisFrame or effect.minMagnitude or 1))
                    end
                end
                if siphoned > 0 then
                    table.insert(toRemove, activeSpell.activeSpellId)
                    totalSiphoned = totalSiphoned + siphoned
                end
            end
            for _, activeSpellId in ipairs(toRemove) do
                pcall(function() activeSpells:remove(activeSpellId) end)
            end
        end
    end

    if totalSiphoned > 0 then
        totalSiphoned = resonantValue(totalSiphoned)
        addSoulPower(totalSiphoned)
        dbg.info("Siphon", "Siphoned " .. totalSiphoned .. " soul power")
        dbg.trackMetric("totalSoulPowerAdded", totalSiphoned)
        if isValidObject(player) then
            player:sendEvent('EnchantMachine_Message', {
                success = true,
                message = "Siphoned " .. totalSiphoned .. " soul power.",
            })
        end
    end
end

local function onUpdate(dt)
    summonPollTimer = summonPollTimer + dt
    if summonPollTimer < SUMMON_POLL_INTERVAL then return end
    summonPollTimer = 0
    checkSummonCasts()
    checkSoulSiphons(world.players[1])
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
        version = 5,
        soulPower = soulPower,
        upgradedItems = upgradedItems,
        itemBaseRecords = itemBaseRecords,
        attuned = attuned,
        attuneAbility = attuneAbility,
        summonSpells = summonSpells,
    }
end

local function onLoad(data)
    if data and data.version then
        soulPower = data.soulPower or 0
        upgradedItems = data.upgradedItems or {}
        itemBaseRecords = data.itemBaseRecords or {}
        -- attuned added in v3; older saves default to false.
        attuned = data.attuned or false
        -- summonSpells added in v4; attuneAbility in v5 (granted on next
        -- onPlayerAdded for older attuned saves).
        attuneAbility = data.attuneAbility
        summonSpells = data.summonSpells or {}
        dbg.info("Load", "Loaded soul power " .. soulPower)
    else
        soulPower = 0
        upgradedItems = {}
        itemBaseRecords = {}
        attuned = false
        attuneAbility = nil
        summonSpells = {}
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

-- Deposit All acts on the whole inventory, not a single item, so it bypasses
-- handleOperationEvent (which requires `item`).
local function onDepositAllEvent(eventData)
    local actor = eventData and eventData.actor
    if not actor then return end

    local success, message = depositAllSouls(actor, eventData.settings)
    actor:sendEvent('EnchantMachine_Result', {
        success = success,
        message = message,
        operation = 'deposit',
    })
end

local function onRechargeItemEvent(eventData)
    handleOperationEvent('recharge', rechargeItem, eventData)
end

local function onUpgradeItemEvent(eventData)
    handleOperationEvent('upgrade', function(item, actor, settings, ev)
        return upgradeItemCapacity(item, ev.amount or 1, actor, settings, ev.customName)
    end, eventData)
end

local function onRemoveEnchantEvent(eventData)
    handleOperationEvent('remove-enchant', removeEnchantment, eventData)
end

local function onAddEnchantEvent(eventData)
    handleOperationEvent('add-enchant', addEnchantment, eventData)
end

local function onMarkCreatureEvent(eventData)
    local actor = eventData and eventData.actor
    local target = eventData and eventData.target
    if not actor then return end

    local success, message = markCreature(target, actor, eventData.settings)
    actor:sendEvent('EnchantMachine_Result', {
        success = success,
        message = message,
        operation = 'mark-creature',
    })
end

local function onMarkedCreatureDiedEvent(eventData)
    local creature = eventData and eventData.creature
    local marker = eventData and eventData.marker
    local actor = isValidObject(marker) and marker or world.players[1]
    local success, message = learnSummonFromCreature(creature, actor)
    if isValidObject(actor) then
        actor:sendEvent('EnchantMachine_Message', {
            success = success,
            message = message,
        })
    end
end

local function onRemoveSummonEvent(eventData)
    local summon = eventData and eventData.summon
    if isValidObject(summon) then
        pcall(function() summon:remove() end)
    end
end

-- Attune the resonator. Unlike the other operations this acts on a location, not
-- an inventory item, so it bypasses handleOperationEvent (which requires `item`).
-- Succeeds only inside the Heart chamber; sets the persistent `attuned` flag.
local function onAttuneEvent(eventData)
    local actor = eventData and eventData.actor
    if not actor then return end

    local cell = actor.cell
    local ok = cell ~= nil and cell.name == FINAL_CHAMBER_CELL
    if ok then
        attuned = true
        updateSharedData()
        syncAttunementAbility(actor)
        dbg.info("Attune", "Resonator attuned at " .. FINAL_CHAMBER_CELL)
    else
        dbg.info("Attune", "Attune failed in cell " .. ((cell and cell.name) or "?"))
    end

    actor:sendEvent('EnchantMachine_Result', {
        success = ok,
        operation = 'attune',
        message = ok and ("The resonator sings in answer to the Heart. Attunement complete. "
                .. "Souls now resonate with greater power, and Kagrenac's craft steadies your hands.")
            or "The device failed to attune.",
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
        depositAllSouls = depositAllSouls,

        -- Custom item creation
        createRemoteItem = createRemoteItem,
        createDwemerScroll = createDwemerScroll,

        -- Item operations
        rechargeItem = rechargeItem,
        removeEnchantment = removeEnchantment,
        addEnchantment = addEnchantment,
        canBeEnchanted = canBeEnchanted,
        getItemCapacity = getItemCapacity,
        getEffectiveEnchantCapacity = getEffectiveEnchantCapacity,

        -- Attunement
        getAttuned = function() return attuned end,

        -- Custom summons
        markCreature = markCreature,
        learnSummonFromCreature = learnSummonFromCreature,
        getSummonSpells = function() return summonSpells end,

        -- Upgrade operations
        getUpgradedCapacity = getUpgradedCapacity,
        upgradeItemCapacity = upgradeItemCapacity,

        -- Settings access
        getSettings = getSettings,
    },
    engineHandlers = {
        onInit = onInit,
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad,
        -- Re-grant Heart's Resonance when the player joins: covers saves that
        -- attuned before the perk existed and any failed earlier grant.
        onPlayerAdded = function(player) syncAttunementAbility(player) end,
    },
    eventHandlers = {
        EnchantMachine_DepositGem = onDepositGemEvent,
        EnchantMachine_DepositAll = onDepositAllEvent,
        EnchantMachine_RechargeItem = onRechargeItemEvent,
        EnchantMachine_UpgradeItem = onUpgradeItemEvent,
        EnchantMachine_RemoveEnchant = onRemoveEnchantEvent,
        EnchantMachine_AddEnchant = onAddEnchantEvent,
        EnchantMachine_MarkCreature = onMarkCreatureEvent,
        EnchantMachine_MarkedCreatureDied = onMarkedCreatureDiedEvent,
        EnchantMachine_RemoveSummon = onRemoveSummonEvent,
        EnchantMachine_Attune = onAttuneEvent,

        -- PLAYER pushes its current settings here so machine.getSettings() (the
        -- documented public API) returns what the user actually configured,
        -- rather than the default fallbacks.
        EnchantMachine_SyncSettings = function(data)
            if not data then return end
            for _, key in ipairs({'enableMachine', 'enchantMultiplier', 'upgradeRatio',
                                  'enableUpgradeFeature', 'attuneEnchantBonus'}) do
                if data[key] ~= nil then
                    settingsData:set(key, data[key])
                end
            end
            -- Live-reswap Heart's Resonance if the bonus setting changed (no-op
            -- unless attuned and the magnitude actually differs).
            syncAttunementAbility()
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
