-- Player script for Dwemer Enchanting Machine
-- Handles UI, settings, and player interactions

local self = require('openmw.self')
local ui = require('openmw.ui')
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
local async = require('openmw.async')
local storage = require('openmw.storage')
local nearby = require('openmw.nearby')
local I = require('openmw.interfaces')

print("[EnchantMachine] Player script loading...")

-- ---------- Settings registration ----------

I.Settings.registerPage({
    key = 'EnchantMachine',
    l10n = 'EnchantMachine',
    name = 'Dwemer Enchanting Machine',
    description = 'Configure the enchanting machine settings and view soul power',
})

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
            argument = { disabled = true },
        },
    },
})

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
            argument = { integer = true, min = 1, max = 100 },
        },
        {
            key = 'upgradeRatio',
            renderer = 'number',
            name = 'Upgrade Ratio',
            description = 'Soul power cost per capacity point (default: 100:1)',
            default = 100,
            argument = { integer = true, min = 1, max = 1000 },
        },
        {
            key = 'enableUpgradeFeature',
            renderer = 'checkbox',
            name = 'Enable Upgrades',
            description = 'Allow upgrading item enchantment capacity',
            default = false,
        },
        {
            key = 'attuneEnchantBonus',
            renderer = 'number',
            name = 'Attunement Enchant Bonus',
            description = 'Constant Enchant skill bonus granted while attuned to the Heart (0 disables; takes effect immediately)',
            default = 50,
            argument = { integer = true, min = 0, max = 100 },
        },
        {
            key = 'howToAccess',
            renderer = 'textLine',
            name = 'How to Access Machine',
            description = 'Use the Dwemer Enchanting Machine Remote from your inventory',
            default = 'See description',
            argument = { disabled = true },
        },
    },
})

-- ---------- State ----------

local sharedData = storage.globalSection('EnchantMachine_SharedData')
local statusSettings = storage.playerSection('SettingsEnchantMachineStatus')
local configSettings = storage.playerSection('SettingsEnchantMachineConfig')

local currentMenu = nil
local updateTimer = 0
local UPDATE_INTERVAL = 1.0

-- Boss-cell detection (persisted across save/load via onSave/onLoad below)
local lastCellName = nil
local bossSpawnRequested = false
local BOSS_CELL_NAME = "Arkngthand, Deep Ore Passage"

-- Dwemer-scroll quest trigger (EM_DwemerDiscovery). Looting from a corpse is an
-- inventory transfer, not a world activation, and OpenMW has no inventory-add
-- engine handler — so we detect the scroll by a throttled inventory poll rather
-- than onActivated. No persistence needed: the journal stage itself is the state.
-- NOTE: content-file string ids are lower-cased by the engine, so the quest key
-- is lowercase even though OpenMW-CS shows "EM_DwemerDiscovery".
local SCROLL_QUEST_ID = "em_dwemerdiscovery"
local SCROLL_LOOTED_STAGE = 10
local SCROLL_ITEM_ENCODED = "em_dwemer_scroll_encoded"
local SCROLL_ITEM_DECODED = "em_dwemer_scroll_decoded"
local scrollJournalDone = false

local SUMMON_CAPTURE_RANGE = 2048
local SUMMON_CAPTURE_LIMIT = 12

-- ---------- Forward declarations ----------
-- All menu functions reference each other (Back buttons, retry-after-result, etc.),
-- so we declare every binding up front. Lua resolves closure upvalues at parse time;
-- forgetting any of these would silently turn a call into a nil global lookup.

local createMenu
local createMainMenu
local showDepositMenu
local showRechargeMenu
local showReinforceMenu
local showReinforceAmountMenu
local showUpgradeMenu
local showUpgradeAmountMenu
local showRemoveEnchantMenu
local showRemoveEffectMenu
local showAddEnchantMenu
local showEnchantTypeMenu
local showSpellSelectMenu
local showNameItemMenu
local showCaptureSummonMenu
local attuneResonator

-- ---------- Settings sync (PLAYER -> GLOBAL) ----------

local function getSettings()
    return {
        enableMachine = configSettings:get('enableMachine'),
        enchantMultiplier = configSettings:get('enchantMultiplier'),
        upgradeRatio = configSettings:get('upgradeRatio'),
        enableUpgradeFeature = configSettings:get('enableUpgradeFeature'),
        attuneEnchantBonus = configSettings:get('attuneEnchantBonus'),
    }
end

-- Push current settings to GLOBAL so machine.getSettings() (the public API)
-- returns user-configured values, not the GLOBAL defaults.
local function syncSettingsToGlobal()
    core.sendGlobalEvent('EnchantMachine_SyncSettings', getSettings())
end

-- Fire whenever any setting in our group changes. The callback signature is
-- (sectionName, key) — key is nil when the whole section was reset.
configSettings:subscribe(async:callback(function() syncSettingsToGlobal() end))

-- ---------- Helpers ----------

local function setMenuMode(enabled)
    if enabled then
        I.UI.setMode('Interface', { windows = {} })
    else
        I.UI.setMode()
    end
end

local function getSoulPower()
    return sharedData:get('soulPower') or 0
end

local function isAttuned()
    return sharedData:get('attuned') or false
end

-- Soul Resonance: while attuned, deposited and siphoned souls yield 50% more
-- power. Must match RESONANCE_MULT in global.lua — this copy only drives the
-- menu previews; GLOBAL owns the actual banking math.
local RESONANCE_MULT = 1.5

local function resonantValue(value)
    if isAttuned() then
        return math.floor(value * RESONANCE_MULT)
    end
    return value
end

local function closeMenu()
    if currentMenu then
        pcall(function() currentMenu:destroy() end)
        currentMenu = nil
    end
    setMenuMode(false)
end

local function createButton(text, onClick, enabled)
    if enabled == nil then enabled = true end

    return {
        template = I.MWUI.templates.box,
        props = { alpha = enabled and 1.0 or 0.5 },
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
        events = enabled and { mouseClick = async:callback(onClick) } or {},
    }
end

