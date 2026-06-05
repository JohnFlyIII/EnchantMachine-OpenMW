-- Local script attached to NPCs and creatures. Only creatures use it.
-- GLOBAL applies the mark; this script observes death while the creature is active.

local self = require('openmw.self')
local core = require('openmw.core')
local types = require('openmw.types')

local CAPTURE_MARK_SPELL_ID = "em_capture_mark_spell"
local CHECK_INTERVAL = 0.5

local marked = false
local captured = false
local marker = nil
local updateTimer = 0

local function hasActiveMark()
    local ok, result = pcall(function()
        return types.Actor.activeSpells(self.object):isSpellActive(CAPTURE_MARK_SPELL_ID)
    end)
    return ok and result
end

local function clearMark()
    marked = false
    captured = false
    marker = nil
end

local function onUpdate(dt)
    if not marked or captured then return end
    if not types.Creature.objectIsInstance(self.object) then
        clearMark()
        return
    end

    if types.Actor.isDead(self.object) then
        captured = true
        core.sendGlobalEvent('EnchantMachine_MarkedCreatureDied', {
            creature = self.object,
            marker = marker,
        })
        return
    end

    updateTimer = updateTimer + dt
    if updateTimer < CHECK_INTERVAL then return end
    updateTimer = 0

    if not hasActiveMark() then
        clearMark()
    end
end

local function onSave()
    return {
        version = 1,
        marked = marked,
        captured = captured,
        marker = marker,
    }
end

local function onLoad(data)
    marked = (data and data.marked) or false
    captured = (data and data.captured) or false
    marker = data and data.marker or nil
    updateTimer = 0
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad,
    },
    eventHandlers = {
        EnchantMachine_SetSoulMark = function(data)
            if not types.Creature.objectIsInstance(self.object) then return end
            marked = true
            captured = false
            marker = data and data.marker or nil
            updateTimer = 0
        end,
    },
}
