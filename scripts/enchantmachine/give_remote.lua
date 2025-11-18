-- Helper script to give player the Enchanting Machine remote control
-- Run this ONCE to give the player the remote item

local world = require('openmw.world')
local core = require('openmw.core')
local types = require('openmw.types')

-- Function to give remote to player
local function giveRemoteToPlayer()
    print("[EnchantMachine] Creating remote control item...")

    -- Use a vanilla scroll as the base (doesn't consume when used)
    -- Or use a misc item that looks Dwemer
    local remoteId = "sc_windwalker"  -- Windwalker scroll (vanilla, looks magical)

    -- Create the item
    local remote = world.createObject(remoteId, 1)

    -- Attach our script to it
    core.attachScript("scripts/enchantmachine/remote.lua", remote)

    -- Find player and give them the item
    for _, player in ipairs(world.players) do
        local inventory = types.Actor.inventory(player)
        remote:moveInto(inventory)

        print("[EnchantMachine] Remote control added to player inventory!")
        print("[EnchantMachine] Use the scroll to open the Enchanting Machine menu.")

        return true
    end

    return false
end

return {
    engineHandlers = {
        onInit = function()
            -- Give remote on game start (runs once)
            giveRemoteToPlayer()
        end,
    },
}
