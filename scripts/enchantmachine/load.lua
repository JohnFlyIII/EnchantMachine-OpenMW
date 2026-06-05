-- Load script for records that must exist before a game starts.
-- OpenMW 0.51 load scripts can create content records with openmw.content.

local content = require('openmw.content')

local CAPTURE_MARK_EFFECT_ID = "em_capture_mark"
local CAPTURE_MARK_SPELL_ID = "em_capture_mark_spell"
local SUMMON_EFFECT_ID = "em_summon_echo"

local markTemplate = content.magicEffects.records["detectanimal"]
    or content.magicEffects.records["chameleon"]
local summonTemplate = content.magicEffects.records["summonscamp"]
    or content.magicEffects.records["commandcreature"]

content.magicEffects.records[CAPTURE_MARK_EFFECT_ID] = {
    template = markTemplate,
    name = "Resonant Mark",
    baseCost = 1,
    school = "conjuration",
    harmful = false,
    hasDuration = true,
    hasMagnitude = false,
}

content.magicEffects.records[SUMMON_EFFECT_ID] = {
    template = summonTemplate,
    name = "Summon Echo",
    baseCost = 1,
    school = "conjuration",
    harmful = false,
    hasDuration = true,
    hasMagnitude = false,
}

content.spells.records[CAPTURE_MARK_SPELL_ID] = {
    name = "Resonant Mark",
    type = content.spells.TYPE.Spell,
    cost = 1,
    isAutocalc = false,
    starterSpellFlag = false,
    effects = {
        {
            id = CAPTURE_MARK_EFFECT_ID,
            range = content.RANGE.Self,
            area = 0,
            duration = 86400,
        },
    },
}

return {}
