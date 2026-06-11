-- Load script for records that must exist before a game starts.
-- OpenMW 0.51 load scripts can create content records with openmw.content.

local content = require('openmw.content')

local CAPTURE_MARK_EFFECT_ID = "em_capture_mark"
local CAPTURE_MARK_SPELL_ID = "em_capture_mark_spell"
local SUMMON_EFFECT_ID = "em_summon_echo"
local SIPHON_EFFECT_ID = "em_soul_siphon"
local SIPHON_SPELL_ID = "em_soul_siphon_spell"

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

-- Soul Siphon: the machine's signature weapon enchantment. The effect itself has
-- no engine behaviour — GLOBAL polls active actors for it (checkSoulSiphons) and
-- banks the rolled magnitude as soul power, then strips the active spell.
local siphonTemplate = content.magicEffects.records["soultrap"]
    or content.magicEffects.records["absorbhealth"]

content.magicEffects.records[SIPHON_EFFECT_ID] = {
    template = siphonTemplate,
    name = "Soul Siphon",
    baseCost = 5,
    school = "mysticism",
    harmful = true,
    hasDuration = true,
    hasMagnitude = true,
}

-- The imbue template the machine offers for Cast-on-Strike enchantments. Not
-- taught to the player; the spell-select menu pins it at the top of the list.
-- Duration must comfortably outlast GLOBAL's 0.5s siphon poll so hits between
-- polls aren't lost. cost becomes the enchantment's PER-STRIKE charge cost —
-- keep it low or a modest charge pool only covers a couple of swings.
content.spells.records[SIPHON_SPELL_ID] = {
    name = "Soul Siphon",
    type = content.spells.TYPE.Spell,
    cost = 5,
    isAutocalc = false,
    starterSpellFlag = false,
    effects = {
        {
            id = SIPHON_EFFECT_ID,
            range = content.RANGE.Touch,
            area = 0,
            duration = 3,
            magnitudeMin = 5,
            magnitudeMax = 25,
        },
    },
}

return {}