local function spacer(height)
    return {
        type = ui.TYPE.Flex,
        -- autoSize must be off or Flex ignores `size` and collapses to 0 height.
        props = { autoSize = false, size = util.vector2(0, height) },
    }
end

local function textLine(text, opts)
    opts = opts or {}
    return {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = {
            text = text,
            textSize = opts.size or 14,
            textColor = opts.color,
        },
    }
end

local function boxedTitle(text, size)
    return {
        template = I.MWUI.templates.boxSolid,
        content = ui.content{
            {
                type = ui.TYPE.Text,
                template = I.MWUI.templates.textHeader,
                props = { text = text, textSize = size or 20 },
            },
        },
    }
end

local function bareHeader(text, size)
    return {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textHeader,
        props = { text = text, textSize = size or 30 },
    }
end

-- Single-line text input. `props` is a caller-owned table: keep props.text in
-- sync inside onChanged, so if the widget is ever recreated by an update() it
-- doesn't reset to the stale initial text.
local function textInput(props, onChanged)
    return {
        template = I.MWUI.templates.textEditLine,
        props = props,
        events = { textChanged = async:callback(onChanged) },
    }
end

-- A horizontal row of pre-built nodes, centered on the cross axis.
local function buttonRow(nodes)
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        content = ui.content(nodes),
    }
end

-- Build and display a vertical, centered menu.
-- opts = {
--   header    = { type = 'boxed'|'bare', text = string, size = number? }  -- optional
--   info      = string?                  -- normal text under the header
--   warning   = string?                  -- yellow callout text
--   items     = table                    -- pre-built UI nodes (buttons, spacers, etc.)
--   onBack    = function?                -- if set, appends a Back button
--   backLabel = string?                  -- defaults to "Back"
-- }
createMenu = function(opts)
    setMenuMode(true)

    local content = {}

    if opts.header then
        if opts.header.type == 'bare' then
            table.insert(content, bareHeader(opts.header.text, opts.header.size))
        else
            table.insert(content, boxedTitle(opts.header.text, opts.header.size))
        end
    end

    if opts.info then
        table.insert(content, textLine(opts.info))
    end

    if opts.warning then
        table.insert(content, textLine(opts.warning, { size = 12, color = util.color.rgb(1, 1, 0) }))
    end

    -- MWUI has no scroll container, so a long centered list can push the Back
    -- button off the bottom of the screen (the "can't back out" bug). For long
    -- lists we render Back at the TOP and top-anchor the window (below) so the
    -- header and Back stay on-screen; short menus stay centered with Back at the
    -- bottom as before.
    local menuItems = opts.items or {}
    local longList = #menuItems > 8

    if opts.onBack and longList then
        table.insert(content, createButton(opts.backLabel or "Back", opts.onBack))
    end

    table.insert(content, spacer(10))

    for _, item in ipairs(menuItems) do
        table.insert(content, item)
    end

    if opts.onBack and not longList then
        table.insert(content, spacer(10))
        table.insert(content, createButton(opts.backLabel or "Back", opts.onBack))
    end

    local menu = ui.create{
        layer = 'Windows',
        template = I.MWUI.templates.boxTransparent,
        props = {
            relativePosition = longList and util.vector2(0.5, 0.04) or util.vector2(0.5, 0.5),
            anchor = longList and util.vector2(0.5, 0.0) or util.vector2(0.5, 0.5),
        },
        content = ui.content{
            {
                type = ui.TYPE.Flex,
                -- Flex's orientation prop is `horizontal` (false = vertical, the
                -- default). There is no `vertical` prop — 0.51's widget validation
                -- warns on unrecognised fields.
                props = {
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Center,
                },
                content = ui.content(content),
            },
        },
    }

    currentMenu = menu
    return menu
end

-- ---------- Inventory scans ----------

local function getFilledSoulGems()
    local gems = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        if types.Miscellaneous.objectIsInstance(item) then
            local itemData = types.Miscellaneous.itemData(item)
            if itemData and itemData.soul then
                -- Resolve the trapped soul's creature record for its display name
                -- and soul value. Records are static game data and readable from
                -- the player context (the value is not a property of a nearby
                -- instance). Guarded so an odd/missing soul id can't break the menu.
                local soulName, soulValue = itemData.soul, 0
                local ok, creature = pcall(function() return types.Creature.records[itemData.soul] end)
                if ok and creature then
                    soulName = creature.name or itemData.soul
                    soulValue = creature.soulValue or 0
                end
                table.insert(gems, {
                    item = item,
                    record = types.Miscellaneous.record(item),
                    soul = itemData.soul,
                    soulName = soulName,
                    soulValue = soulValue,
                    count = item.count or 1,
                })
            end
        end
    end
    return gems
end

local function getEnchantableRecord(item)
    if types.Weapon.objectIsInstance(item) then
        return types.Weapon.record(item), types.Weapon.itemData(item)
    elseif types.Armor.objectIsInstance(item) then
        return types.Armor.record(item), types.Armor.itemData(item)
    elseif types.Clothing.objectIsInstance(item) then
        return types.Clothing.record(item), types.Clothing.itemData(item)
    end
end

local function getRechargeableItems()
    local items = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        local record, itemData = getEnchantableRecord(item)
        if record and record.enchant and record.enchant ~= "" then
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
    return items
end

local function getUpgradeableItems()
    local items = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        local record = getEnchantableRecord(item)
        if record
            and record.enchantCapacity and record.enchantCapacity > 0
            and (not record.enchant or record.enchant == "")
        then
            table.insert(items, { item = item, record = record })
        end
    end
    return items
end

-- Enchanted weapons/armor/clothing — candidates for Remove Enchantment.
local function getEnchantedItems()
    local items = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        local record = getEnchantableRecord(item)
        if record and record.enchant and record.enchant ~= "" then
            table.insert(items, { item = item, record = record })
        end
    end
    return items
end

