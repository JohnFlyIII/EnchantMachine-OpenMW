-- One-time boss encounter that guards the Dwemer Enchanting Machine Remote.
-- Triggered when the player first enters the configured cell.

local world = require('openmw.world')
local types = require('openmw.types')
local util = require('openmw.util')
local I = require('openmw.interfaces')

-- Forwarding wrapper for the optional debug interface — same pattern as global.lua.
local dbg = setmetatable({}, {
    __index = function(_, method)
        return function(...)
            local d = I.EnchantMachineDebug
            if d and d[method] then return d[method](...) end
        end
    end,
})

-- Vanilla dwarven ghost may be redefined by other mods. Try each candidate
-- until one creates successfully and use it as both boss and guards.
local DWARVEN_GHOST_CANDIDATES = {
    "dwarven ghost",
    "bs_dwarven ghost_uni",
    "dwarven ghost_radac",
    "dwarven ghost_jeanne_u",
    "roht_dwarvenshade",
}
local CREATURE_CENTURION_STEAM = "centurion_steam"

local SPAWN_LOCATIONS = {
    {
        cell = "Arkngthand, Deep Ore Passage",
        pos = util.vector3(6350, 750, 1280),
        description = "Deep in the ore passage, where the Dwemer kept their secrets",
    },
    {
        cell = "Arkngthand, Weepingbell Hall",
        pos = util.vector3(3200, 2900, 200),
        description = "By the ancient forge where the machine was created",
    },
    {
        cell = "Bthuand, Workshop",
        pos = util.vector3(2800, 2400, 350),
        description = "The Master's private workshop, where experiments took place",
    },
    {
        cell = "Nchuleftingth, Test of Pattern",
        pos = util.vector3(3500, 3800, 100),
        description = "The testing chambers where Dwemer technology was perfected",
    },
}

-- Pick location 1-4 (see SPAWN_LOCATIONS above).
local CHOSEN_LOCATION = 1

local bossSpawned = false

-- Find up to `limit` creature IDs that contain `searchTerm` (case-insensitive).
local function findSimilarCreatures(searchTerm, limit)
    local matches = {}
    local term = string.lower(searchTerm)
    for _, record in pairs(types.Creature.records) do
        if record.id and string.find(string.lower(record.id), term) then
            table.insert(matches, record.id)
            if #matches >= (limit or 10) then break end
        end
    end
    return matches
end

-- Try the candidate list and return the first creature that creates successfully,
-- along with the id that worked.
local function createDwarvenGhost()
    for _, candidateId in ipairs(DWARVEN_GHOST_CANDIDATES) do
        local ok, result = pcall(world.createObject, candidateId, 1)
        if ok and result then
            return result, candidateId
        end
    end
    return nil, nil
end

-- Best-effort: create `count` of `itemId` and move them into `inventory`.
-- Logs a warning on failure but doesn't abort the caller.
local function addLoot(inventory, itemId, count)
    local ok, item = pcall(world.createObject, itemId, count)
    if ok and item then
        item:moveInto(inventory)
        return item
    end
    dbg.warn("Loot", "Could not create '" .. itemId .. "': " .. tostring(item))
end

-- Best-effort: create + teleport a guard. Returns the object or nil.
local function spawnGuard(creatureId, cell, position, label)
    local ok, guard = pcall(world.createObject, creatureId, 1)
    if not ok or not guard then
        dbg.warn("Boss", "Failed to spawn " .. label .. ": " .. tostring(guard))
        return nil
    end
    guard:teleport(cell, position)
    return guard
end

local function spawnResearcher()
    if bossSpawned then return end

    local location = SPAWN_LOCATIONS[CHOSEN_LOCATION]
    dbg.info("Boss", "Spawning at " .. location.cell)

    if not types.Creature.records[CREATURE_CENTURION_STEAM] then
        dbg.error("Boss", "Centurion record missing: '" .. CREATURE_CENTURION_STEAM .. "'")
        local similar = findSimilarCreatures("centurion")
        if #similar > 0 then
            dbg.info("Boss", "Similar creatures: " .. table.concat(similar, ", "))
        end
        return
    end

    local cell = world.getCellByName(location.cell)
    if not cell then
        dbg.error("Boss", "Cell not found: " .. location.cell)
        return
    end

    local masterResearcher, workingGhostId = createDwarvenGhost()
    if not masterResearcher then
        dbg.error("Boss", "No working dwarven ghost found — likely a mod conflict")
        local similar = findSimilarCreatures("dwarven")
        if #similar > 0 then
            dbg.info("Boss", "Available dwarven creatures: " .. table.concat(similar, ", "))
        end
        return
    end

    local basePos = location.pos
    masterResearcher:teleport(cell, basePos)

    local bossInventory = types.Actor.inventory(masterResearcher)

    -- The remote: the actual reward. Fall back to a vanilla artifact if the
    -- record creation fails for any reason (e.g. omwaddon missing template).
    local remote = I.EnchantMachine and I.EnchantMachine.createRemoteItem()
    if remote then
        remote:moveInto(bossInventory)
    else
        dbg.error("Boss", "Could not create remote — adding fallback artifact")
        addLoot(bossInventory, "misc_dwrv_artifact00", 1)
    end

    -- The Dwemer scroll: a second loot item. Reading/obtaining it starts the
    -- EM_DwemerDiscovery quest (journal stage 10, detected by player_full.lua).
    local scroll = I.EnchantMachine and I.EnchantMachine.createDwemerScroll()
    if scroll then
        scroll:moveInto(bossInventory)
    else
        dbg.warn("Boss", "Could not create Dwemer scroll loot")
    end

    addLoot(bossInventory, "gold_001", 1000)
    addLoot(bossInventory, "misc_dwrv_coin00", 10)
    addLoot(bossInventory, "misc_dwrv_artifact60", 1)

    -- Guards: two ghosts flanking, one centurion in front.
    local guards = {
        { id = workingGhostId,            offset = util.vector3(-150, 100, 0), label = "Ghost L", gold = 200, coins = 3 },
        { id = workingGhostId,            offset = util.vector3( 150, 100, 0), label = "Ghost R", gold = 200, coins = 3 },
        { id = CREATURE_CENTURION_STEAM,  offset = util.vector3(   0, 150, 0), label = "Centurion", gold = 300, coins = 0 },
    }
    for _, g in ipairs(guards) do
        local guard = spawnGuard(g.id, cell, basePos + g.offset, g.label)
        if guard then
            local inv = types.Actor.inventory(guard)
            if g.gold > 0 then addLoot(inv, "gold_001", g.gold) end
            if g.coins > 0 then addLoot(inv, "misc_dwrv_coin00", g.coins) end
        end
    end

    bossSpawned = true
    dbg.info("Boss", "Encounter spawned at " .. location.cell .. " — will not spawn again")
end

return {
    eventHandlers = {
        EnchantMachine_SpawnBoss = function()
            if not bossSpawned then spawnResearcher() end
        end,
    },
    engineHandlers = {
        onSave = function()
            return { version = 1, bossSpawned = bossSpawned }
        end,
        onLoad = function(data)
            bossSpawned = (data and data.bossSpawned) or false
        end,
    },
}
