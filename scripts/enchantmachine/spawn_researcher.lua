-- Spawn THE Master Dwemer Researcher - a unique, extremely challenging boss encounter
-- This is a one-time spawn that guards the Enchanting Machine remote

local world = require('openmw.world')
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')

-- In-memory tracking - saved/loaded with save file
-- This way each save file has its own boss spawn state
local bossSpawned = false

-- Vanilla Dwemer ruin locations - carefully selected for atmosphere and accessibility
-- The boss will spawn in ONE of these locations (configured below)
local SPAWN_LOCATIONS = {
    -- 1. Arkngthand, Deep Ore Passage (RECOMMENDED - Quiet area with chest, perfect for discovery)
    {
        cell = "Arkngthand, Deep Ore Passage",
        pos = util.vector3(6350, 750, 1280),  -- Near dwrv_chest00
        rot = util.vector3(0, 0, 0),
        description = "Deep in the ore passage, where the Dwemer kept their secrets"
    },

    -- 2. Arkngthand, Weepingbell Hall (Alternative - Main hall, easier to find)
    {
        cell = "Arkngthand, Weepingbell Hall",
        pos = util.vector3(3200, 2900, 200),  -- Near the forge area
        rot = util.vector3(0, 0, 0),
        description = "By the ancient forge where the machine was created"
    },

    -- 3. Bthuand, Workshop (Alternative - Deeper ruins for higher level players)
    {
        cell = "Bthuand, Workshop",
        pos = util.vector3(2800, 2400, 350),  -- Central workshop area
        rot = util.vector3(0, 0, 0),
        description = "The Master's private workshop, where experiments took place"
    },

    -- 4. Nchuleftingth, Test of Pattern (Alternative - Challenging location)
    {
        cell = "Nchuleftingth, Test of Pattern",
        pos = util.vector3(3500, 3800, 100),  -- Large chamber with good space
        rot = util.vector3(0, 0, 0),
        description = "The testing chambers where Dwemer technology was perfected"
    },
}

-- ========== CONFIGURATION ==========
-- Select which location to use (1-4):
--   1 = Arkngthand, Deep Ore Passage (RECOMMENDED - Quiet area with chest)
--   2 = Arkngthand, Weepingbell Hall (Main hall, easier to find)
--   3 = Bthuand, Workshop (Deeper, more challenging)
--   4 = Nchuleftingth, Test of Pattern (Large ruins, harder to find)
local CHOSEN_LOCATION = 1
-- ===================================