-- Weapons/armor/clothing that can hold an enchantment — candidates for Add
-- Enchantment. Unenchanted items always qualify; once attuned, enchanted items
-- are also offered (the "weave" perk appends effects to the existing
-- enchantment). Kept separate from getUpgradeableItems so the features can
-- diverge (Add doesn't depend on the upgrade feature being unlocked).
local function getEnchantableItems()
    local includeEnchanted = isAttuned()
    local items = {}
    for _, item in ipairs(types.Actor.inventory(self):getAll()) do
        local record = getEnchantableRecord(item)
        if record and record.enchantCapacity and record.enchantCapacity > 0 then
            local enchanted = record.enchant and record.enchant ~= ""
            if not enchanted then
                table.insert(items, { item = item, record = record })
            elseif includeEnchanted then
                table.insert(items, { item = item, record = record, enchanted = true })
            end
        end
    end
    return items
end

-- Human-readable one-liner for a MagicEffectWithParams ("Fire Damage 10-30 pts, 5s").
local function describeEffect(e)
    local name = e.id
    local ok, effRec = pcall(function() return core.magic.effects.records[e.id] end)
    if ok and effRec and effRec.name then name = effRec.name end
    local qualifier = e.affectedSkill or e.affectedAttribute
    if qualifier then name = name .. ": " .. qualifier end

    local parts = { name }
    local maxMag = e.magnitudeMax or 0
    if maxMag > 0 then
        local minMag = e.magnitudeMin or maxMag
        if minMag == maxMag then
            table.insert(parts, minMag .. " pts")
        else
            table.insert(parts, minMag .. "-" .. maxMag .. " pts")
        end
    end
    if (e.duration or 0) > 0 then
        table.insert(parts, e.duration .. "s")
    end
    return table.concat(parts, ", ")
end

-- The player's known, castable spells (excludes abilities, diseases, powers, etc.)
-- — these are the templates offered as enchantments.
local function getKnownSpells()
    local spells = {}
    for _, spell in pairs(types.Actor.spells(self)) do
        if spell.type == core.magic.SPELL_TYPE.Spell then
            table.insert(spells, spell)
        end
    end
    return spells
end

local function distanceToPlayer(actor)
    local ok, distance = pcall(function()
        return (actor.position - self.object.position):length()
    end)
    if ok and distance then return distance end

    local delta = actor.position - self.object.position
    return math.sqrt((delta.x or 0) * (delta.x or 0)
        + (delta.y or 0) * (delta.y or 0)
        + (delta.z or 0) * (delta.z or 0))
end

local function getNearbySummonCandidates()
    local creatures = {}
    for _, actor in ipairs(nearby.actors) do
        if actor ~= self.object
            and types.Creature.objectIsInstance(actor)
            and not types.Actor.isDead(actor)
        then
            local distance = distanceToPlayer(actor)
            if distance <= SUMMON_CAPTURE_RANGE then
                table.insert(creatures, {
                    actor = actor,
                    record = types.Creature.record(actor),
                    distance = distance,
                })
            end
        end
    end

    table.sort(creatures, function(a, b) return a.distance < b.distance end)
    while #creatures > SUMMON_CAPTURE_LIMIT do
        table.remove(creatures)
    end
    return creatures
end

-- ---------- Menu definitions ----------

showDepositMenu = function()
    closeMenu()

    local gems = getFilledSoulGems()
    if #gems == 0 then
        ui.showMessage("You have no filled soul gems to deposit.")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local items = {}

    -- Deposit All: preview the haul in the label. Mirrors GLOBAL's stack math
    -- (resonant soulValue * stack count); Azura's Star counts once and is kept.
    local totalPower, totalGems = 0, 0
    for _, gem in ipairs(gems) do
        totalPower = totalPower + resonantValue(gem.soulValue or 0) * gem.count
        totalGems = totalGems + gem.count
    end
    if totalGems > 1 then
        table.insert(items, createButton(
            string.format("Deposit All (%d souls, %d power)", totalGems, totalPower),
            function()
                core.sendGlobalEvent('EnchantMachine_DepositAll', {
                    actor = self.object,
                    settings = getSettings(),
                })
                ui.showMessage("Depositing all soul gems...")
                closeMenu()
            end
        ))
        table.insert(items, spacer(6))
    end

    for _, gem in ipairs(gems) do
        local gemName = (gem.record and gem.record.name) or "Soul Gem"
        local soulName = gem.soulName or gem.soul or "Unknown"
        local label = gemName
        if gem.count > 1 then
            label = label .. " x" .. gem.count
        end
        label = label .. " (" .. soulName
        if (gem.soulValue or 0) > 0 then
            label = label .. " - " .. resonantValue(gem.soulValue) .. " power"
        end
        label = label .. ")"
        table.insert(items, createButton(
            label,
            function()
                core.sendGlobalEvent('EnchantMachine_DepositGem', {
                    actor = self.object,
                    item = gem.item,
                    settings = getSettings(),
                })
                ui.showMessage("Depositing soul gem...")
                closeMenu()
            end
        ))
    end

    createMenu{
        header = { type = 'boxed', text = "Deposit Soul Gems" },
        info = isAttuned()
            and "Select a soul gem to deposit. The Heart's resonance amplifies souls by 50%."
            or "Select a soul gem to deposit. Gems are consumed permanently.",
        warning = "Azura's Star only releases its soul — the star itself is never consumed.",
        items = items,
        onBack = function() createMainMenu() end,
    }
end

showRechargeMenu = function()
    closeMenu()

    local rechargeable = getRechargeableItems()
    if #rechargeable == 0 then
        ui.showMessage("You have no enchanted items that need recharging.")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local soulPower = getSoulPower()
    local items = {}
    for _, entry in ipairs(rechargeable) do
        local itemName = entry.record.name or "Item"
        local current = math.floor(entry.currentCharge)
        local max = math.floor(entry.maxCharge)
        local needed = math.ceil(entry.maxCharge - entry.currentCharge)
        local canAfford = soulPower >= needed

        table.insert(items, createButton(
            string.format("%s (%d/%d) - %d power needed", itemName, current, max, needed),
            function()
                core.sendGlobalEvent('EnchantMachine_RechargeItem', {
                    actor = self.object,
                    item = entry.item,
                    settings = getSettings(),
                })
                ui.showMessage("Recharging item...")
                closeMenu()
            end,
            canAfford
        ))
    end

    createMenu{
        header = { type = 'boxed', text = "Recharge Enchanted Items" },
        info = "Soul Power: " .. math.floor(soulPower) .. " | Cost: 1 power per charge point",
        items = items,
        onBack = function() createMainMenu() end,
    }
end

-- Reinforce Charge: enlarge an enchanted item's max charge pool (1 power per
-- point, consistent with recharge). Constant enchantments have no pool.
showReinforceMenu = function()
    closeMenu()

    local candidates = {}
    for _, entry in ipairs(getEnchantedItems()) do
        local ok, ench = pcall(function()
            return core.magic.enchantments.records[entry.record.enchant]
        end)
        if ok and ench and ench.type ~= core.magic.ENCHANTMENT_TYPE.ConstantEffect then
            entry.maxCharge = math.floor(ench.charge or 0)
            table.insert(candidates, entry)
        end
    end

    if #candidates == 0 then
        ui.showMessage("You have no charged enchanted items to reinforce.")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local items = {}
    for _, entry in ipairs(candidates) do
        table.insert(items, createButton(
            string.format("%s (pool: %d)", entry.record.name or "Item", entry.maxCharge),
            function() showReinforceAmountMenu(entry) end
        ))
    end

    createMenu{
        header = { type = 'boxed', text = "Reinforce Charge" },
        info = string.format("Soul Power: %d | Cost: 1 power per charge point",
            math.floor(getSoulPower())),
        warning = "Enlarges the maximum charge pool. Current charge is kept — top up via Recharge.",
        items = items,
        onBack = function() createMainMenu() end,
    }
