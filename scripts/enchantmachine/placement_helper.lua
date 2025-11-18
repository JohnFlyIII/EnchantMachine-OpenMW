-- Placement Helper for Dwemer Enchanting Machine
-- Helps place and manage machine objects in the game world

local core = require('openmw.core')
local world = require('openmw.world')
local types = require('openmw.types')
local util = require('openmw.util')
local storage = require('openmw.storage')

-- Storage for placed machines
local machineStorage = storage.globalSection('EnchantMachine_Placements')

-- Initialize placement data
local function ensurePlacementData()
    if not machineStorage:get('machines') then
        machineStorage:set('machines', {})
    end
end

-- Predefined machine locations (examples)
local PREDEFINED_LOCATIONS = {
    {
        id = "balmora_mages_guild",
        cell = "Balmora, Guild of Mages",
        position = util.vector3(0, 0, 0),  -- Adjust coordinates
        rotation = util.vector3(0, 0, 0),
        description = "Balmora Mages Guild - Basement",
    },
    {
        id = "vivec_telvanni",
        cell = "Vivec, Telvanni Canton",
        position = util.vector3(0, 0, 0),
        rotation = util.vector3(0, 0, 0),
        description = "Vivec Telvanni - Tower",
    },
    {
        id = "dwemer_ruin_01",
        cell = "Arkngthand, Hall of Centrifuge",
        position = util.vector3(0, 0, 0),
        rotation = util.vector3(0, 0, 0),
        description = "Arkngthand - Deep chamber",
    },
}

-- Recommended activator objects for machine placement
local ACTIVATOR_TEMPLATES = {
    "dwrv_machine00",        -- Dwemer machine (perfect thematic fit)
    "dwrv_console00",        -- Dwemer console
    "active_dwrv_artifact00", -- Dwemer artifact
    "dwrv_centurion_base",   -- Centurion base (large)
    "dwrv_device_01",        -- Generic Dwemer device
}

-- Register a placed machine
local function registerMachine(objectRef, locationId, description)
    ensurePlacementData()

    local machines = machineStorage:get('machines') or {}

    local machineData = {
        objectId = objectRef.id,
        locationId = locationId or "custom_" .. #machines + 1,
        description = description or "Custom placement",
        position = objectRef.position,
        cell = objectRef.cell.name or "Unknown",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    }

    table.insert(machines, machineData)
    machineStorage:set('machines', machines)

    return true, machineData
end

-- Get all registered machines
local function getRegisteredMachines()
    ensurePlacementData()
    return machineStorage:get('machines') or {}
end

-- Place a machine at predefined location
local function placeAtPredefinedLocation(locationId)
    local location = nil
    for _, loc in ipairs(PREDEFINED_LOCATIONS) do
        if loc.id == locationId then
            location = loc
            break
        end
    end

    if not location then
        return false, "Location not found: " .. locationId
    end

    -- Note: Actual spawning would require different approach depending on how
    -- you want to handle it (ESP/ESM files vs runtime spawning)
    print(string.format("Place machine at: %s (%s)", location.description, location.cell))
    print("Instructions:")
    print("1. Open OpenMW-CS")
    print("2. Navigate to cell: " .. location.cell)
    print("3. Place activator object (recommended: dwrv_machine00)")
    print("4. Attach script: scripts/EnchantMachine/machine.lua")
    print("5. Save your plugin")

    return true, location
end

-- Attach machine script to nearest object
local function attachToNearestObject(player, maxDistance)
    maxDistance = maxDistance or 500  -- Default 500 units

    local playerPos = player.position
    local nearestObject = nil
    local nearestDistance = maxDistance

    -- Search for nearby objects in the same cell
    for _, obj in ipairs(player.cell:getAll()) do
        if types.Activator.objectIsInstance(obj) then
            local distance = (obj.position - playerPos):length()
            if distance < nearestDistance then
                nearestObject = obj
                nearestDistance = distance
            end
        end
    end

    if not nearestObject then
        return false, "No activator objects found within range"
    end

    -- Attach script
    -- Note: This might not work in all contexts - OpenMW Lua has limitations
    -- on attaching scripts at runtime
    local success = pcall(function()
        core.attachScript("scripts/EnchantMachine/machine.lua", nearestObject)
    end)

    if success then
        registerMachine(nearestObject, nil, "Runtime attachment")
        return true, string.format("Attached to object at distance %.1f", nearestDistance)
    else
        return false, "Failed to attach script (runtime attachment may not be supported)"
    end
end

