-- Local script for Dwemer Enchanting Machine activators
-- Handles activation and sends signal to player script to open UI

local self = require('openmw.self')
local types = require('openmw.types')

-- Handler for when the machine is activated
local function onActivated(actor)
    -- Only respond to player activation
    if not types.Player.objectIsInstance(actor) then
        return
    end

    -- Send event to player script to open the machine UI
    actor:sendEvent('EnchantMachine_OpenMenu', {
        machine = self.object
    })
end

return {
    engineHandlers = {
        onActivated = onActivated,
    },
}