end

showReinforceAmountMenu = function(entry)
    closeMenu()

    local soulPower = getSoulPower()
    local itemName = entry.record.name or "Item"
    local maxCharge = entry.maxCharge or 0
    local maxAffordable = math.floor(soulPower)

    local function sendReinforce(amount)
        core.sendGlobalEvent('EnchantMachine_ReinforceCharge', {
            actor = self.object,
            item = entry.item,
            amount = amount,
            settings = getSettings(),
        })
        ui.showMessage("Reinforcing charge pool...")
        closeMenu()
    end

    local items = {}
    for _, amount in ipairs({100, 500, 1000}) do
        table.insert(items, createButton(
            string.format("+%d charge (%d power) → %d pool", amount, amount, maxCharge + amount),
            function() sendReinforce(amount) end,
            soulPower >= amount
        ))
    end
    if maxAffordable > 0 then
        table.insert(items, createButton(
            string.format("+%d charge (Max affordable)", maxAffordable),
            function() sendReinforce(maxAffordable) end
        ))
    end

    local customAmount = nil
    local editProps = { text = '', size = util.vector2(240, 24) }
    local statusProps = {
        text = string.format("Type an amount and Apply (max affordable: %d)", maxAffordable),
        textSize = 14,
    }

    local function onAmountChanged(text)
        editProps.text = text
        customAmount = tonumber(text:match('^%s*(%d+)%s*$') or '')
        if customAmount and customAmount >= 1 then
            if customAmount <= soulPower then
                statusProps.text = string.format("+%d charge costs %d power → %d pool",
                    customAmount, customAmount, maxCharge + customAmount)
                statusProps.textColor = util.color.rgb(0.5, 1, 0.5)
            else
                statusProps.text = string.format("Costs %d power — you only have %d",
                    customAmount, math.floor(soulPower))
                statusProps.textColor = util.color.rgb(1, 0.4, 0.4)
            end
        else
            customAmount = nil
            statusProps.text = text == '' and
                string.format("Type an amount and Apply (max affordable: %d)", maxAffordable)
                or "Enter a whole number"
            statusProps.textColor = nil
        end
        if currentMenu then currentMenu:update() end
    end

    table.insert(items, spacer(10))
    table.insert(items, textLine("Custom amount:"))
    table.insert(items, textInput(editProps, onAmountChanged))
    table.insert(items, {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = statusProps,
    })
    table.insert(items, createButton("Apply Custom Amount", function()
        if not customAmount then
            ui.showMessage("Enter a whole number of charge points first.")
            return
        end
        if customAmount > soulPower then
            ui.showMessage(string.format("Not enough soul power (need %d, have %d).",
                customAmount, math.floor(soulPower)))
            return
        end
        sendReinforce(customAmount)
    end))

    createMenu{
        header = { type = 'boxed', text = "Reinforce: " .. itemName },
        info = string.format("Current pool: %d | Soul Power: %d | Rate: 1 power per point",
            maxCharge, math.floor(soulPower)),
        items = items,
        onBack = showReinforceMenu,
    }
end

showUpgradeMenu = function()
    closeMenu()

    local settings = getSettings()
    if not settings.enableUpgradeFeature then
        ui.showMessage("Upgrade feature is locked. Enable it in settings!")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local upgradeable = getUpgradeableItems()
    if #upgradeable == 0 then
        ui.showMessage("You have no items that can be upgraded.")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local soulPower = getSoulPower()
    local ratio = settings.upgradeRatio or 100

    local items = {}
    for _, entry in ipairs(upgradeable) do
        local itemName = entry.record.name or "Item"
        local capacity = math.floor(entry.record.enchantCapacity or 0)
        table.insert(items, createButton(
            string.format("%s (Capacity: %d)", itemName, capacity),
            function() showUpgradeAmountMenu(entry, ratio, soulPower) end
        ))
    end

    createMenu{
        header = { type = 'boxed', text = "Upgrade Item Capacity" },
        info = string.format("Soul Power: %d | Cost: %d power per capacity point",
            math.floor(soulPower), ratio),
        warning = "Note: Only unenchanted items can be upgraded. Upgrade before enchanting!",
        items = items,
        onBack = function() createMainMenu() end,
    }
end