-- Generate placement report
local function generatePlacementReport()
    local machines = getRegisteredMachines()

    local report = {}
    table.insert(report, "=== MACHINE PLACEMENT REPORT ===")
    table.insert(report, string.format("Total Machines: %d", #machines))
    table.insert(report, "")

    if #machines == 0 then
        table.insert(report, "No machines registered yet.")
    else
        for i, machine in ipairs(machines) do
            table.insert(report, string.format("%d. %s", i, machine.description))
            table.insert(report, string.format("   Cell: %s", machine.cell))
            table.insert(report, string.format("   Location ID: %s", machine.locationId))
            table.insert(report, string.format("   Placed: %s", machine.timestamp))
            table.insert(report, "")
        end
    end

    return table.concat(report, "\n")
end

-- Generate ESP placement instructions
local function generateESPInstructions()
    local instructions = {}

    table.insert(instructions, "=== MACHINE PLACEMENT GUIDE (ESP Creation) ===")
    table.insert(instructions, "")
    table.insert(instructions, "METHOD 1: Using OpenMW-CS (Recommended)")
    table.insert(instructions, "")
    table.insert(instructions, "1. Open OpenMW-CS")
    table.insert(instructions, "2. File -> New Content")
    table.insert(instructions, "3. Load Morrowind.esm and dependencies")
    table.insert(instructions, "4. Navigate to: World -> Cells")
    table.insert(instructions, "5. Find desired cell (e.g., 'Balmora, Guild of Mages')")
    table.insert(instructions, "6. Add activator object:")
    table.insert(instructions, "   - Recommended: dwrv_machine00 (Dwemer Machine)")
    table.insert(instructions, "   - Alternative: dwrv_console00 (Dwemer Console)")
    table.insert(instructions, "7. Select the placed object")
    table.insert(instructions, "8. Right-click -> Edit")
    table.insert(instructions, "9. In Scripts tab, add: scripts/EnchantMachine/machine.lua")
    table.insert(instructions, "10. Save as new plugin (e.g., EnchantMachine_Placements.esp)")
    table.insert(instructions, "11. Enable plugin in OpenMW Launcher")
    table.insert(instructions, "")
    table.insert(instructions, "METHOD 2: Console Commands (Temporary Testing)")
    table.insert(instructions, "")
    table.insert(instructions, "1. In-game, press F3 (open console)")
    table.insert(instructions, "2. Click on existing activator object")
    table.insert(instructions, "3. Type: \"reference\"->addscript \"scripts/EnchantMachine/machine.lua\"")
    table.insert(instructions, "4. Close console and activate object")
    table.insert(instructions, "")
    table.insert(instructions, "METHOD 3: Place New Object (Advanced)")
    table.insert(instructions, "")
    table.insert(instructions, "1. Console: PlaceAtPC \"dwrv_machine00\" 1 128 0")
    table.insert(instructions, "2. Console: Click on spawned object")
    table.insert(instructions, "3. Console: \"reference\"->addscript \"scripts/EnchantMachine/machine.lua\"")
    table.insert(instructions, "")
    table.insert(instructions, "RECOMMENDED LOCATIONS:")
    for _, loc in ipairs(PREDEFINED_LOCATIONS) do
        table.insert(instructions, string.format("  - %s (%s)", loc.description, loc.cell))
    end
    table.insert(instructions, "")

    return table.concat(instructions, "\n")
end

-- Console commands
local function onConsoleCommand(mode, command)
    if mode ~= 'global' then return end

    if command == "em_place_help" then
        print(generateESPInstructions())
        return true
    end

    if command == "em_place_list" then
        print(generatePlacementReport())
        return true
    end

    if command:match("^em_place_at%s+(.+)") then
        local locationId = command:match("^em_place_at%s+(.+)")
        local success, result = placeAtPredefinedLocation(locationId)
        if success then
            print("Location info retrieved. Follow instructions above.")
        else
            print("Error: " .. result)
        end
        return true
    end

    if command == "em_place_locations" then
        print("Available predefined locations:")
        for _, loc in ipairs(PREDEFINED_LOCATIONS) do
            print(string.format("  %s - %s (%s)", loc.id, loc.description, loc.cell))
        end
        print("\nUse: em_place_at <location_id>")
        return true
    end

    if command == "em_place_register" then
        print("To register current machine, use console to select it first:")
        print("1. Click on machine object in console")
        print("2. Not yet implemented - use em_place_help for placement guide")
        return true
    end

    if command == "em_place_templates" then
        print("Recommended Dwemer activator templates:")
        for i, template in ipairs(ACTIVATOR_TEMPLATES) do
            print(string.format("%d. %s", i, template))
        end
        print("\nUse in console: PlaceAtPC \"<template>\" 1 128 0")
        return true
    end

    return false
end

return {
    engineHandlers = {
        onConsoleCommand = onConsoleCommand,
    },
    interface = {
        registerMachine = registerMachine,
        getRegisteredMachines = getRegisteredMachines,
        placeAtPredefinedLocation = placeAtPredefinedLocation,
        generatePlacementReport = generatePlacementReport,
        generateESPInstructions = generateESPInstructions,
        PREDEFINED_LOCATIONS = PREDEFINED_LOCATIONS,
        ACTIVATOR_TEMPLATES = ACTIVATOR_TEMPLATES,
    },
}
