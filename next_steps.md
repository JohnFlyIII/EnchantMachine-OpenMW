# Next Steps — EM_DwemerDiscovery feature

**Status (2026-05-31):** Narrative finalized. Scrolls, the five journal entries, **and the Baladas dialogue stack (two topics + greeting)** are now entered in `EnchantMachine.omwaddon` via OpenMW-CS. **Lua stage-10 trigger + scroll loot are wired** (see "Lua work"). Remaining work: the facility/dungeon cell and the Array activator + reward script (stage 40), plus the reward decision (#3) and the `MG_Dwarves` stage-70 verify.

> This file is the resume point for whoever picks this up next session. It contains the full design, the CS/Lua work remaining, all final prose, and the open decisions. Self-contained — should be readable with no prior context.

> **Design note — supersedes earlier draft (2026-05-28):** An earlier version of this quest had the decoded scroll give *directions to "The Master's Workshop"* on a hidden, unnamed mountain, with a 3-stage journal (10/20/100) gated on `MG_Dwarves ≥ 70`. **That is overridden.** The move to Red Mountain and the Heart Chamber — the scroll as a *Resonance Vessel* of a *Harmonics Array* — replaced those first thoughts. The current design below is canonical. (Old prose preserved only in git history / the 2026-05-28 transcript if ever needed.)

> **Tooling note (researched 2026-05-31 — don't re-investigate):** Editing `EnchantMachine.omwaddon` programmatically/offline (to skip the CS GUI) is **not documented and not supported by OpenMW**. OpenMW-CS is GUI-only (no CLI/headless/batch mode; dialogue export/import was requested in GitLab #4108 / forum t=7034 but never shipped). Lua can't author records either: `world.createRecord` excludes `DIAL`/`INFO`/`JOUR`, `core.dialogue.*` is read-only, and `addJournalEntry(stage)` no-ops unless the journal record already exists. The only programmatic option is the **unofficial** `tes3conv` JSON round-trip (Greatness7) — not installed here, undocumented schema, no round-trip guarantees for dialogue (strict INAM/PNAM ordering), medium-to-high risk; the community uses it for version control, not dialogue authoring. **Decision: dialogue + journal records are entered manually in OpenMW-CS** using the field-by-field spec in work item #1.

> **Resonator-menu update (2026-06-01):** The resonator menu now has **Attune Resonator**, **Remove Enchantment**, and **Add Enchantment** options (runtime enchantment editing is supported as of OpenMW Lua API rev 131 — see `ENCHANTING_LIMITATION.md`). The **Attune** option is a *standalone* feature: it sets a persistent `attuned` flag in `global.lua` save data (exposed via `I.EnchantMachine.getAttuned()`), but only when the player is in `Akulakhan's Chamber` (the Heart of Lorkhan cell). It does **not** yet wire the stage-40 reward described below (Enchant→100 + power infusion) or consume the Vessel — that remains the work item #4 below. When the Array facility/cradle is built, the cradle handler can simply check/set this same flag (or advance the journal) instead of re-implementing location logic. The menu's Attune gates on the *vanilla* Heart cell; if the design instead wants the new custom Array cell, repoint `FINAL_CHAMBER_CELL` in `global.lua`.

## Design summary

The Dwemer boss already drops a Remote (the activator for the existing enchanting machine). We add a second loot item: a Dwemer scroll. The player can't read it at first — the in-game Book text describes looking at untranslatable Dwemer glyphs.

The scroll is translated by **Baladas Demnevanni** (Arvs-Drelen, Gnisis), but only once the player brings him a **translation key** (an existing or custom Dwemer volume — see open decisions). The translation reveals the device the player carries is a **"Resonance Vessel, Third Order"** — one of seven nodes of a larger Dwemer machine, the **Harmonics Array**, built to refine soul-energy and, at full harmonic alignment, perhaps to exert influence over the **Heart Chamber** itself, at Red Mountain. Baladas appends a warning: the Vessel may still be resonating with that place and "may not have entirely forgotten."

The player then seeks the **facility** that houses the Array (adjoining the Heart Chamber), fights through it, sets the Vessel into the one empty cradle (seven cradles, six filled), and **attunes** the resonator. The machine wakes; the player is joined to the Heart, gaining their reward **here** — Enchant skill to 100 plus a power infusion. Reporting back to Baladas concludes the quest: he is shaken to awe and resolves to prepare for his own journey, which may take decades.

## Journal — EM_DwemerDiscovery (record Name: "The Resonance Vessel")

Five stages, increments of 10, finisher at 50. All five are entered in the omwaddon.

| Index | Stage | Finishes? | Beat |
|---|---|---|---|
| 10 | 10 | No | Obtained the scroll; unreadable; seek a Dwemeris reader |
| 20 | 20 | No | Brought to Baladas; can't read without a translation key |
| 30 | 30 | No | Baladas translates it (Resonance Vessel / Array / Heart Chamber + warning) |
| 40 | 40 | No | Attuned the Array at the facility; gained the power |
| 50 | 50 | **Yes** | Reported back to Baladas; quest complete |

## Remaining work

### 1. Baladas dialogue — TWO topics: `Dwemer scroll` then `Resonance Vessel`

**Mechanics confirmed against the OpenMW-CS manual** (`docs/source/manuals/openmw-cs/tables-characters.rst`): a **Topic** owns unlimited **Topic Infos**; each info carries an Info-Conditions table (Actor / Disposition / Journal / Item rows) plus a **Script** (result) field; the engine fires the **first** info (top→bottom) whose conditions all pass; the result-script command form is `Journal, "QuestID", Index`. First-match ordering means **highest journal stage sits at the TOP** of each topic's info list.

**Two-topic design (DECIDED 2026-05-29).** The spine *evolves* as the player learns what they hold:
- **`Dwemer scroll`** — the pre-translation topic. Player knows this term from the start; covers stages 10 → 20 → 30 (getting Baladas to read it).
- **`Resonance Vessel`** — the post-translation topic. The player only learns this name when Baladas translates the scroll, so it's `AddTopic`'d **inside the translation result script** (Topic A info #2). Covers stages 30 → 40 → 50 (the mission and the report-back).

Both topics target `Actor = BM_Baladas`. Naming matches the prose: **`Resonance Vessel`** (the object the player carries), not "Dwemer Resonator". (If you'd rather the post-translation topic be about the destination, `Harmonics Array` also fits — but `Resonance Vessel` matches what's in their inventory.)

#### Topic bootstrap — a Baladas greeting that runs `AddTopic "Dwemer scroll"`

Lua has no API to add a dialogue topic (`AddTopic` is mwscript only), and a topic stays invisible until added or seen in text. A high-priority greeting info on Baladas surfaces the first topic:

| Greeting info (sits above his normal greetings) | |
|---|---|
| Conditions | `Actor BM_Baladas` + `Item em_dwemer_scroll_encoded >= 1` + `Journal EM_DwemerDiscovery >= 10` + `Journal EM_DwemerDiscovery < 20` |
| Response | e.g. *"You carry something old — Dwemer-made, and a long way from where it was forged. May I see it?"* |
| Script | `AddTopic "Dwemer scroll"` |

The `< 20` upper bound retires the greeting once the player has raised the topic (which sets journal 20). Re-fires harmlessly if they walk away without clicking.

#### Topic A — `Dwemer scroll` (stages 10 → 20 → 30), top→bottom

| # | Conditions | Result script | Purpose |
|---|---|---|---|
| A1 | `Journal EM_DwemerDiscovery >= 30` | none | Post-translation redirect: "I've set down all I can read — the **Vessel** itself is what matters now." (points the player at the new topic) |
| A2 | `Disposition >= 60` + `Item em_dwemer_scroll_encoded >= 1` + `Journal MG_Dwarves >= 70` | `Journal "EM_DwemerDiscovery" 30` + scroll swap (below) + `AddTopic "Resonance Vessel"` | Baladas can read it → translates + warns; **hands off to the new topic** |
| A3 | `Disposition >= 60` + `Item em_dwemer_scroll_encoded >= 1` | `Journal "EM_DwemerDiscovery" 20` | Can't read it yet → "not without some kind of translation key" |

- A2 above A3: both need the encoded scroll + Disposition 60; A2 adds the `MG_Dwarves >= 70` gate. Until MG_Dwarves ≥ 70 the player falls through to A3 (re-sets journal 20 harmlessly).
- A1 above both: once journal ≥ 30 it intercepts so the player never re-triggers translation; it redirects them to `Resonance Vessel`. (The full translated text also lives permanently in the `em_dwemer_scroll_decoded` book.)
- **Scroll swap is MANDATORY in A2's result script** — the decoded book is what the cradle activator checks for at the facility:
  ```
  Player->RemoveItem "em_dwemer_scroll_encoded" 1
  Player->AddItem "em_dwemer_scroll_decoded" 1
  AddTopic "Resonance Vessel"
  ```
  After the swap, A2/A3's `Item em_dwemer_scroll_encoded` conditions go false — fine, A1 (`>= 30`) intercepts above them.

#### Topic B — `Resonance Vessel` (stages 30 → 40 → 50), top→bottom

Added by A2's `AddTopic`; invisible until then.

| # | Conditions | Result script | Purpose |
|---|---|---|---|
| B1 | `Journal EM_DwemerDiscovery >= 50` | none | Post-quest farewell line |
| B2 | `Journal EM_DwemerDiscovery >= 40` | `Journal "EM_DwemerDiscovery" 50` | Report-back / awe conclusion |
| B3 | `Journal EM_DwemerDiscovery >= 30` | none | Reminder: reach the facility, go prepared, leave nothing out |

- B3 is the default state right after translation; B2 fires when the player returns having attuned the Array (journal 40) and advances to 50; B1 is the finished-quest farewell.
- **Cradle coupling:** because of the mandatory swap, the facility cradle activator (work item #4) must check for `em_dwemer_scroll_decoded` and consume *that* item.
- B2 can instead be written as a **greeting** gated on `Journal >= 40` if you'd rather Baladas speak first when the player walks in changed — say so and it'll be rewritten as a greeting condition.

#### Per-info build spec (CS fields + draft response prose)

Each block below is one Topic Info record. **Filter fields** (Actor, Disposition) are the structured columns on the info; **Info Conditions** are rows in the info's condition sub-table (Function = `Journal`/`Item`, with ID, relation, value); **Result** is the Script field (mwscript, blank = none); **Response** is the spoken text. Disposition is a *minimum* threshold — enter `60`, the engine treats it as "≥ 60". Prose is a **draft** — revise freely; it just needs to match the journal voice.

**GREETING — surfaces the first topic**
- Topic: `Greeting` (place above his generic greetings) · Actor: `BM_Baladas` · Disposition: — (ungated, so it fires even at low rapport)
- Info Conditions: `Item "em_dwemer_scroll_encoded" >= 1` · `Journal "EM_DwemerDiscovery" >= 10` · `Journal "EM_DwemerDiscovery" < 20`
- Result: `AddTopic "Dwemer scroll"`
- Response (draft): *"A moment. You carry something I have not seen the like of in a long age — Dwemer work, and not trinketry; it pulls at the air around it. Permit an old man his curiosity. Ask me about the **Dwemer scroll**."*

---

**A3 — "I can't read it yet" (sets journal 20)**
- Topic: `Dwemer scroll` · Actor: `BM_Baladas` · Disposition: `60`
- Info Conditions: `Item "em_dwemer_scroll_encoded" >= 1`
- Result: `Journal "EM_DwemerDiscovery" 20`
- Response (draft): *"A record, etched rather than written, in a hand no living scholar reads fluently — whatever the Mages Guild may pretend. I can see it is a specification of some kind. What it specifies, I cannot yet tell you: I lack the key. Their tongue is reconstructed piecemeal, from cross-referenced volumes, and I do not have enough of them to hand. Bring me more of their writings — proper scholarly texts, not market curiosities — and I may yet make this speak."*

**A2 — translates (sets journal 30, swaps scroll, opens new topic)** · *sits ABOVE A3*
- Topic: `Dwemer scroll` · Actor: `BM_Baladas` · Disposition: `60`
- Info Conditions: `Item "em_dwemer_scroll_encoded" >= 1` · `Journal "MG_Dwarves" >= 70`  *(verify the 70 stage — see §2)*
- Result:
  ```
  Journal "EM_DwemerDiscovery" 30
  Player->RemoveItem "em_dwemer_scroll_encoded" 1
  Player->AddItem "em_dwemer_scroll_decoded" 1
  AddTopic "Resonance Vessel"
  ```
- Response (draft): *"You have been busy. The volumes you brought me these past weeks will serve. ... It is done — I have written the translation out in full; keep it. But hear the substance from me, for the page does not carry what I feel about it. The thing you hold is no enchanter's trinket. It is a component — a 'Resonance Vessel,' it names itself — one of seven, part of a far larger engine the Dwemer called a Harmonics Array. The Array was built beside a place at Red Mountain I will not name twice. And I believe your Vessel still listens for that place. Do not go near the facility unprepared, if you go at all — and if you go and live, come back and tell me everything. Ask me about the **Resonance Vessel** when you are ready."*

**A1 — post-translation redirect (no journal change)** · *sits ABOVE A2/A3 (intercepts once journal ≥ 30)*
- Topic: `Dwemer scroll` · Actor: `BM_Baladas` · Disposition: —
- Info Conditions: `Journal "EM_DwemerDiscovery" >= 30`
- Result: *(none)*
- Response (draft): *"You have my translation, and the scroll itself; there is nothing further I can wring from the page. It is the Vessel that should occupy you now — what it is, and what it is part of. Ask me about the **Resonance Vessel**."*

> **Topic A order (top→bottom): A1, A2, A3.** A1 (`>= 30`) intercepts after translation so A2 never re-fires; A2 (with the `MG_Dwarves` gate) sits above A3 so the can-translate path wins once the books are delivered.

---

**B3 — reminder / default after translation (no journal change)**
- Topic: `Resonance Vessel` · Actor: `BM_Baladas` · Disposition: —
- Info Conditions: `Journal "EM_DwemerDiscovery" >= 30`
- Result: *(none)*
- Response (draft): *"The Resonance Vessel. I have said what I can of the thing and the place it wishes to return to; I will only repeat myself. Do not go to that facility ill-prepared. Whatever the Dwemer left guarding the Array, the centuries will not have gentled it — to say nothing of who keeps that mountain now. Go ready, or do not go."*

**B2 — report-back / awe conclusion (sets journal 50)** · *sits ABOVE B3*
- Topic: `Resonance Vessel` · Actor: `BM_Baladas` · Disposition: —
- Info Conditions: `Journal "EM_DwemerDiscovery" >= 40`
- Result: `Journal "EM_DwemerDiscovery" 50`
- Response (draft): *"You went. And you came back. ... Give me your account. ... I have lived more than two thousand years on this island, and made it my discipline never to be impressed; I will set that discipline down a moment. No one has been joined to the Heart as you now are — no one will be again, and I will see the manner of it recorded so that none are fool enough to try. As for me: I will go and see this place properly, with the care its builders would have demanded. It may take me decades to prepare. I find I do not mind. Some work is worth doing slowly."*

**B1 — post-quest farewell (no journal change)** · *sits ABOVE B2*
- Topic: `Resonance Vessel` · Actor: `BM_Baladas` · Disposition: —
- Info Conditions: `Journal "EM_DwemerDiscovery" >= 50`
- Result: *(none)*
- Response (draft): *"The honed one — still walking the world, I see. I am still preparing; do not look so impatient, it has been but a moment as I reckon time. When I have what I need, I will follow where you led. Until then, carry it well."*

> **Topic B order (top→bottom): B1, B2, B3.** Highest journal stage on top, as everywhere.

### 2. The translation gate (the 20 → 30 gate) — DECIDED 2026-05-29

**No separate fetch item.** The "translation key" is the player having already gotten *Mystery of the Dwarves* far enough that Baladas has the Dwemer volumes he needs. So the gate on dialogue #4 is:
- `Item em_dwemer_scroll_encoded >= 1` (player is carrying the scroll), **and**
- `Journal MG_Dwarves >= 70` (Baladas has been given / has translated the books — see verify note), **and**
- `Disposition >= 60`.

Until `MG_Dwarves >= 70`, the player falls through to dialogue #5 (sets journal 20). Narratively this is clean: Baladas can read Dwemeris only after the player has supplied him the Dwemer texts in the vanilla quest.

> **Verify in OpenMW-CS:** confirm `MG_Dwarves` is the right quest ID and that **70** is the "books delivered to / translated by Baladas" stage (the prior 76a53714 session believed so). Adjust the index if CS shows a different stage. The vanilla Baladas "Divine Metaphysics" / "Egg of Time" dialogue (pasted in the 2026-05-28 session) has an "already brought the books to Baladas" state — that is the stage to match.

### 3. The facility / dungeon (the 30 → 40 stage) — DECIDED 2026-05-29

- A new interior cell for the Harmonics Array hall, **accessed off the Heart Chamber within the Red Mountain / Dagoth Ur facility** (a hidden door beyond Dagoth Ur's defenses — "a place that mad demigod himself may never have known was there," per the stage-50 entry). Reachable during/after the main-quest approach to Dagoth Ur.
- The Array: seven cradles, six filled, one empty (the activator).
- Populate the approach with "Dagoth Ur's defenses" (ash creatures, traps, etc.) — much is already present in the vanilla facility cells the new cell hangs off of.

### 4. Array activator + reward script (fires journal 40 + the power) — OPEN DECISION #3

An activator on the empty cradle. On activate, the script should:
- check the player carries the Vessel — i.e. `Item em_dwemer_scroll_decoded >= 1` (the decoded scroll, post-Baladas-swap; the encoded one never reaches here),
- remove/place the Vessel into the cradle (consume `em_dwemer_scroll_decoded`),
- set Enchant skill to 100,
- apply the power infusion — **OPEN DECISION #3: what exactly beyond Enchant 100?** (e.g. Fortify Magicka, a constant-effect ability, resist something),
- `Journal "EM_DwemerDiscovery" 40`.

This is where the reward lives now (not in Baladas dialogue).

### 5. Playtest the full chain

scroll loot → can't-read (needs MG_Dwarves progress) → Baladas translates once MG_Dwarves ≥ 70 (30) → facility off the Heart Chamber → attune cradle (40, reward) → return to Baladas (50, finish).

## Final prose (as entered in the omwaddon)

### Encoded scroll text (Book A — `em_dwemer_scroll_encoded`)

> You hold an ancient scroll, brittle but unbroken by the centuries. The material is not quite parchment, not quite metal, something between the two, as though the Dwemer could not bring themselves to trust a thing that might rot or burn. Its surface bears glyphs etched in tarnished bronze ink, angular and precise, each stroke made by a hand that never doubted itself.
>
> You turn it carefully. The glyphs seem to shift when you look away, always settling back into their positions just as your eyes return, as though they are watching you watch them. To your untrained eye they offer nothing. And yet there is a weight to them beyond the scroll's physical measure, a sense of compressed meaning, like a gear under tension, waiting.
>
> You recognize the shape of purpose, if not its content. Measurement. Sequence. Instructions for something built, or something yet to be built. The Dwemer did not make things idly.
>
> The ink, if it is ink, does not reflect light so much as hold it briefly before letting go.

### Decoded scroll text (Book B — `em_dwemer_scroll_decoded`)

> **[BALADAS DEMNEVANNI, TRANSLATION AND NOTES]**
> The following is set down by Baladas Demnevanni, of Gnisis. Translation is my own. My observations follow the body of the text.
>
> *Translated body of the scroll:*
> This component is designated Resonance Vessel, Third Order. It is one node of a larger system, the Harmonics Array, comprising no fewer than seven joined instruments designed to amplify and refine the binding potential of soul-energy drawn through them in sequence. A soul gem of complete charge, passed fully through the Vessel, will yield enchantments of a depth no single instrument could otherwise achieve. The Vessel functions in isolation. Reconnected to the Array, it transforms.
> The Array is housed in the facility adjoining the Heart Chamber. The Vessel currently in transit to Arkngthand for recalibration is to be returned there upon completion. Handle with care. The housing is more fragile than it appears.
> When all nodes are returned and the Array achieves full harmonic alignment, the result will exceed the calculations of any individual craftsman. We believe, though have not confirmed, that at full alignment the Array may permit influence over the resonance source itself. We do not speculate further. We recorded it because it was measured.
>
> *My notes, appended:*
> I have spent three days with this text and the volumes you brought me. I will be plain.
> The device you carry is not merely an enchanting aid. It is a component of something much larger, and that larger thing was built in proximity to a place I will not describe in full here, except to say that those who know Red Mountain well will understand what is meant by the Heart Chamber. Those who do not, I would suggest, should count themselves fortunate and remain that way.
> What troubles me most is this: drawing on the three volumes you provided, I believe this Vessel may already be resonating with that place in ways I cannot measure from Gnisis. The Dwemer built it to reconnect there. It may not have entirely forgotten.
> I would not go near that facility lightly. I would not go at all without exceptional preparation, and a clear sense of what you are walking into.
> If you do go, and if you survive what is down there, I want to know everything you find. Write it down if you must. Leave nothing out.
> Go carefully.
> Baladas Demnevanni
> Arvs-Drelen, Gnisis

### Journal — stage 10 (looted)

> I have come into possession of an ancient Dwemer scroll. The glyphs mean nothing to me, but the thing has a weight to it — clearly an instruction or a record of some kind. I should find someone who can read Dwemeris.

### Journal — stage 20 (brought to Baladas, no key)

> I brought the Dwemer scroll to Baladas Demnevanni at Arvs-Drelen in Gnisis. He turned it over with interest, but shook his head — he cannot read the Dwemer tongue without some kind of translation key to work from. He told me that with the right volumes in hand he might be able to make sense of it, but as things stand the glyphs are closed to him. I should seek out the texts he would need before returning.

### Journal — stage 30 (translated, with the warning)

> Baladas has finished translating the scroll. The device I carry is a "Resonance Vessel, Third Order" — one of seven components of a larger Dwemer machine, the Harmonics Array, built to refine soul-energy and, at full alignment, perhaps to exert influence over the Heart Chamber itself. The Array was housed in a facility beside that place, at Red Mountain; this Vessel was lost in transit to Arkngthand. Baladas warns it may still be resonating with the place it was built to return to, and that it "may not have entirely forgotten." He urges me not to approach the facility without exceptional preparation. If I go and survive, he wants a full account of everything I find.

### Journal — stage 40 (attuned the Array; power gained here)

> I have found the Harmonics Array, still standing in the halls where the Dwemer left it. Seven cradles, six of them filled — and one waiting. I set the Vessel into its place and attuned the resonator to the Array's main configuration. The machine woke. As it did, something passed between it and me, a connection I have no proper word for — and in that moment I simply understood, the way one understands one's own hand. The Array's purpose, the path of the soul-energy through it, the tone it reaches for at full alignment, and the thing it reaches toward: the Heart. I have been honed by it. My skill at the enchanter's craft is sharpened to its very peak, and more besides — I am carrying power of a kind that has not touched a living thing on Tamriel in ages. I shall document everything I have found here and return to Baladas. He will want to know what I now know.

### Journal — stage 50 (report back; quest finisher)

> I returned to Baladas with everything I had set down, and for the first time since I have known him the old wizard had nothing ready to say. He read in silence, and read again — and then he looked not at the pages but at me, and went still. Whatever lingers about me now, he felt it. When he finally spoke it was with something I had not expected from a man who has watched more than two thousand years pass over Vvardenfell: awe. I had walked through Dagoth Ur's own defenses, into a place that mad demigod himself may never have known was there, attuned the Array with my own hands, and come back whole and changed. No one, he said quietly, has ever been joined to the Heart in the way I now am. No one ever will be again — he would see to the telling of it, so that none would try. He told me he will begin preparing for his own journey to that place, though to do it properly, with the care the Dwemer themselves would have demanded, may take him decades. He does not seem troubled by the wait. Some things, he said, are worth doing slowly. My part is done.

## CS record specs (Book A / Book B)

Open `EnchantMachine.omwaddon` in OpenMW-CS.

| Field | Book A (encoded) | Book B (decoded) |
|---|---|---|
| ID | `em_dwemer_scroll_encoded` | `em_dwemer_scroll_decoded` |
| Name | `Dwemer Scroll (Untranslated)` | `Dwemer Scroll (Translated by Baladas Demnevanni)` |
| Model | A scroll mesh (e.g. `m\misc_scroll_01.nif`) | Same as A |
| Icon | A scroll icon (e.g. `m\tx_scroll_01.tga`) | Same as A |
| Is Scroll | ✓ | ✓ |
| Weight | `0.2` | `0.2` |
| Value | `50` | `250` |
| Enchantment | (empty) | (empty) |
| Text | "Encoded scroll text" above | "Decoded scroll text" above |

## Lua work

> **Design correction (2026-05-31):** the earlier plan used a CUSTOM `scroll.lua` with `onActivated` to detect pickup. **That doesn't work** — `onActivated` only fires for *world* activations (picking an item off the ground); **looting from a corpse is an inventory transfer and does not fire it**, and OpenMW has **no inventory-add engine handler** (verified in `engine_handlers.rst`). So stage 10 is detected by a **throttled inventory poll in the player script** instead. Consequences: **no `scroll.lua`, no new `.omwscripts` entry, and no save-schema bump** — the journal stage itself is the persistent state (`addJournalEntry` works in player scripts per `types.lua`).

**DONE (2026-05-31) — stage-10 trigger + scroll loot:**

1. ✅ **`global.lua`** — `createDwemerScroll()` added: directly instantiates the existing `em_dwemer_scroll_encoded` Book record via `world.createObject` (guarded if the record is missing). Exposed on the `EnchantMachine` interface. The debug **`EnchantMachine_GiveRemote`** handler now also gives the scroll.

2. ✅ **`spawn_researcher.lua`** — `spawnResearcher` drops the scroll into the boss inventory via `I.EnchantMachine.createDwemerScroll()`, after the remote.

3. ✅ **`player_full.lua`** — `checkScrollLooted()` runs in the throttled (~1 s) `onUpdate` block: if the player carries `em_dwemer_scroll_encoded`/`_decoded` and the quest is below stage 10, it calls `addJournalEntry(10)`; self-heals across loads by reading `quest.stage`; stops polling once done.
   - ⚠️ **Verify in playtest:** the quest key is hard-coded lowercase `em_dwemerdiscovery` (engine lower-cases content-file ids; OpenMW-CS shows `EM_DwemerDiscovery`). If the journal entry doesn't appear on looting, confirm the journal record id and adjust `SCROLL_QUEST_ID`.

**STILL TODO — the cradle reward (stage 40):** blocked on the facility cell (work item #3) and reward decision #3.

4. ⏳ **Array cradle activator handler** — on activate, verify the player carries `em_dwemer_scroll_decoded`, consume it, set Enchant→100 + the power infusion (decision #3), `addJournalEntry(40)`. **This** is the piece that still needs a save-flag (reward-claimed) + schema bump — add it when building the cradle, not before. The activator object/cell come from CS first.

> Note: stages 20, 30, and 50 are driven by **Baladas dialogue result scripts (mwscript)**, not Lua (now entered in CS). Lua handles only pickup (10) and the cradle reward (40). The translation gate is the dialogue's `Item em_dwemer_scroll_encoded` + `Journal MG_Dwarves >= 70` + `Disposition >= 60` conditions — no separate fetch item.

## Open decisions (blockers for the remaining build)

1. ~~Translation key~~ — **DECIDED:** no fetch item; gate is scroll-in-inventory + `Journal MG_Dwarves >= 70` (Baladas has the books) + Disposition ≥ 60. *(Verify the exact MG_Dwarves stage in CS.)*
2. ~~Facility location~~ — **DECIDED:** new interior cell off the Heart Chamber, inside the Red Mountain / Dagoth Ur facility.
3. **Reward** — Enchant→100 plus *what* exactly (the power infusion)? *(User deferred — to decide later.)*

## Notes for future me

- `types.Player.quests(player)["EM_DwemerDiscovery"]:addJournalEntry(stage)` silently does nothing if the omwaddon lacks a record at that stage — no crash, just no journal entry.
- The PLAYER script is the natural place to read quest state (PLAYER context, `self.object`); a GLOBAL handler must use its `actor` parameter, e.g. `types.Player.quests(actor)[...]`.
- Dialogue ordering: top→bottom, first match wins — keep the highest journal-stage condition at the top of the stack.