showUpgradeAmountMenu = function(entry, ratio, soulPower)
    closeMenu()

    local itemName = entry.record.name or "Item"
    local currentCapacity = math.floor(entry.record.enchantCapacity or 0)
    local maxAffordable = math.floor(soulPower / ratio)

    -- Optional rename, applied by whichever upgrade button is clicked.
    -- Whitespace-only means "keep the current name" (GLOBAL ignores it).
    local renameTyped = ''
    local renameProps = { text = '', size = util.vector2(240, 24) }

    local function sendUpgrade(amount)
        core.sendGlobalEvent('EnchantMachine_UpgradeItem', {
            actor = self.object,
            item = entry.item,
            amount = amount,
            customName = renameTyped,
            settings = getSettings(),
        })
        ui.showMessage("Upgrading item...")
        closeMenu()
    end

    local items = {}
    table.insert(items, textLine("Rename (optional):"))
    table.insert(items, textInput(renameProps, function(text)
        renameProps.text = text
        renameTyped = text
    end))
    table.insert(items, spacer(10))
    for _, amount in ipairs({1, 10, 100}) do
        local cost = amount * ratio
        local canAfford = soulPower >= cost
        table.insert(items, createButton(
            string.format("+%d capacity (%d power) → %d total", amount, cost, currentCapacity + amount),
            function() sendUpgrade(amount) end,
            canAfford
        ))
    end
    if maxAffordable > 0 then
        table.insert(items, createButton(
            string.format("+%d capacity (Max affordable, %d power)", maxAffordable, maxAffordable * ratio),
            function() sendUpgrade(maxAffordable) end
        ))
    end

    -- Custom amount: a text box validated live against the exchange rate and the
    -- bank balance. customAmount is nil until the box holds a whole number.
    local customAmount = nil
    local editProps = { text = '', size = util.vector2(240, 24) }
    local statusProps = {
        text = string.format("Type an amount and Apply (max affordable: %d)", maxAffordable),
        textSize = 14,
    }

    local function onAmountChanged(text)
        editProps.text = text
        customAmount = tonumber(text:match('^%s*(%d+)%s*$') or '')
        if customAmount and customAmount >= 1 then
            local cost = customAmount * ratio
            if cost <= soulPower then
                statusProps.text = string.format("+%d capacity costs %d power → %d total",
                    customAmount, cost, currentCapacity + customAmount)
                statusProps.textColor = util.color.rgb(0.5, 1, 0.5)
            else
                statusProps.text = string.format("Costs %d power — you only have %d",
                    cost, math.floor(soulPower))
                statusProps.textColor = util.color.rgb(1, 0.4, 0.4)
            end
        else
            customAmount = nil
            statusProps.text = text == '' and
                string.format("Type an amount and Apply (max affordable: %d)", maxAffordable)
                or "Enter a whole number"
            statusProps.textColor = nil
        end
        -- The status node's layout table is mutated in place; update() applies it
        -- without recreating the (focused) text edit widget.
        if currentMenu then currentMenu:update() end
    end

    table.insert(items, spacer(10))
    table.insert(items, textLine("Custom amount:"))
    table.insert(items, textInput(editProps, onAmountChanged))
    table.insert(items, {
        type = ui.TYPE.Text,
        template = I.MWUI.templates.textNormal,
        props = statusProps,
    })
    table.insert(items, createButton("Apply Custom Amount", function()
        if not customAmount then
            ui.showMessage("Enter a whole number of capacity points first.")
            return
        end
        local cost = customAmount * ratio
        if cost > soulPower then
            ui.showMessage(string.format("Not enough soul power (need %d, have %d).",
                cost, math.floor(soulPower)))
            return
        end
        sendUpgrade(customAmount)
    end))

    createMenu{
        header = { type = 'boxed', text = "Upgrade: " .. itemName },
        info = string.format("Current Capacity: %d | Soul Power: %d | Rate: %d power per point",
            currentCapacity, math.floor(soulPower), ratio),
        items = items,
        onBack = showUpgradeMenu,
    }
end

showRemoveEnchantMenu = function()
    closeMenu()

    local enchanted = getEnchantedItems()
    if #enchanted == 0 then
        ui.showMessage("You have no enchanted items.")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local items = {}
    for _, entry in ipairs(enchanted) do
        local itemName = entry.record.name or "Item"
        table.insert(items, createButton(
            itemName,
            function()
                -- Attuned and multi-effect: offer per-effect unweaving.
                local effectCount = 0
                if isAttuned() then
                    local ok, ench = pcall(function()
                        return core.magic.enchantments.records[entry.record.enchant]
                    end)
                    if ok and ench then
                        for _ in ipairs(ench.effects) do effectCount = effectCount + 1 end
                    end
                end
                if effectCount > 1 then
                    showRemoveEffectMenu(entry)
                else
                    core.sendGlobalEvent('EnchantMachine_RemoveEnchant', {
                        actor = self.object,
                        item = entry.item,
                        settings = getSettings(),
                    })
                    ui.showMessage("Removing enchantment...")
                    closeMenu()
                end
            end
        ))
    end

    createMenu{
        header = { type = 'boxed', text = "Remove Enchantment" },
        info = isAttuned()
            and "Strips enchantments for a refund. The Heart's resonance allows unweaving single effects."
            or "Strips an item's enchantment and refunds soul power.",
        warning = "The item can then be enchanted normally (or have its capacity upgraded here).",
        items = items,
        onBack = function() createMainMenu() end,
    }
end

