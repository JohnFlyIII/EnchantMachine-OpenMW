-- Local script attached to Lua-spawned custom summons.
-- It keeps the creature following the player and asks GLOBAL to remove it on expiry.

local self = require('openmw.self')
local core = require('openmw.core')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local DEFAULT_DURATION = 60
local AI_REFRESH_INTERVAL = 3

local owner = nil
local creatureName = "creature"
local expireAt = 0
local aiTimer = 0
local removing = false

local function isValidObject(object)
    if not object then return false end
    local ok, valid = pcall(function() return object:isValid() end)
    return ok and valid
end

local function pacifySummon()
    pcall(function() types.Actor.stats.ai.fight(self.object).base = 0 end)
    pcall(function() types.Actor.stats.ai.flee(self.object).base = 0 end)
    pcall(function() types.Actor.stats.ai.alarm(self.object).base = 0 end)
end

local function startFollow()
    if not isValidObject(owner) then return end
    pacifySummon()
    local ok = pcall(function()
        I.AI.startPackage({
            type = 'Follow',
            target = owner,
            distance = 128,
            sideWithTarget = true,
            cancelOther = true,
        })
    end)
    if not ok then
        pcall(function()
            I.AI.startPackage({
                type = 'Follow',
                target = owner,
                distance = 128,
                cancelOther = true,
            })
        end)
    end
end

local function requestRemoval()
    if removing then return end
    removing = true
    core.sendGlobalEvent('EnchantMachine_RemoveSummon', {
        summon = self.object,
        creatureName = creatureName,
    })
end

local function initialize(initData)
    initData = initData or {}
    owner = initData.owner
    creatureName = initData.creatureName or creatureName
    expireAt = core.getSimulationTime() + (initData.duration or DEFAULT_DURATION)
    aiTimer = AI_REFRESH_INTERVAL
    removing = false
    startFollow()
end

local function onUpdate(dt)
    if removing then return end
    if types.Actor.isDead(self.object) then
        requestRemoval()
        return
    end
    if expireAt > 0 and core.getSimulationTime() >= expireAt then
        requestRemoval()
        return
    end

    aiTimer = aiTimer + dt
    if aiTimer >= AI_REFRESH_INTERVAL then
        aiTimer = 0
        startFollow()
    end
end

local function onSave()
    return {
        version = 1,
        owner = owner,
        creatureName = creatureName,
        expireAt = expireAt,
        removing = removing,
    }
end

local function onLoad(data, initData)
    if data and data.version then
        owner = data.owner
        creatureName = data.creatureName or creatureName
        expireAt = data.expireAt or 0
        removing = data.removing or false
    else
        initialize(initData)
    end
    aiTimer = AI_REFRESH_INTERVAL
end

return {
    engineHandlers = {
        onInit = initialize,
        onActive = startFollow,
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad,
    },
}