local function spawnResearcher()
    -- Check if boss has already been spawned (in this save file)
    if bossSpawned then
        print("[EnchantMachine] The Master Researcher has already been encountered in this save.")
        return
    end

    local location = SPAWN_LOCATIONS[CHOSEN_LOCATION]

    print("[EnchantMachine] ========================================")
    print("[EnchantMachine] WARNING: Spawning UNIQUE BOSS ENCOUNTER")
    print("[EnchantMachine] The Master Dwemer Researcher and Guards")
    print("[EnchantMachine] Location: " .. location.cell)
    print("[EnchantMachine] " .. location.description)
    print("[EnchantMachine] ========================================")

    -- Get the cell
    local cell = world.getCellByName(location.cell)
    if not cell then
        print("[EnchantMachine] ERROR: Cell not found: " .. location.cell)
        return
    end

    local basePos = location.pos

    -- BOSS: The Master Dwemer Researcher (Dwarven Ghost - ancient Dwemer spirit)
    print("[EnchantMachine] Spawning BOSS: Master Researcher (Dwarven Ghost)")
    local masterResearcher = world.createObject("dwarven ghost", 1)
    masterResearcher:teleport(cell, basePos)

    -- Add valuable loot to BOSS including the REMOTE!
    local bossInventory = types.Actor.inventory(masterResearcher)

    -- Add the Enchanting Machine Remote (custom item from omwaddon)
    local remote = world.createObject("enchant_machine_remote", 1)
    remote:moveInto(bossInventory)
    print("[EnchantMachine] Added remote control to boss inventory")

    -- Add gold and Dwemer artifacts
    world.createObject("gold_001", 1000):moveInto(bossInventory)
    world.createObject("misc_dwrv_coin00", 10):moveInto(bossInventory)
    world.createObject("misc_dwrv_artifact60", 1):moveInto(bossInventory)  -- Dwemer tube as bonus

    -- GUARDS: Additional Dwemer enemies to make this VERY hard
    print("[EnchantMachine] Spawning GUARDS...")

    -- Guard 1: Dwarven Ghost (to the left, closer)
    local guard1 = world.createObject("dwarven ghost", 1)
    local guard1Pos = util.vector3(basePos.x - 150, basePos.y + 100, basePos.z)
    guard1:teleport(cell, guard1Pos)
    print("[EnchantMachine] Guard 1 spawned at: " .. guard1Pos.x .. ", " .. guard1Pos.y .. ", " .. guard1Pos.z)
    local guard1Inv = types.Actor.inventory(guard1)
    world.createObject("gold_001", 200):moveInto(guard1Inv)
    world.createObject("misc_dwrv_coin00", 3):moveInto(guard1Inv)

    -- Guard 2: Dwarven Ghost (to the right, closer)
    local guard2 = world.createObject("dwarven ghost", 1)
    local guard2Pos = util.vector3(basePos.x + 150, basePos.y + 100, basePos.z)
    guard2:teleport(cell, guard2Pos)
    print("[EnchantMachine] Guard 2 spawned at: " .. guard2Pos.x .. ", " .. guard2Pos.y .. ", " .. guard2Pos.z)
    local guard2Inv = types.Actor.inventory(guard2)
    world.createObject("gold_001", 200):moveInto(guard2Inv)
    world.createObject("misc_dwrv_coin00", 3):moveInto(guard2Inv)

    -- Guard 3: Steam Centurion (in front, closer)
    local guard3 = world.createObject("centurion_steam", 1)
    local guard3Pos = util.vector3(basePos.x, basePos.y + 150, basePos.z)
    guard3:teleport(cell, guard3Pos)
    print("[EnchantMachine] Guard 3 spawned at: " .. guard3Pos.x .. ", " .. guard3Pos.y .. ", " .. guard3Pos.z)
    local guard3Inv = types.Actor.inventory(guard3)
    world.createObject("gold_001", 300):moveInto(guard3Inv)

    -- Mark as spawned in this save file
    bossSpawned = true

    print("[EnchantMachine] ========================================")
    print("[EnchantMachine] BOSS ENCOUNTER SPAWNED!")
    print("[EnchantMachine] Enemies: 3x Dwarven Ghosts + 1x Steam Centurion")
    print("[EnchantMachine] Defeat the Master to claim the Remote!")
    print("[EnchantMachine] This encounter will NOT spawn again in this save.")
    print("[EnchantMachine] ========================================")
    print("")
    print("[EnchantMachine] How to use the Remote:")
    print("[EnchantMachine] 1. Defeat the boss and loot the Remote")
    print("[EnchantMachine] 2. Find 'Dwemer Enchanting Machine Remote' in inventory")
    print("[EnchantMachine] 3. Drag it onto your character model to activate")
    print("[EnchantMachine] 4. The machine menu will open!")
    print("[EnchantMachine] ========================================")
end

-- Event handler: PLAYER script sends this when entering boss cell
local function onSpawnBossRequest(eventData)
    print("[EnchantMachine] Received spawn request from player script")

    if bossSpawned then
        print("[EnchantMachine] Boss already spawned, ignoring request")
        return
    end

    spawnResearcher()
end

return {
    eventHandlers = {
        EnchantMachine_SpawnBoss = onSpawnBossRequest,
    },

    engineHandlers = {
        onSave = function()
            -- Save boss spawn state with save file
            return {
                version = 1,
                bossSpawned = bossSpawned,
            }
        end,

        onLoad = function(data)
            -- Restore boss spawn state from save file
            if data and data.version then
                bossSpawned = data.bossSpawned or false
            else
                bossSpawned = false
            end

            print("[EnchantMachine] Boss spawn state loaded: " .. tostring(bossSpawned))
        end,
    },
}