-- Per-effect removal (attunement perk): list the enchantment's effects, strip
-- one for a proportional refund, or fall through to full removal.
showRemoveEffectMenu = function(entry)
    closeMenu()

    local ench = core.magic.enchantments.records[entry.record.enchant]
    if not ench then
        ui.showMessage("The enchantment cannot be read.")
        async:newUnsavableSimulationTimer(1.5, function() showRemoveEnchantMenu() end)
        return
    end

    local function sendRemove(effectIndex)
        core.sendGlobalEvent('EnchantMachine_RemoveEnchant', {
            actor = self.object,
            item = entry.item,
            effectIndex = effectIndex,
            settings = getSettings(),
        })
        ui.showMessage(effectIndex and "Unweaving effect..." or "Removing enchantment...")
        closeMenu()
    end

    -- Mirror GLOBAL's refund math for the per-effect preview.
    local effectCount = 0
    for _ in ipairs(ench.effects) do effectCount = effectCount + 1 end
    local charge = ench.charge or 0
    local fullRefund = math.floor(charge > 0 and charge or (ench.cost or 0))
    local perEffectRefund = effectCount > 0 and math.floor(fullRefund / effectCount) or 0

    local items = {}
    for i, effect in ipairs(ench.effects) do
        table.insert(items, createButton(
            string.format("Unweave: %s (+%d power)", describeEffect(effect), perEffectRefund),
            function() sendRemove(i) end
        ))
    end
    table.insert(items, spacer(10))
    table.insert(items, createButton(
        string.format("Remove Entire Enchantment (+%d power)", fullRefund),
        function() sendRemove(nil) end
    ))

    createMenu{
        header = { type = 'boxed', text = "Unweave: " .. (entry.record.name or "Item") },
        info = "Choose a single effect to unweave, or strip the whole enchantment.",
        items = items,
        onBack = function() showRemoveEnchantMenu() end,
    }
end

-- "Add Enchantment" enchants an unenchanted item with one of the player's known
-- spells, entirely in Lua via the GLOBAL record-swap (see addEnchantment there).
-- The old native-UI handoff (I.UI.addMode('Enchanting')) is gone: it failed because
-- the engine's EnchantingDialog needs a Ptr the Lua API can't supply.
showAddEnchantMenu = function()
    closeMenu()

    local candidates = getEnchantableItems()
    if #candidates == 0 then
        ui.showMessage("You have no unenchanted weapons, armor, or clothing that can hold an enchantment.")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local items = {}
    for _, entry in ipairs(candidates) do
        local itemName = entry.record.name or "Item"
        local capacity = math.floor(entry.record.enchantCapacity or 0)
        if entry.enchanted then
            -- Weaving inherits the existing cast type, so skip the type menu.
            table.insert(items, createButton(
                string.format("%s (Enchanted — weave in more)", itemName),
                function() showSpellSelectMenu(entry, nil) end
            ))
        else
            table.insert(items, createButton(
                string.format("%s (Capacity: %d)", itemName, capacity),
                function() showEnchantTypeMenu(entry) end
            ))
        end
    end

    createMenu{
        header = { type = 'boxed', text = "Add Enchantment" },
        info = isAttuned()
            and "Choose an item, then a spell. The Heart's resonance lets you weave into existing enchantments."
            or "Choose an item, then how it casts, then a known spell to imbue.",
        items = items,
        onBack = function() createMainMenu() end,
    }
end

-- Cast-type descriptions shown on the spell-select screen. Keys are the strings
-- sent to GLOBAL as eventData.enchantType (mapped there to ENCHANTMENT_TYPE).
local ENCHANT_TYPE_INFO = {
    CastOnStrike = { label = "Cast on Strike", note = "Casts on whatever the weapon hits. Item arrives fully charged." },
    CastOnUse = { label = "Cast on Use", note = "Cast manually like a magic item. Item arrives fully charged." },
    ConstantEffect = { label = "Constant Effect", note = "Always active while equipped; effects become self-targeted. Never needs charge." },
}

showEnchantTypeMenu = function(entry)
    closeMenu()

    -- Cast on Strike is weapon-only; everything enchantable can take the others.
    local typeKeys = { 'CastOnUse', 'ConstantEffect' }
    if types.Weapon.objectIsInstance(entry.item) then
        table.insert(typeKeys, 1, 'CastOnStrike')
    end

    local items = {}
    for _, key in ipairs(typeKeys) do
        table.insert(items, createButton(
            ENCHANT_TYPE_INFO[key].label,
            function() showSpellSelectMenu(entry, key) end
        ))
    end

    createMenu{
        header = { type = 'boxed', text = "Enchant: " .. (entry.record.name or "Item") },
        info = "How should the enchantment trigger?",
        warning = "Constant Effect stays active while the item is equipped.",
        items = items,
        onBack = function() showAddEnchantMenu() end,
    }
end

local SPELL_PAGE_SIZE = 10

showSpellSelectMenu = function(entry, enchantType)
    closeMenu()

    local spells = getKnownSpells()
    if #spells == 0 then
        ui.showMessage("You know no castable spells to imbue.")
        async:newUnsavableSimulationTimer(1.5, function() showAddEnchantMenu() end)
        return
    end
    table.sort(spells, function(a, b)
        return (a.name or a.id):lower() < (b.name or b.id):lower()
    end)

    -- Weave mode (attunement perk): adding to an already-enchanted item. The
    -- existing cast type is inherited, so enchantType arrives as nil.
    local weaveType = nil
    if entry.enchanted then
        local ok, existing = pcall(function()
            return core.magic.enchantments.records[entry.record.enchant]
        end)
        weaveType = ok and existing and existing.type or nil
    end

    -- Pin the machine's Soul Siphon template for strike enchantments. The player
    -- never "knows" this spell — it's machine tech injected by load.lua, and the
    -- effect feeds soul power straight into the bank on every hit.
    if enchantType == 'CastOnStrike'
        or weaveType == core.magic.ENCHANTMENT_TYPE.CastOnStrike
    then
        local siphon = core.magic.spells.records['em_soul_siphon_spell']
        if siphon then
            local known = false
            for _, s in ipairs(spells) do
                if s.id == siphon.id then known = true; break end
            end
            if not known then table.insert(spells, 1, siphon) end
        end
    end

    local soulPower = getSoulPower()
    local settings = getSettings()
    local multiplier = settings.enchantMultiplier or 10
    -- Mirrors the GLOBAL charge calc: capacity * multiplier, filled to full 1:1.
    local charge = math.floor((entry.record.enchantCapacity or 0) * multiplier)
    local canAfford = soulPower >= charge

    local function spellButton(spell)
        local spellName = spell.name or spell.id
        return createButton(
            string.format("%s (cost %d)", spellName, math.floor(spell.cost or 0)),
            function() showNameItemMenu(entry, enchantType, spell) end,
            canAfford
        )
    end

    -- Search box + paged list. MWUI has no scroll container, so the list is
    -- capped at SPELL_PAGE_SIZE with Prev/Next paging, and the search box
    -- filters by name. listFlex is mutated in place and currentMenu:update()
    -- applies the change without recreating the focused text edit.
    local searchText = ''
    local page = 1
    local searchProps = { text = '', size = util.vector2(240, 24) }
    local listFlex = {
        type = ui.TYPE.Flex,
        props = { arrange = ui.ALIGNMENT.Center },
        content = ui.content{},
    }

    local function rebuildList()
        local needle = searchText:lower()
        local matches = {}
        for _, spell in ipairs(spells) do
            if needle == '' or (spell.name or spell.id):lower():find(needle, 1, true) then
                table.insert(matches, spell)
            end
        end

        local pageCount = math.max(1, math.ceil(#matches / SPELL_PAGE_SIZE))
        if page > pageCount then page = pageCount end

        local nodes = {}
        if #matches == 0 then
            table.insert(nodes, textLine("No known spells match.", { size = 14 }))
        end
        local first = (page - 1) * SPELL_PAGE_SIZE + 1
        for i = first, math.min(first + SPELL_PAGE_SIZE - 1, #matches) do
            table.insert(nodes, spellButton(matches[i]))
        end
        if pageCount > 1 then
            table.insert(nodes, buttonRow{
                createButton("< Prev", function()
                    page = page - 1
                    rebuildList()
                end, page > 1),
                textLine(string.format("  Page %d/%d (%d spells)  ", page, pageCount, #matches)),
                createButton("Next >", function()
                    page = page + 1
                    rebuildList()
                end, page < pageCount),
            })
        end

        listFlex.content = ui.content(nodes)
        if currentMenu then currentMenu:update() end
    end

    rebuildList()

    local typeInfo
    if entry.enchanted then
        typeInfo = {
            label = "Weave into existing enchantment",
            note = "New effects join the current enchantment. The matrix is re-forged and arrives fully charged.",
        }
    else
        typeInfo = ENCHANT_TYPE_INFO[enchantType] or ENCHANT_TYPE_INFO.CastOnUse
    end

    createMenu{
        header = { type = 'boxed', text = "Imbue: " .. (entry.record.name or "Item") },
        info = string.format("%s | Soul Power: %d | Cost to enchant: %d power",
            typeInfo.label, math.floor(soulPower), charge),
        warning = typeInfo.note,
        items = {
            textLine("Search:"),
            textInput(searchProps, function(text)
                searchProps.text = text
                searchText = text
                page = 1
                rebuildList()
            end),
            spacer(6),
            listFlex,
        },
        onBack = entry.enchanted
            and function() showAddEnchantMenu() end
            or function() showEnchantTypeMenu(entry) end,
    }
end

-- Final step of the imbue flow: optionally name the creation, then send the
-- AddEnchant event. A blank name keeps the item's original name.
showNameItemMenu = function(entry, enchantType, spell)
    closeMenu()

    local originalName = entry.record.name or "Item"
    local typed = ''
    local nameProps = { text = '', size = util.vector2(240, 24) }

    local function imbue()
        local name = typed:gsub('^%s+', ''):gsub('%s+$', '')
        if #name > 48 then name = name:sub(1, 48) end
        core.sendGlobalEvent('EnchantMachine_AddEnchant', {
            actor = self.object,
            item = entry.item,
            spellId = spell.id,
            enchantType = enchantType,
            customName = name ~= '' and name or nil,
            settings = getSettings(),
        })
        ui.showMessage("Imbuing enchantment...")
        closeMenu()
    end

    local typeLabel = entry.enchanted and "Weave"
        or (ENCHANT_TYPE_INFO[enchantType] or ENCHANT_TYPE_INFO.CastOnUse).label

    createMenu{
        header = { type = 'boxed', text = "Name Your Creation" },
        info = string.format("Imbuing %s with %s (%s)",
            originalName, spell.name or spell.id, typeLabel),
        warning = "Leave blank to keep the name \"" .. originalName .. "\".",
        items = {
            textInput(nameProps, function(text)
                nameProps.text = text
                typed = text
            end),
            spacer(10),
            createButton("Imbue", imbue),
        },
        onBack = function() showSpellSelectMenu(entry, enchantType) end,
    }
end

showCaptureSummonMenu = function()
    closeMenu()

    local candidates = getNearbySummonCandidates()
    if #candidates == 0 then
        ui.showMessage("No living creatures are close enough to mark.")
        async:newUnsavableSimulationTimer(1.5, function() createMainMenu() end)
        return
    end

    local items = {}
    for _, entry in ipairs(candidates) do
        local record = entry.record
        local creatureName = (record and record.name and record.name ~= "" and record.name) or entry.actor.recordId
        table.insert(items, createButton(
            string.format("%s (%d units)", creatureName, math.floor(entry.distance)),
            function()
                core.sendGlobalEvent('EnchantMachine_MarkCreature', {
                    actor = self.object,
                    target = entry.actor,
                    settings = getSettings(),
                })
                ui.showMessage("Marking creature...")
                closeMenu()
            end
        ))
    end

    createMenu{
        header = { type = 'boxed', text = "Mark Summon Creature" },
        info = "Choose a nearby creature. Defeat it while marked to learn a 60-second summon.",
        items = items,
        onBack = function() createMainMenu() end,
    }
end

attuneResonator = function()
    closeMenu()
    core.sendGlobalEvent('EnchantMachine_Attune', { actor = self.object })
    ui.showMessage("The resonator reaches outward...")
end

createMainMenu = function()
    closeMenu()

    local soulPower = getSoulPower()
    local settings = getSettings()

    local items = {}
    table.insert(items, createButton("Deposit Soul Gems", showDepositMenu))
    table.insert(items, createButton("Recharge Enchanted Items", showRechargeMenu))
    table.insert(items, createButton("Reinforce Charge Pool", showReinforceMenu))
    table.insert(items, createButton("Add Enchantment", showAddEnchantMenu))
    table.insert(items, createButton("Remove Enchantment", showRemoveEnchantMenu))
    table.insert(items, createButton("Mark Summon Creature", showCaptureSummonMenu))
    if settings.enableUpgradeFeature then
        table.insert(items, createButton("Upgrade Item Capacity", showUpgradeMenu))
    else
        table.insert(items, textLine("[Upgrade Capacity - Locked]",
            { size = 18, color = util.color.rgb(0.5, 0.5, 0.5) }))
    end
    if isAttuned() then
        table.insert(items, textLine("* Attuned to the Heart *",
            { size = 14, color = util.color.rgb(1, 0.85, 0.4) }))
    else
        table.insert(items, createButton("Attune Resonator", attuneResonator))
    end
    table.insert(items, spacer(20))
    table.insert(items, createButton("Exit", closeMenu))

    createMenu{
        header = { type = 'bare', text = "Dwemer Enchanting Machine", size = 30 },
        info = "Soul Power: " .. math.floor(soulPower),
        items = items,
    }
end

-- ---------- Boss cell detection ----------

local function checkBossCellEntry()
    local cell = self.object.cell
    if not cell then return end

    local currentCellName = cell.name or ""
    if currentCellName == lastCellName then return end
    lastCellName = currentCellName

    if not bossSpawnRequested and currentCellName == BOSS_CELL_NAME then
        bossSpawnRequested = true
        core.sendGlobalEvent('EnchantMachine_SpawnBoss', {})
    end
end

-- Start EM_DwemerDiscovery at stage 10 once the player is carrying the Dwemer
-- scroll (encoded or, after Baladas's swap, decoded). Self-healing across loads:
-- if the quest is already at/past stage 10 we just stop polling. addJournalEntry
-- is a no-op if the omwaddon lacks an entry at the stage. Called throttled (~1s).
local function checkScrollLooted()
    if scrollJournalDone then return end

    local quest = types.Player.quests(self.object)[SCROLL_QUEST_ID]
    if quest and (quest.stage or 0) >= SCROLL_LOOTED_STAGE then
        scrollJournalDone = true
        return
    end

    local inv = types.Actor.inventory(self.object)
    if inv:countOf(SCROLL_ITEM_ENCODED) > 0 or inv:countOf(SCROLL_ITEM_DECODED) > 0 then
        if quest then
            quest:addJournalEntry(SCROLL_LOOTED_STAGE)
            scrollJournalDone = true
        end
    end
end

-- ---------- Engine handlers ----------

local function onUpdate(dt)
    checkBossCellEntry()

    updateTimer = updateTimer + dt
    if updateTimer >= UPDATE_INTERVAL then
        updateTimer = 0
        statusSettings:set('soulPowerDisplay', tostring(math.floor(getSoulPower())))
        checkScrollLooted()
    end
end

local function onKeyPress(key)
    if key.symbol == 'Escape' and currentMenu then
        closeMenu()
    end
end

local function onSave()
    return {
        version = 1,
        bossSpawnRequested = bossSpawnRequested,
    }
end

local function onLoad(data)
    if data and data.version then
        bossSpawnRequested = data.bossSpawnRequested or false
    else
        bossSpawnRequested = false
    end
    -- One sync at load — subscribe() only fires on subsequent changes.
    syncSettingsToGlobal()
end

print("[EnchantMachine] Player script loaded successfully")

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onKeyPress = onKeyPress,
        onSave = onSave,
        onLoad = onLoad,
        onInactive = closeMenu,
    },
    eventHandlers = {
        EnchantMachine_Result = function(eventData)
            if eventData.success then
                ui.showMessage(eventData.message)
            else
                ui.showMessage("Error: " .. eventData.message)
            end
            -- Reopen the sub-menu the action came from so the player can act on
            -- the rest of the stack/list. Each sub-menu self-redirects to the main
            -- menu when its list is empty, so this is safe when nothing is left.
            local reopen = createMainMenu
            if eventData.operation == 'deposit' then
                reopen = showDepositMenu
            elseif eventData.operation == 'recharge' then
                reopen = showRechargeMenu
            elseif eventData.operation == 'reinforce' then
                reopen = showReinforceMenu
            elseif eventData.operation == 'upgrade' then
                reopen = showUpgradeMenu
            elseif eventData.operation == 'remove-enchant' then
                reopen = showRemoveEnchantMenu
            elseif eventData.operation == 'add-enchant' then
                reopen = showAddEnchantMenu
            elseif eventData.operation == 'mark-creature' then
                reopen = showCaptureSummonMenu
            end
            -- 'attune' (and any unknown op) falls through to the main menu.
            async:newUnsavableSimulationTimer(1.5, function() reopen() end)
        end,
        EnchantMachine_Message = function(eventData)
            if eventData and eventData.success == false then
                ui.showMessage("Error: " .. (eventData.message or "Unknown error"))
            elseif eventData and eventData.message then
                ui.showMessage(eventData.message)
            end
        end,
        EnchantMachine_OpenMenu = function()
            ui.showMessage("The ancient Dwemer machine hums to life, its crystalline interface beginning to shimmer with ethereal light...")
            async:newUnsavableSimulationTimer(1.5, function()
                local ok, err = pcall(createMainMenu)
                if not ok then
                    print("[EnchantMachine] ERROR creating menu:", err)
                    ui.showMessage("The machine sputters and falls silent... Something went wrong.")
                end
            end)
        end,
        -- OpenMW fires this when UI mode changes (e.g., ESC pressed).
        -- When mode becomes nil, Interface mode was exited.
        UiModeChanged = function(data)
            if currentMenu and data.newMode == nil then
                closeMenu()
            end
        end,
    },
}
